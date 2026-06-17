defmodule ApiHarness.Memory.Reconciler do
  @moduledoc """
  Decides what to do with each extracted knowledge candidate (FR-019, research §10).

  For each candidate the Reconciler:
    1. Retrieves the nearest existing persistent memory (pgvector).
    2. Calls the LLM to decide: create / update / merge / discard.
    3. Discards non-durable candidates automatically.
    4. Returns annotated candidates ready for `Memory.apply_reconciliation/2`.

  The goal is to avoid blind append (FR-017) while maintaining complete audit
  trails (`memory_context_updates`).
  """

  alias ApiHarness.LLM.Provider
  alias ApiHarness.Memory.Retriever

  @reconciliation_schema %{
    type: "object",
    properties: %{
      action: %{type: "string", enum: ["create", "update", "merge", "discard"]},
      content: %{type: "string"}
    },
    required: ["action", "content"],
    additionalProperties: false
  }

  @doc """
  Reconcile a list of extracted `candidates` for `user_id`.
  Returns `{:ok, annotated_candidates}` where each candidate has an `"action"`
  field set to one of `create | update | merge | discard`.
  """
  @spec reconcile(integer(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def reconcile(user_id, candidates) when is_list(candidates) do
    results =
      Enum.map(candidates, fn candidate ->
        if candidate["durable"] == false do
          Map.put(candidate, "action", "discard")
        else
          reconcile_candidate(user_id, candidate)
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, results}
    else
      {:error, hd(errors)}
    end
  end

  defp reconcile_candidate(user_id, candidate) do
    content = candidate["content"]

    case Retriever.retrieve(user_id, content, k: 1, category: candidate["category"]) do
      {:ok, []} ->
        Map.put(candidate, "action", "create")

      {:ok, [nearest | _]} ->
        decide_action(candidate, nearest)

      {:error, _reason} ->
        # On retrieval failure, default to create to avoid data loss.
        Map.put(candidate, "action", "create")
    end
  end

  defp decide_action(candidate, nearest) do
    messages = [
      %{
        role: "system",
        content: """
        You decide how to reconcile a new piece of knowledge with an existing memory.
        Existing: "#{nearest.content}"
        New: "#{candidate["content"]}"
        Actions: create (no overlap), update (replaces existing), merge (combine both), discard (duplicate/irrelevant).
        """
      },
      %{role: "user", content: "What action should be taken? Provide the merged/updated content."}
    ]

    opts = [json_schema: @reconciliation_schema, schema_name: "memory_reconciliation"]

    case Provider.chat_completion(messages, opts) do
      {:ok, %{"action" => action, "content" => content}} ->
        candidate
        |> Map.put("action", action)
        |> Map.put("content", content)
        |> then(fn c ->
          if action in ["update", "merge"], do: Map.put(c, "id", nearest.id), else: c
        end)

      {:ok, _} ->
        Map.put(candidate, "action", "create")

      {:error, _} ->
        Map.put(candidate, "action", "create")
    end
  end
end
