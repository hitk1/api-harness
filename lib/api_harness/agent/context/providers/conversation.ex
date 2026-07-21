defmodule ApiHarness.Agent.Context.Providers.Conversation do
  @moduledoc """
  Provides conversation history: rolling summary (if present) + recent messages within budget.

  Returns a 3-tuple `{summary, prior_turns, tokens_used}` from `provide/2` where
  `prior_turns` is a list of `%{role: ..., content: ...}` maps and `summary` is the
  rolling summary string (or nil). The Runtime handles this special case.
  """
  alias ApiHarness.Chats
  alias ApiHarness.LLM.TokenCounter

  def plan(opts) do
    chat = opts[:chat]
    window = Application.get_env(:api_harness, :agent)[:recent_messages_window] || 10
    messages = Chats.list_recent_messages(chat, window)
    msg_tokens = messages |> Enum.map(&msg_tokens/1) |> Enum.sum()
    summary_tokens = chat.rolling_summary_token_count || 0
    %{full: summary_tokens + msg_tokens, essential: summary_tokens}
  end

  def provide(budget, opts) do
    chat = opts[:chat]
    window = Application.get_env(:api_harness, :agent)[:recent_messages_window] || 10
    messages = Chats.list_recent_messages(chat, window)

    summary = chat.rolling_summary

    summary_tokens =
      if summary, do: chat.rolling_summary_token_count || TokenCounter.count(summary), else: 0

    remaining = budget - summary_tokens

    # Fit as many recent messages as possible within remaining budget.
    # list_recent_messages returns chronological order; we select from most recent.
    {fitted_messages, msg_tokens_used} =
      messages
      |> Enum.reverse()
      |> Enum.reduce_while({[], 0}, fn msg, {acc, total} ->
        t = msg_tokens(msg)

        if total + t <= remaining do
          {:cont, {[msg | acc], total + t}}
        else
          {:halt, {acc, total}}
        end
      end)

    prior_turns = Enum.map(fitted_messages, &%{role: &1.role, content: &1.content})
    total_used = summary_tokens + msg_tokens_used

    {summary, prior_turns, total_used}
  end

  defp msg_tokens(%{token_count: tc}) when is_integer(tc) and tc > 0, do: tc
  defp msg_tokens(%{content: c}), do: TokenCounter.count(c)
end
