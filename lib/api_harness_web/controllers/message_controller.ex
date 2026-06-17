defmodule ApiHarnessWeb.MessageController do
  use ApiHarnessWeb, :controller

  alias ApiHarness.Agent.Runtime
  alias ApiHarness.Chats
  alias ApiHarness.Memory.Pipeline.Supervisor, as: PipelineSupervisor

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

        chat ->
          with {:ok, assistant_msg} <- Runtime.run(user, chat, content) do
            dispatch_pipeline(user, chat, assistant_msg)
            render(conn, :create, message: assistant_msg)
          else
            {:error, :planner_failed} -> {:error, :planner_failed}
            {:error, _} -> {:error, :llm_unavailable}
          end
      end
    end
  end

  defp dispatch_pipeline(user, chat, assistant_msg) do
    interaction = %{user_id: user.id, chat_id: chat.id, message: assistant_msg}
    PipelineSupervisor.start_worker(interaction)
  rescue
    _ -> :ok
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
end
