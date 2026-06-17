defmodule ApiHarness.ChatsTest do
  use ApiHarness.DataCase, async: true

  alias ApiHarness.Accounts
  alias ApiHarness.Chats
  alias ApiHarness.Memory.SessionMemory

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, user: user}
  end

  describe "create_chat/2" do
    test "creates chat and initializes session memory", %{user: user} do
      assert {:ok, chat} = Chats.create_chat(user, %{title: "Ação trabalhista"})
      assert chat.title == "Ação trabalhista"
      assert chat.user_id == user.id

      session_memory = Repo.get_by(SessionMemory, chat_id: chat.id)
      assert session_memory
      assert session_memory.state == %{}
    end

    test "title is optional", %{user: user} do
      assert {:ok, chat} = Chats.create_chat(user, %{})
      assert is_nil(chat.title)
    end
  end

  describe "list_chats/1" do
    test "returns only threads owned by user", %{user: user} do
      {:ok, _} =
        Accounts.create_user(%{name: "Other", email: "other@example.com", password: "password1"})

      {:ok, chat1} = Chats.create_chat(user, %{title: "Thread 1"})
      {:ok, chat2} = Chats.create_chat(user, %{title: "Thread 2"})

      chats = Chats.list_chats(user)
      ids = Enum.map(chats, & &1.id)

      assert chat1.id in ids
      assert chat2.id in ids
    end
  end

  describe "get_chat/2" do
    test "returns chat with messages preloaded", %{user: user} do
      {:ok, chat} = Chats.create_chat(user, %{title: "Test"})
      {:ok, _} = Chats.add_message(chat, "user", "Hello")
      {:ok, _} = Chats.add_message(chat, "assistant", "Hi!")

      loaded = Chats.get_chat(user, chat.id)
      assert loaded.id == chat.id
      assert length(loaded.messages) == 2
      roles = Enum.map(loaded.messages, & &1.role)
      assert roles == ["user", "assistant"]
    end

    test "returns nil for foreign thread", %{user: user} do
      {:ok, other} =
        Accounts.create_user(%{name: "Other", email: "other2@example.com", password: "password1"})

      {:ok, chat} = Chats.create_chat(other, %{})

      assert Chats.get_chat(user, chat.id) == nil
    end

    test "returns nil for unknown id", %{user: user} do
      assert Chats.get_chat(user, 0) == nil
    end
  end

  describe "add_message/3" do
    test "persists message with correct role and content", %{user: user} do
      {:ok, chat} = Chats.create_chat(user, %{})
      assert {:ok, msg} = Chats.add_message(chat, "user", "Qual o prazo?")
      assert msg.role == "user"
      assert msg.content == "Qual o prazo?"
      assert msg.chat_id == chat.id
    end

    test "rejects invalid role", %{user: user} do
      {:ok, chat} = Chats.create_chat(user, %{})
      assert {:error, changeset} = Chats.add_message(chat, "invalid", "text")
      assert errors_on(changeset).role
    end
  end

  describe "list_recent_messages/2" do
    test "returns last N messages in ascending order", %{user: user} do
      {:ok, chat} = Chats.create_chat(user, %{})

      for i <- 1..5 do
        {:ok, _} = Chats.add_message(chat, "user", "Message #{i}")
      end

      messages = Chats.list_recent_messages(chat, 3)
      assert length(messages) == 3
      contents = Enum.map(messages, & &1.content)
      assert contents == ["Message 3", "Message 4", "Message 5"]
    end
  end
end
