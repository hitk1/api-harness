defmodule ApiHarness.Agent.Context.Providers.UserQuestion do
  @moduledoc "Always includes the current user question in full."
  @behaviour ApiHarness.Agent.Context.Providers.Behaviour

  alias ApiHarness.LLM.TokenCounter

  @impl true
  def plan(opts) do
    q = opts[:question] || ""
    n = TokenCounter.count(q)
    %{full: n, essential: n}
  end

  @impl true
  def provide(_budget, opts) do
    q = opts[:question] || ""
    {q, TokenCounter.count(q)}
  end
end
