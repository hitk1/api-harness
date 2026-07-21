defmodule ApiHarness.Agent.Runtime do
  @moduledoc """
  Agent orchestrator (FR-008–FR-013).

  Synchronous request path:
    1. Persist user message
    2. Context.Runtime → 6-layer prompt + context_metrics
    3. Planner → structured plan
    4. Executor → runs plan
    5. Persist assistant message
    6. Return {:ok, message, context_metrics}
  """

  alias ApiHarness.Accounts.User
  alias ApiHarness.Agent.{Context.Runtime, Executor, Planner}
  alias ApiHarness.Chats
  alias ApiHarness.Chats.Chat

  require Logger

  @spec run(User.t(), Chat.t(), String.t()) ::
          {:ok, Chats.Message.t(), map()}
          | {:error, :empty_content | :not_found | :planner_failed | :llm_unavailable}
  def run(%User{} = user, %Chat{} = chat, question) do
    with :ok <- validate_content(question),
         {:ok, _user_msg} <- Chats.add_message(chat, "user", question),
         {messages, context_metrics} <- Runtime.build(user, chat, question),
         {:ok, steps} <- Planner.plan(messages),
         {:ok, answer} <- Executor.execute(steps, messages),
         {:ok, assistant_msg} <- Chats.add_message(chat, "assistant", answer) do
      {:ok, assistant_msg, context_metrics}
    else
      {:error, :planner_failed} -> {:error, :planner_failed}
      {:error, :llm_unavailable} -> {:error, :llm_unavailable}

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
