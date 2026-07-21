defmodule ApiHarness.Agent.Context.Providers.DomainMemory do
  @moduledoc "Provides domain-category persistent memories within budget."
  @behaviour ApiHarness.Agent.Context.Providers.Behaviour

  alias ApiHarness.LLM.TokenCounter
  alias ApiHarness.Memory

  @impl true
  def plan(opts) do
    user_id = opts[:user_id]
    memories = Memory.list_persistent_memories_by_category(user_id, "domain")
    total = memories |> Enum.map(&entry_tokens/1) |> Enum.sum()
    %{full: total, essential: 0}
  end

  @impl true
  def provide(budget, opts) do
    user_id = opts[:user_id]
    memories = Memory.list_persistent_memories_by_category(user_id, "domain")

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

  defp entry_tokens(%{token_count: tc}) when is_integer(tc) and tc > 0, do: tc
  defp entry_tokens(%{content: c}), do: TokenCounter.count(c)
end
