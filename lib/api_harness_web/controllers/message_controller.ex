defmodule ApiHarnessWeb.MessageController do
  use ApiHarnessWeb, :controller

  alias ApiHarness.Agent.Context.PostResponse
  alias ApiHarness.Agent.Runtime
  alias ApiHarness.Chats
  alias ApiHarness.Memory.Pipeline.Supervisor, as: PipelineSupervisor
  alias ApiHarness.Memory.SessionMemory.Coordinator, as: SessionMemoryCoordinator

  action_fallback ApiHarnessWeb.FallbackController

  def create(conn, %{"chat_id" => chat_id} = params) do
    user = conn.assigns.current_user
    content = params["content"]

    if blank?(content) do
      {:error, :empty_content}
    else
      case Chats.get_chat(user, chat_id) do
        nil ->
          {:error, :not_found}

        %{context_status: "compacting"} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "Session is being compacted, please retry shortly"})

        chat ->
          with {:ok, assistant_msg, context_metrics} <- Runtime.run(user, chat, content) do
            dispatch_pipeline(user, chat, content, assistant_msg, context_metrics)
            render(conn, :create, message: assistant_msg, context_metrics: context_metrics)
          else
            {:error, :planner_failed} -> {:error, :planner_failed}
            {:error, _} -> {:error, :llm_unavailable}
          end
      end
    end
  end

  # Dispatches memory pipelines and post-response analysis off the response path
  # (fire-and-forget). PostResponse.analyze handles compaction detection.
  defp dispatch_pipeline(user, chat, question, assistant_msg, context_metrics) do
    interaction = %{user_id: user.id, chat_id: chat.id, message: assistant_msg}
    PipelineSupervisor.start_worker(interaction)
    SessionMemoryCoordinator.enqueue(chat.id, user.id, question, assistant_msg.content)
    PostResponse.analyze(chat, context_metrics.total_tokens)
  rescue
    _ -> :ok
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
end
