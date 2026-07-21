defmodule ApiHarness.Agent.Context.Providers.SessionMemory do
  @moduledoc "Provides current thread session memory within budget."
  @behaviour ApiHarness.Agent.Context.Providers.Behaviour

  alias ApiHarness.LLM.TokenCounter
  alias ApiHarness.Memory

  @full_categories [
    {"goal", "Goal"},
    {"fact", "Facts"},
    {"constraint", "Constraints"},
    {"preference", "Preferences"}
  ]
  @essential_categories [{"goal", "Goal"}, {"fact", "Facts"}]

  @impl true
  def plan(opts) do
    sm = Memory.get_session_memory(opts[:chat_id])
    full = render(@full_categories, sm) |> TokenCounter.count()
    essential = render(@essential_categories, sm) |> TokenCounter.count()
    %{full: full, essential: essential}
  end

  @impl true
  def provide(budget, opts) do
    sm = Memory.get_session_memory(opts[:chat_id])
    full_text = render(@full_categories, sm)
    full_tokens = TokenCounter.count(full_text)

    if full_text == "" do
      {"", 0}
    else
      if full_tokens <= budget do
        {full_text, full_tokens}
      else
        essential_text = render(@essential_categories, sm)
        essential_tokens = TokenCounter.count(essential_text)

        if essential_tokens <= budget do
          {essential_text, essential_tokens}
        else
          {"", 0}
        end
      end
    end
  end

  defp render(categories, %{state: state}) when map_size(state) > 0 do
    sections =
      for {key, label} <- categories,
          entries = Map.get(state, key, []),
          entries != [] do
        contents = Enum.map_join(entries, "\n", &"- #{&1["content"]}")
        "**#{label}:**\n#{contents}"
      end

    Enum.join(sections, "\n")
  end

  defp render(_categories, _), do: ""
end
