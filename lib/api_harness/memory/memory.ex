defmodule ApiHarness.Memory do
  @moduledoc """
  Memory context API — session memory and persistent memory operations (US4).

  Session memory is scoped per chat thread (FR-014) and, since spec 002,
  categorized into goal/fact/constraint/preference entries reconciled by
  `ApiHarness.Memory.SessionReconciler` and applied via
  `apply_session_reconciliation/2` — see
  `specs/002-session-memory-categorization/data-model.md`. Persistent memory
  is per-user and managed by the async pipeline (FR-016, FR-017).
  """
  import Ecto.Query

  alias ApiHarness.Memory.{PersistentMemory, SessionMemory}
  alias ApiHarness.Repo

  # ---------------------------------------------------------------------------
  # Session Memory
  # ---------------------------------------------------------------------------

  @doc "Fetch the session memory for `chat_id`. Returns `nil` if not found."
  @spec get_session_memory(integer()) :: SessionMemory.t() | nil
  def get_session_memory(chat_id), do: Repo.get_by(SessionMemory, chat_id: chat_id)

  @doc "Update (merge) the session memory `state` for `chat_id`."
  @spec update_session_memory(integer(), map()) ::
          {:ok, SessionMemory.t()} | {:error, Ecto.Changeset.t()}
  def update_session_memory(chat_id, new_state) when is_map(new_state) do
    case get_session_memory(chat_id) do
      nil ->
        %SessionMemory{chat_id: chat_id}
        |> SessionMemory.changeset(%{state: new_state})
        |> Repo.insert()

      existing ->
        existing
        |> SessionMemory.changeset(%{state: Map.merge(existing.state, new_state)})
        |> Repo.update()
    end
  end

  @doc """
  Apply a session-memory reconciliation decision (`ApiHarness.Memory.SessionReconciler`)
  to `chat_id`'s categorized `state[kind]` (spec 002, FR-003). Mirrors
  `apply_reconciliation/2` for persistent memory, but targets one category/entry
  within the single `session_memories` jsonb row instead of a separate table row
  (data-model.md).

  `candidate` MUST have `"action"` (`create | update | merge | discard`) and
  `"kind"` keys; `"update"`/`"merge"` also require an `"id"` targeting the
  existing entry, and all but `"discard"` require `"content"`.
  """
  @spec apply_session_reconciliation(integer(), map()) ::
          {:ok, SessionMemory.t()} | {:error, Ecto.Changeset.t()}
  def apply_session_reconciliation(chat_id, %{"action" => action, "kind" => kind} = candidate) do
    case get_session_memory(chat_id) do
      nil ->
        new_state = apply_session_action(%{}, kind, action, candidate)

        %SessionMemory{chat_id: chat_id}
        |> SessionMemory.changeset(%{state: new_state})
        |> Repo.insert()

      existing ->
        new_state = apply_session_action(existing.state, kind, action, candidate)

        existing
        |> SessionMemory.changeset(%{state: new_state})
        |> Repo.update()
    end
  end

  defp apply_session_action(state, kind, action, candidate) do
    entries = Map.get(state, kind, [])

    new_entries =
      case action do
        "create" ->
          entries ++ [%{"id" => Ecto.UUID.generate(), "content" => candidate["content"]}]

        action when action in ["update", "merge"] ->
          replace_session_entry(entries, candidate["id"], candidate["content"])

        _ ->
          entries
      end

    Map.put(state, kind, new_entries)
  end

  defp replace_session_entry(entries, id, content) do
    Enum.map(entries, fn
      %{"id" => ^id} = entry -> Map.put(entry, "content", content)
      entry -> entry
    end)
  end

  # ---------------------------------------------------------------------------
  # Persistent Memory
  # ---------------------------------------------------------------------------

  @doc "List all persistent memories for `user_id`."
  @spec list_persistent_memories(integer()) :: [PersistentMemory.t()]
  def list_persistent_memories(user_id) do
    Repo.all(from pm in PersistentMemory, where: pm.user_id == ^user_id)
  end

  @doc "List persistent memories for `user_id` filtered by `category`."
  @spec list_persistent_memories_by_category(integer(), String.t()) :: [PersistentMemory.t()]
  def list_persistent_memories_by_category(user_id, category) do
    Repo.all(
      from pm in PersistentMemory,
        where: pm.user_id == ^user_id and pm.category == ^category
    )
  end

  @doc """
  Apply a reconciliation action (create/update/merge/discard) to a persistent
  memory candidate. Writes a `MemoryContextUpdate` audit row for every
  non-discard action.
  """
  @spec apply_reconciliation(integer(), map()) ::
          {:ok, PersistentMemory.t() | nil} | {:error, term()}
  def apply_reconciliation(user_id, %{"action" => action} = candidate) do
    case action do
      "create" -> create_persistent_memory(user_id, candidate)
      "update" -> update_persistent_memory(candidate)
      "merge" -> merge_persistent_memory(candidate)
      "discard" -> {:ok, nil}
      _ -> {:error, {:unknown_action, action}}
    end
  end

  defp create_persistent_memory(user_id, candidate) do
    tc = ApiHarness.LLM.TokenCounter.count(candidate["content"] || "")

    %PersistentMemory{user_id: user_id, token_count: tc}
    |> PersistentMemory.changeset(candidate)
    |> Repo.insert()
  end

  defp update_persistent_memory(%{"id" => id} = candidate) do
    case Repo.get(PersistentMemory, id) do
      nil ->
        {:error, :not_found}

      pm ->
        tc = ApiHarness.LLM.TokenCounter.count(candidate["content"] || pm.content)

        pm
        |> Ecto.Changeset.change(%{token_count: tc})
        |> PersistentMemory.changeset(candidate)
        |> Repo.update()
    end
  end

  defp update_persistent_memory(_), do: {:error, :missing_id}

  defp merge_persistent_memory(%{"id" => id} = candidate) do
    case Repo.get(PersistentMemory, id) do
      nil ->
        {:error, :not_found}

      pm ->
        merged_content = Map.get(candidate, "content", pm.content)
        tc = ApiHarness.LLM.TokenCounter.count(merged_content)

        pm
        |> Ecto.Changeset.change(%{token_count: tc})
        |> PersistentMemory.changeset(%{"content" => merged_content})
        |> Repo.update()
    end
  end

  defp merge_persistent_memory(_), do: {:error, :missing_id}
end
