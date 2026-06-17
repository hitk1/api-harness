defmodule ApiHarnessWeb.ChatController do
  use ApiHarnessWeb, :controller

  alias ApiHarness.Chats

  action_fallback ApiHarnessWeb.FallbackController

  def index(conn, _params) do
    chats = Chats.list_chats(conn.assigns.current_user)
    render(conn, :index, chats: chats)
  end

  def create(conn, params) do
    case Chats.create_chat(conn.assigns.current_user, params) do
      {:ok, chat} ->
        conn
        |> put_status(:created)
        |> render(:create, chat: chat)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def show(conn, %{"id" => id}) do
    case Chats.get_chat(conn.assigns.current_user, id) do
      nil -> {:error, :not_found}
      chat -> render(conn, :show, chat: chat)
    end
  end
end
