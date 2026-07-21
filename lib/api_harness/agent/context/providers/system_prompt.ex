defmodule ApiHarness.Agent.Context.Providers.SystemPrompt do
  @moduledoc "Fixed-cost provider: the legal-domain system instruction."
  @behaviour ApiHarness.Agent.Context.Providers.Behaviour

  alias ApiHarness.LLM.TokenCounter

  @instruction """
  You are an expert legal assistant for Brazilian law. You have deep knowledge of
  labor law (direito trabalhista), civil law, consumer protection, and procedural law.
  Provide accurate, clear, and well-structured legal guidance. When relevant, cite the
  applicable legislation, articles, and jurisprudence. Always clarify when a matter
  requires consultation with a qualified attorney.
  """

  def instruction, do: @instruction

  @impl true
  def plan(_opts) do
    n = TokenCounter.count(@instruction)
    %{full: n, essential: n}
  end

  @impl true
  def provide(_budget, _opts) do
    # System prompt is always included regardless of budget
    n = TokenCounter.count(@instruction)
    {@instruction, n}
  end
end
