defmodule ApiHarnessWeb.MessageControllerTest do
  # async: false because LLMStub uses global Application env overrides
  use ApiHarnessWeb.ConnCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Accounts.Token
  alias ApiHarness.Chats
  alias ApiHarness.LLMStub
  alias ApiHarness.Memory
  alias ApiHarness.Memory.SessionMemory.Coordinator

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    LLMStub.reset()
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, token} = Token.generate(user)
    {:ok, chat} = Chats.create_chat(user, %{title: "Test"})

    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    {:ok, conn: conn, user: user, chat: chat}
  end

  describe "POST /api/chats/:chat_id/messages" do
    test "returns 200 with assistant message for valid content", %{
      conn: conn,
      chat: chat
    } do
      conn =
        post(conn, "/api/chats/#{chat.id}/messages", %{content: "Qual o prazo prescricional?"})

      assert %{
               "message" => %{
                 "role" => "assistant",
                 "content" => content,
                 "chat_id" => _,
                 "id" => _
               }
             } = json_response(conn, 200)

      assert is_binary(content) and content != ""
    end

    test "returns 400 for empty content", %{conn: conn, chat: chat} do
      conn = post(conn, "/api/chats/#{chat.id}/messages", %{content: ""})
      assert %{"errors" => %{"detail" => _}} = json_response(conn, 400)
    end

    test "returns 400 for missing content", %{conn: conn, chat: chat} do
      conn = post(conn, "/api/chats/#{chat.id}/messages", %{})
      assert %{"errors" => %{"detail" => _}} = json_response(conn, 400)
    end

    test "returns 404 for foreign chat_id", %{conn: conn} do
      conn = post(conn, "/api/chats/0/messages", %{content: "hello"})
      assert json_response(conn, 404)
    end

    test "returns 401 without auth", %{chat: chat} do
      conn = build_conn() |> post("/api/chats/#{chat.id}/messages", %{content: "hello"})
      assert json_response(conn, 401)
    end

    test "returns 502 when LLM is unavailable", %{conn: conn, chat: chat} do
      LLMStub.set_error({:http_error, 503, %{}})
      conn = post(conn, "/api/chats/#{chat.id}/messages", %{content: "Qual o prazo?"})
      assert json_response(conn, 502)
    end
  end

  describe "categorized session memory (spec 002, dispatched off the request path)" do
    test "a turn's categorized facts arrive in session memory shortly after the response", %{
      conn: conn,
      chat: chat
    } do
      LLMStub.set_chat_response_for("knowledge_extraction", %{
        "items" => [
          %{
            "category" => "task",
            "kind" => "fact",
            "content" => "Cliente: João Silva",
            "durable" => true
          }
        ]
      })

      conn =
        post(conn, "/api/chats/#{chat.id}/messages", %{
          content: "O cliente se chama João Silva."
        })

      assert json_response(conn, 200)

      # The response above already returned — the assertion below proves the
      # categorization work was not on the critical path (SC-004) while still
      # confirming it lands shortly after (eventual consistency).
      Coordinator.sync(Coordinator)
      wait_for_idle(chat.id)

      facts = Memory.get_session_memory(chat.id).state["fact"] || []
      assert Enum.any?(facts, &(&1["content"] == "Cliente: João Silva"))
    end
  end

  # Busy-poll `:sys.get_state/1` on the production Coordinator singleton
  # (constitution-endorsed synchronization primitive) until `chat_id` has no
  # in-flight or pending job left. Bounded, not time-based — no
  # `Process.sleep/1`.
  defp wait_for_idle(chat_id, attempts \\ 5_000_000)

  defp wait_for_idle(chat_id, 0) do
    ExUnit.Assertions.flunk("Coordinator never went idle for chat_id=#{chat_id}")
  end

  defp wait_for_idle(chat_id, attempts) do
    state = :sys.get_state(Coordinator)

    if Map.has_key?(state.in_flight, chat_id) or Map.has_key?(state.pending, chat_id) do
      wait_for_idle(chat_id, attempts - 1)
    else
      :ok
    end
  end
end
