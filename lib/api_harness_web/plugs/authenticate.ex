defmodule ApiHarnessWeb.Plugs.Authenticate do
  @moduledoc """
  Verifies the `Authorization: Bearer <jwt>` header and assigns the current user
  to `conn.assigns.current_user` (FR-001-B — identity comes from the token, never
  the request body).

  Rejects with `401 {"errors": {"detail": "unauthenticated"}}` when the header is
  missing/malformed, the signature is invalid, the user no longer exists, or the
  token's `token_version` no longer matches the user's (revoked token).
  """
  import Plug.Conn

  alias ApiHarness.Accounts
  alias ApiHarness.Accounts.Token

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{"sub" => sub, "token_version" => version}} <- Token.verify(token),
         user when not is_nil(user) <- Accounts.get_user(sub),
         true <- user.token_version == version do
      assign(conn, :current_user, user)
    else
      _ -> unauthenticated(conn)
    end
  end

  defp unauthenticated(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{errors: %{detail: "unauthenticated"}})
    |> halt()
  end
end
