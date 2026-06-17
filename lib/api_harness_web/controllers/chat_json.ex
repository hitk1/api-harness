defmodule ApiHarnessWeb.ChatJSON do
  alias ApiHarness.Chats.{Chat, Message}

  def index(%{chats: chats}), do: %{chats: Enum.map(chats, &chat_summary/1)}
  def create(%{chat: chat}), do: %{chat: chat_summary(chat)}
  def show(%{chat: chat}), do: %{chat: chat_detail(chat)}

  defp chat_summary(%Chat{} = c) do
    %{id: c.id, title: c.title, inserted_at: c.inserted_at}
  end

  defp chat_detail(%Chat{} = c) do
    %{
      id: c.id,
      title: c.title,
      inserted_at: c.inserted_at,
      messages: Enum.map(c.messages, &message_data/1)
    }
  end

  defp message_data(%Message{} = m) do
    %{id: m.id, role: m.role, content: m.content, inserted_at: m.inserted_at}
  end
end
