defmodule ApiHarness.Agent.ContextBuilder do
  @moduledoc """
  Assembles the six-layer prompt for the LLM (FR-022, research §9).

  Layer ordering (mapped to OpenAI chat messages):

    1. System instruction — the legal-domain agent role
    2. Domain memories — `domain` category persistent memories (FR-022-A)
    3. Session memory — current thread's JSON state
    4. Relevant persistent memory — `user` + `task` categories, top-K via pgvector (FR-022-A)
    5. Recent conversation messages — windowed (configurable, default 10)
    6. Current user question

  Layers 1–4 are folded into a single `system` message. Layer 5 provides prior
  `user`/`assistant` turns. Layer 6 is the final `user` message.
  """

  alias ApiHarness.Accounts.User
  alias ApiHarness.Chats
  alias ApiHarness.Chats.Chat
  alias ApiHarness.Memory
  alias ApiHarness.Memory.Retriever

  @system_instruction """
  You are an expert legal assistant for Brazilian law. You have deep knowledge of
  labor law (direito trabalhista), civil law, consumer protection, and procedural law.
  Provide accurate, clear, and well-structured legal guidance. When relevant, cite the
  applicable legislation, articles, and jurisprudence. Always clarify when a matter
  requires consultation with a qualified attorney.
  """

  # Session memory `state` category keys (spec 002, data-model.md) rendered as
  # labeled sections in that order, using only each entry's `content` — internal
  # `id`s are never leaked into the prompt.
  @session_category_labels [
    {"goal", "Goal"},
    {"fact", "Facts"},
    {"constraint", "Constraints"},
    {"preference", "Preferences"}
  ]

  @doc """
  Build the prompt message list for `user`, `chat`, and the current `question`.
  Returns a list of `%{role: ..., content: ...}` maps ready for the LLM.
  """
  @spec build(User.t(), Chat.t(), String.t()) :: [map()]
  def build(%User{} = user, %Chat{} = chat, question) when is_binary(question) do
    window = Application.get_env(:api_harness, :agent)[:recent_messages_window] || 10

    domain_memories = Memory.list_persistent_memories_by_category(user.id, "domain")
    session_memory = Memory.get_session_memory(chat.id)
    user_task_memories = retrieve_relevant_memories(user.id, question)
    recent_messages = Chats.list_recent_messages(chat, window)

    system_content =
      build_system_message(domain_memories, session_memory, user_task_memories)

    prior_turns = Enum.map(recent_messages, &%{role: &1.role, content: &1.content})

    [%{role: "system", content: system_content}] ++
      prior_turns ++
      [%{role: "user", content: question}]
  end

  defp build_system_message(domain_memories, session_memory, user_task_memories) do
    parts = [@system_instruction]

    parts =
      if domain_memories != [] do
        knowledge = Enum.map_join(domain_memories, "\n", & &1.content)
        parts ++ ["\n## Domain Knowledge\n#{knowledge}"]
      else
        parts
      end

    parts =
      case render_session_memory(session_memory) do
        nil -> parts
        rendered -> parts ++ ["\n## Current Session Context\n#{rendered}"]
      end

    parts =
      if user_task_memories != [] do
        knowledge = Enum.map_join(user_task_memories, "\n", & &1.content)
        parts ++ ["\n## Relevant User & Task Context\n#{knowledge}"]
      else
        parts
      end

    Enum.join(parts, "\n")
  end

  # Layer 3 (spec 002, FR-005): render each non-empty category as a labeled
  # section built from entry `content` only. Returns `nil` when there is
  # nothing to render (no session memory yet, or all categories empty).
  defp render_session_memory(%{state: state}) when map_size(state) > 0 do
    sections =
      for {key, label} <- @session_category_labels,
          entries = Map.get(state, key, []),
          entries != [] do
        contents = Enum.map_join(entries, "\n", &"- #{&1["content"]}")
        "**#{label}:**\n#{contents}"
      end

    case sections do
      [] -> nil
      _ -> Enum.join(sections, "\n")
    end
  end

  defp render_session_memory(_), do: nil

  # Layer 4 (FR-022-A): retrieve user + task category memories by semantic similarity.
  # Falls back to all memories in those categories if pgvector retrieval fails
  # (e.g., before embeddings are populated).
  defp retrieve_relevant_memories(user_id, question) do
    case Retriever.retrieve(user_id, question, k: 5, category: nil) do
      {:ok, memories} ->
        Enum.filter(memories, &(&1.category in ["user", "task"]))

      {:error, _} ->
        Memory.list_persistent_memories_by_category(user_id, "user") ++
          Memory.list_persistent_memories_by_category(user_id, "task")
    end
  end
end
