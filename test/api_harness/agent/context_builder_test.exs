defmodule ApiHarness.Agent.ContextBuilderTest do
  use ApiHarness.DataCase, async: true

  alias ApiHarness.Accounts
  alias ApiHarness.Agent.ContextBuilder
  alias ApiHarness.Chats
  alias ApiHarness.Memory

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, chat} = Chats.create_chat(user, %{title: "Test"})
    {:ok, user: user, chat: chat}
  end

  describe "build/3" do
    test "returns a list of messages with the six layers in correct order", %{
      user: user,
      chat: chat
    } do
      {:ok, _} = Chats.add_message(chat, "user", "Pergunta anterior")
      {:ok, _} = Chats.add_message(chat, "assistant", "Resposta anterior")

      messages = ContextBuilder.build(user, chat, "Pergunta atual")

      assert is_list(messages)
      assert length(messages) >= 3

      # First message must be the system instruction (layer 1 + 2 + 3 + 4)
      first = List.first(messages)
      assert first.role == "system"
      assert is_binary(first.content)

      # Last message is the current question (layer 6)
      last = List.last(messages)
      assert last.role == "user"
      assert last.content =~ "Pergunta atual"
    end

    test "recent messages are included (layer 5)", %{user: user, chat: chat} do
      for i <- 1..3 do
        {:ok, _} = Chats.add_message(chat, "user", "Msg #{i}")
        {:ok, _} = Chats.add_message(chat, "assistant", "Reply #{i}")
      end

      messages = ContextBuilder.build(user, chat, "Nova pergunta")
      contents = Enum.map(messages, & &1.content)
      assert Enum.any?(contents, &(&1 =~ "Msg"))
    end

    test "session memory state is included in system message", %{user: user, chat: chat} do
      Memory.update_session_memory(chat.id, %{"topic" => "trabalhista"})

      messages = ContextBuilder.build(user, chat, "Pergunta")
      system_content = List.first(messages).content
      assert system_content =~ "trabalhista"
    end
  end
end
