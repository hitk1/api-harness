defmodule ApiHarnessWeb.MessageControllerTest do
  # async: false because LLMStub uses global Application env overrides
  use ApiHarnessWeb.ConnCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Accounts.Token
  alias ApiHarness.Chats
  alias ApiHarness.LLMStub

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
end
