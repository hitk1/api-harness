defmodule ApiHarnessWeb.AuthController do
  use ApiHarnessWeb, :controller

  alias ApiHarness.Accounts
  alias ApiHarness.Accounts.Token

  action_fallback ApiHarnessWeb.FallbackController

  def login(conn, params) do
    email = params["email"]
    password = params["password"]

    if blank?(email) or blank?(password) do
      {:error, :missing_credentials}
    else
      with user when not is_nil(user) <- Accounts.get_user_by_email(email),
           {:ok, user} <- Accounts.verify_password(user, password),
           {:ok, token} <- Token.generate(user) do
        render(conn, :login, token: token, user: user)
      else
        nil ->
          Accounts.no_user_verify()
          {:error, :invalid_credentials}

        {:error, :invalid_credentials} ->
          {:error, :invalid_credentials}
      end
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
end
