defmodule ApiHarness.Agent.Context.PostResponse do
  @moduledoc """
  Async post-response analysis: updates total_context_tokens and flags
  sessions for compaction when utilization crosses the threshold.
  """
  require Logger

  alias ApiHarness.Agent.Context.BudgetManager
  alias ApiHarness.Chats
  alias ApiHarness.Context.Compaction

  @doc """
  Analyze context utilization after a response. Updates metrics and
  enqueues compaction if threshold exceeded. Always returns :ok.
  """
  @spec analyze(map(), non_neg_integer()) :: :ok
  def analyze(chat, total_tokens) do
    profile = BudgetManager.default_profile()

    threshold =
      Application.get_env(:api_harness, :context_budget, [])[:compaction_threshold] || 0.70

    case Chats.update_context_metrics(chat.id, %{total_context_tokens: total_tokens}) do
      {:ok, updated_chat} ->
        utilization = total_tokens / profile.available_budget

        if utilization >= threshold and updated_chat.context_status == "active" do
          Logger.info(
            "PostResponse: utilization=#{Float.round(utilization * 100, 1)}% >= #{threshold * 100}% for chat_id=#{chat.id}, flagging for compaction"
          )

          case Chats.update_context_status(chat.id, "needs_compaction") do
            {:ok, _} ->
              Compaction.Supervisor.start_worker(chat.id, chat.user_id)

            {:error, reason} ->
              Logger.error(
                "PostResponse: failed to set needs_compaction: #{inspect(reason)}"
              )
          end
        end

      {:error, reason} ->
        Logger.warning(
          "PostResponse: failed to update total_context_tokens: #{inspect(reason)}"
        )
    end

    :ok
  end
end
