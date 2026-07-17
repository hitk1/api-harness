defmodule ApiHarness.Memory.SessionReconciler do
  @moduledoc """
  Decides what to do with each turn-extracted candidate against a chat
  thread's categorized session memory (spec 002, FR-003, FR-008).

  For each candidate the reconciler:
    1. Looks at the existing entries already stored under `state[kind]` for
       the chat (`kind` doubles as the session-memory category — goal, fact,
       constraint, preference — per data-model.md).
    2. If the category is empty, the candidate is a `create` — no LLM call
       needed.
    3. Otherwise, an LLM call decides: create (unrelated to any existing
       entry) / update (refines one entry) / merge (combine with one entry) /
       discard (not meaningfully useful to retain).

  Unlike persistent-memory's `Reconciler`, the `"durable"` flag from
  extraction is ignored here — information not durable enough for
  persistent memory can still be exactly right for one thread's lifetime
  (research.md §4).
  """

  alias ApiHarness.LLM.Provider
  alias ApiHarness.Memory

  @session_categories ~w(goal fact constraint preference)

  @reconciliation_schema %{
    type: "object",
    properties: %{
      action: %{type: "string", enum: ["create", "update", "merge", "discard"]},
      id: %{type: ["string", "null"]},
      content: %{type: "string"}
    },
    required: ["action", "id", "content"],
    additionalProperties: false
  }

  @doc """
  Reconcile a list of extracted `candidates` (as produced by
  `ApiHarness.Memory.Extractor.extract/1`) against `chat_id`'s existing
  session memory. Returns `{:ok, annotated_candidates}` where each candidate
  gains an `"action"` field (`create | update | merge | discard`) and, for
  `update`/`merge`, an `"id"` identifying the target existing entry.
  """
  @spec reconcile(integer(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def reconcile(chat_id, candidates) when is_list(candidates) do
    state =
      case Memory.get_session_memory(chat_id) do
        nil -> %{}
        session_memory -> session_memory.state
      end

    results = Enum.map(candidates, &reconcile_candidate(state, &1))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, results}
    else
      {:error, hd(errors)}
    end
  end

  defp reconcile_candidate(state, candidate) do
    kind = candidate["kind"]

    if kind in @session_categories do
      case Map.get(state, kind, []) do
        [] -> candidate |> Map.put("action", "create") |> Map.put("id", nil)
        entries -> decide_action(candidate, entries)
      end
    else
      candidate |> Map.put("action", "discard") |> Map.put("id", nil)
    end
  end

  defp decide_action(candidate, entries) do
    existing_text =
      Enum.map_join(entries, "\n", fn %{"id" => id, "content" => content} ->
        "- id=#{id}: #{content}"
      end)

    messages = [
      %{
        role: "system",
        content: """
        You reconcile new information about the current conversation thread against
        information already captured for the same category ("#{candidate["kind"]}").

        Existing entries:
        #{existing_text}

        New information: "#{candidate["content"]}"

        Decide exactly one action:
          - "create": unrelated to any existing entry — a new entry should be added.
          - "update": refines or corrects one existing entry — replace its content.
          - "merge": overlaps with one existing entry — combine both into one entry.
          - "discard": not meaningfully useful to retain (small talk, already redundant).

        For "update" or "merge", set "id" to the target existing entry's id and
        "content" to the resulting content. For "create", set "id" to null and
        "content" to the new information. For "discard", "id" may be null.
        """
      },
      %{role: "user", content: "What action should be taken?"}
    ]

    opts = [json_schema: @reconciliation_schema, schema_name: "session_reconciliation"]

    case Provider.chat_completion(messages, opts) do
      {:ok, %{"action" => action, "content" => content} = result} ->
        candidate
        |> Map.put("action", action)
        |> Map.put("content", content)
        |> Map.put("id", Map.get(result, "id"))

      {:ok, _} ->
        candidate |> Map.put("action", "create") |> Map.put("id", nil)

      {:error, _} ->
        candidate |> Map.put("action", "create") |> Map.put("id", nil)
    end
  end
end
