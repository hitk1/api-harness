defmodule ApiHarness.Agent.Context.BudgetManager do
  @moduledoc """
  Distributes the context window budget across provider layers.
  Fixed-cost layers (system, question) are reserved first;
  the remainder is split proportionally among variable-cost layers.
  """

  @default_context_window 128_000
  @default_output_reserve 16_384
  @default_safety_headroom 0.02
  @default_proportions %{
    domain: 0.10,
    session: 0.05,
    memory: 0.15,
    conversation: 0.70
  }

  @doc "Returns the default model profile from config or hardcoded defaults."
  def default_profile do
    cfg = Application.get_env(:api_harness, :context_budget, [])
    window = cfg[:context_window] || @default_context_window
    reserve = cfg[:output_reserve] || @default_output_reserve
    headroom = cfg[:safety_headroom] || @default_safety_headroom
    proportions = cfg[:provider_proportions] || @default_proportions

    headroom_tokens = ceil(window * headroom)
    available = window - reserve - headroom_tokens

    %{
      context_window: window,
      output_reserve: reserve,
      safety_headroom_tokens: headroom_tokens,
      available_budget: available,
      proportions: proportions
    }
  end

  @doc """
  Allocates budget across named providers given `system_tokens` and `question_tokens`.
  Returns a map of provider => token budget.
  """
  def allocate(profile, opts \\ []) do
    system_tokens = opts[:system_tokens] || 0
    question_tokens = opts[:question_tokens] || 0

    available = profile.available_budget
    variable_budget = max(0, available - system_tokens - question_tokens)

    p = profile.proportions
    domain = floor(variable_budget * p.domain)
    session = floor(variable_budget * p.session)
    memory = floor(variable_budget * p.memory)
    # conversation gets the remainder to avoid rounding loss
    conversation = variable_budget - domain - session - memory

    %{
      system: system_tokens,
      domain: domain,
      session: session,
      memory: memory,
      conversation: max(0, conversation),
      question: question_tokens,
      total: system_tokens + domain + session + memory + max(0, conversation) + question_tokens,
      available_budget: available
    }
  end
end
