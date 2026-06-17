defmodule ApiHarness.Accounts.Token do
  @moduledoc """
  JWT issuance and verification (FR-000) via Joken.

  Tokens are **non-expiring** (no `exp` claim — FR-000-A) and carry `sub`
  (user id) plus `token_version`. Revocation is handled by bumping the user's
  `token_version` (see `ApiHarness.Accounts.User.revoke_tokens_changeset/1`):
  the auth plug rejects tokens whose claim no longer matches the stored value.
  Signed with HS256 using `:jwt_secret` from config (env-overridden at runtime).
  """

  alias ApiHarness.Accounts.User

  @doc "Issue a signed JWT for `user`. Returns `{:ok, token}`."
  @spec generate(User.t()) :: {:ok, String.t()} | {:error, term()}
  def generate(%User{} = user) do
    claims = %{"sub" => to_string(user.id), "token_version" => user.token_version}

    case Joken.generate_and_sign(%{}, claims, signer()) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verify a token's signature. Returns `{:ok, claims}` (a string-keyed map with
  `\"sub\"` and `\"token_version\"`) or `{:error, reason}`.
  """
  @spec verify(String.t()) :: {:ok, map()} | {:error, term()}
  def verify(token) when is_binary(token) do
    Joken.verify_and_validate(%{}, token, signer())
  end

  defp signer do
    Joken.Signer.create("HS256", Application.fetch_env!(:api_harness, :jwt_secret))
  end
end
