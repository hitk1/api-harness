defmodule ApiHarnessWeb.MessageJSON do
  alias ApiHarness.Chats.Message

  def create(%{message: %Message{} = m}) do
    %{
      message: %{
        id: m.id,
        role: m.role,
        content: m.content,
        chat_id: m.chat_id,
        inserted_at: m.inserted_at
      }
    }
  end
end
