defmodule ApiHarnessWeb.AuthControllerTest do
  use ApiHarnessWeb.ConnCase, async: true

  alias ApiHarness.Accounts

  @valid_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    {:ok, user} = Accounts.create_user(@valid_attrs)
    {:ok, user: user}
  end

  describe "POST /api/login" do
    test "returns 200 with token and user on valid credentials", %{conn: conn} do
      conn =
        post(conn, "/api/login", %{
          email: "eduardo@example.com",
          password: "s3cr3tpass"
        })

      assert %{"token" => token, "user" => user_data} = json_response(conn, 200)
      assert is_binary(token)
      assert token != ""
      assert user_data["email"] == "eduardo@example.com"
      assert user_data["name"] == "Eduardo"
      refute Map.has_key?(user_data, "hashed_password")
    end

    test "returns 400 when email is missing", %{conn: conn} do
      conn = post(conn, "/api/login", %{password: "s3cr3tpass"})
      assert %{"errors" => %{"detail" => msg}} = json_response(conn, 400)
      assert msg =~ "required"
    end

    test "returns 400 when password is missing", %{conn: conn} do
      conn = post(conn, "/api/login", %{email: "eduardo@example.com"})
      assert %{"errors" => %{"detail" => msg}} = json_response(conn, 400)
      assert msg =~ "required"
    end

    test "returns 401 on wrong password", %{conn: conn} do
      conn =
        post(conn, "/api/login", %{email: "eduardo@example.com", password: "wrongpassword"})

      assert %{"errors" => %{"detail" => "invalid credentials"}} = json_response(conn, 401)
    end

    test "returns 401 on unknown email (constant-time, no enumeration)", %{conn: conn} do
      conn =
        post(conn, "/api/login", %{email: "ghost@example.com", password: "doesntmatter"})

      assert %{"errors" => %{"detail" => "invalid credentials"}} = json_response(conn, 401)
    end
  end
end
