defmodule ApiHarness.Agent.Context.Providers.Behaviour do
  @moduledoc "Behaviour for context providers that supply content within a token budget."

  @doc "Returns token cost estimates at each detail level."
  @callback plan(opts :: keyword()) :: %{full: non_neg_integer(), essential: non_neg_integer()}

  @doc "Returns content fitting within budget and the actual tokens used."
  @callback provide(budget :: non_neg_integer(), opts :: keyword()) ::
              {content :: String.t(), tokens_used :: non_neg_integer()}
end
