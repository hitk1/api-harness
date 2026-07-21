defmodule ApiHarnessWeb.MessageJSON do
  alias ApiHarness.Chats.Message

  def create(%{message: %Message{} = m, context_metrics: context_metrics}) do
    %{
      message: %{
        id: m.id,
        role: m.role,
        content: m.content,
        chat_id: m.chat_id,
        inserted_at: m.inserted_at
      },
      context: context_metrics
    }
  end

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
