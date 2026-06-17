defmodule ApiHarnessWeb.ChatControllerTest do
  use ApiHarnessWeb.ConnCase, async: true

  alias ApiHarness.Accounts
  alias ApiHarness.Accounts.Token

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, token} = Token.generate(user)

    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    {:ok, conn: conn, user: user}
  end

  describe "POST /api/chats" do
    test "creates a chat and returns 201", %{conn: conn} do
      conn = post(conn, "/api/chats", %{title: "Ação trabalhista"})
      assert %{"chat" => %{"id" => _, "title" => "Ação trabalhista"}} = json_response(conn, 201)
    end

    test "title is optional", %{conn: conn} do
      conn = post(conn, "/api/chats", %{})
      assert %{"chat" => %{"id" => _}} = json_response(conn, 201)
    end

    test "returns 401 without auth", %{} do
      conn = build_conn() |> post("/api/chats", %{})
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/chats" do
    test "returns list of own chats", %{conn: conn} do
      post(conn, "/api/chats", %{title: "Thread 1"})
      post(conn, "/api/chats", %{title: "Thread 2"})

      conn = get(conn, "/api/chats")
      %{"chats" => chats} = json_response(conn, 200)
      assert length(chats) >= 2
    end

    test "returns 401 without auth" do
      conn = build_conn() |> get("/api/chats")
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/chats/:id" do
    test "returns chat with messages", %{conn: conn} do
      %{"chat" => %{"id" => chat_id}} =
        conn |> post("/api/chats", %{title: "Test"}) |> json_response(201)

      conn = get(conn, "/api/chats/#{chat_id}")
      assert %{"chat" => %{"id" => ^chat_id, "messages" => []}} = json_response(conn, 200)
    end

    test "returns 404 for foreign thread", %{conn: conn} do
      {:ok, other} =
        Accounts.create_user(%{name: "Other", email: "other@example.com", password: "password1"})

      {:ok, other_token} = Token.generate(other)

      other_conn =
        build_conn() |> put_req_header("authorization", "Bearer #{other_token}")

      %{"chat" => %{"id" => other_chat_id}} =
        other_conn |> post("/api/chats", %{}) |> json_response(201)

      conn = get(conn, "/api/chats/#{other_chat_id}")
      assert json_response(conn, 404)
    end
  end
end
