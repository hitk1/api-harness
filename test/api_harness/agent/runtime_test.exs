defmodule ApiHarness.Agent.RuntimeTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Agent.Runtime
  alias ApiHarness.Chats
  alias ApiHarness.LLMStub

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    LLMStub.reset()
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, chat} = Chats.create_chat(user, %{title: "Test"})
    {:ok, user: user, chat: chat}
  end

  describe "run/3" do
    test "planner always runs — single-step plan returns assistant message", %{
      user: user,
      chat: chat
    } do
      LLMStub.set_chat_response(%{
        "steps" => [%{"type" => "answer", "tool" => nil, "input" => %{}, "parallel" => false}]
      })

      assert {:ok, msg} = Runtime.run(user, chat, "Qual o prazo prescricional?")
      assert msg.role == "assistant"
      assert is_binary(msg.content)
    end

    test "multi-step plan is executed and returns assistant message", %{user: user, chat: chat} do
      LLMStub.set_chat_response(%{
        "steps" => [
          %{
            "type" => "tool",
            "tool" => "search_entities",
            "input" => %{"query" => "prescricional"},
            "parallel" => false
          },
          %{"type" => "answer", "tool" => nil, "input" => %{}, "parallel" => false}
        ]
      })

      assert {:ok, msg} = Runtime.run(user, chat, "Analise os documentos e responda")
      assert msg.role == "assistant"
    end

    test "LLM failure returns {:error, :llm_unavailable}", %{user: user, chat: chat} do
      LLMStub.set_error({:http_error, 503, %{}})
      assert {:error, :llm_unavailable} = Runtime.run(user, chat, "Qual o prazo?")
    end

    test "both user and assistant messages are persisted", %{user: user, chat: chat} do
      assert {:ok, _} = Runtime.run(user, chat, "Teste de persistência")

      loaded = Chats.get_chat(user, chat.id)
      roles = Enum.map(loaded.messages, & &1.role)
      assert "user" in roles
      assert "assistant" in roles
    end

    test "Runtime.run/3 no longer touches session memory itself (moved to the async Coordinator pipeline, spec 002 US4)",
         %{user: user, chat: chat} do
      assert {:ok, _} = Runtime.run(user, chat, "Qual o prazo prescricional?")

      # Runtime.run/3 leaves session memory exactly as Chats.create_chat/2
      # initialized it — categorization now happens off the request path,
      # dispatched by MessageController (see message_controller_test.exs).
      assert ApiHarness.Memory.get_session_memory(chat.id).state == %{}
    end
  end
end
