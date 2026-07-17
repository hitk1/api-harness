defmodule ApiHarness.Agent.Runtime do
  @moduledoc """
  Agent orchestrator (FR-008–FR-013).

  Synchronous request path:
    1. Persist user message
    2. ContextBuilder → 6-layer prompt
    3. Planner → structured plan (always runs — FR-010-A)
    4. Executor → runs plan (Coordinator for parallel steps, Tool Registry for tool calls)
    5. Persist assistant message
    6. Return `{:ok, message}`

  After returning, the caller (MessageController) dispatches both async memory
  pipelines (fire-and-forget — FR-023, SC-002, and spec 002 FR-006): the
  persistent-memory pipeline, and the categorized session-memory update via
  `ApiHarness.Memory.SessionMemory.Coordinator.enqueue/4`. Neither pipeline is
  started here, keeping the response path free of their failures.
  """

  alias ApiHarness.Accounts.User
  alias ApiHarness.Agent.{ContextBuilder, Executor, Planner}
  alias ApiHarness.Chats
  alias ApiHarness.Chats.Chat

  require Logger

  @doc """
  Run the full synchronous agent loop for `user`, `chat`, and `question`.
  Returns `{:ok, assistant_message}` or `{:error, reason}`.
  """
  @spec run(User.t(), Chat.t(), String.t()) ::
          {:ok, Chats.Message.t()}
          | {:error, :empty_content | :not_found | :planner_failed | :llm_unavailable}
  def run(%User{} = user, %Chat{} = chat, question) do
    with :ok <- validate_content(question),
         {:ok, _user_msg} <- Chats.add_message(chat, "user", question),
         messages <- ContextBuilder.build(user, chat, question),
         {:ok, steps} <- Planner.plan(messages),
         {:ok, answer} <- Executor.execute(steps, messages),
         {:ok, assistant_msg} <- Chats.add_message(chat, "assistant", answer) do
      {:ok, assistant_msg}
    else
      {:error, :planner_failed} ->
        {:error, :planner_failed}

      {:error, :llm_unavailable} ->
        {:error, :llm_unavailable}

      {:error, %Ecto.Changeset{} = cs} ->
        Logger.warning("Runtime persist failed: #{inspect(cs.errors)}")
        {:error, :llm_unavailable}

      other ->
        other
    end
  end

  defp validate_content(content) when is_binary(content) do
    if String.trim(content) == "", do: {:error, :empty_content}, else: :ok
  end

  defp validate_content(_), do: {:error, :empty_content}
end
