defmodule ApiHarness.Agent.Context.Providers.PersistentMemory do
  @moduledoc "Provides user+task category persistent memories within budget using pgvector retrieval."
  @behaviour ApiHarness.Agent.Context.Providers.Behaviour

  alias ApiHarness.LLM.TokenCounter
  alias ApiHarness.Memory
  alias ApiHarness.Memory.Retriever

  @impl true
  def plan(opts) do
    memories = fetch_memories(opts[:user_id], opts[:question])
    total = memories |> Enum.map(&entry_tokens/1) |> Enum.sum()
    %{full: total, essential: 0}
  end

  @impl true
  def provide(budget, opts) do
    memories = fetch_memories(opts[:user_id], opts[:question])

    {lines, used} =
      Enum.reduce_while(memories, {[], 0}, fn mem, {acc, total} ->
        t = entry_tokens(mem)

        if total + t <= budget do
          {:cont, {[mem.content | acc], total + t}}
        else
          {:halt, {acc, total}}
        end
      end)

    if lines == [] do
      {"", 0}
    else
      content = lines |> Enum.reverse() |> Enum.join("\n")
      {content, used}
    end
  end

  defp fetch_memories(user_id, question) do
    case Retriever.retrieve(user_id, question, k: 5, category: nil) do
      {:ok, memories} ->
        Enum.filter(memories, &(&1.category in ["user", "task"]))

      {:error, _} ->
        Memory.list_persistent_memories_by_category(user_id, "user") ++
          Memory.list_persistent_memories_by_category(user_id, "task")
    end
  end

  defp entry_tokens(%{token_count: tc}) when is_integer(tc) and tc > 0, do: tc
  defp entry_tokens(%{content: c}), do: TokenCounter.count(c)
end
