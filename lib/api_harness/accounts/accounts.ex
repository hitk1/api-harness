defmodule ApiHarness.Accounts do
  @moduledoc """
  User management context (FR-001, FR-002). All CRUD is performed via the REPL;
  there is no HTTP registration endpoint. Login is the only public HTTP surface
  (see `ApiHarnessWeb.AuthController`).
  """
  import Ecto.Query

  alias ApiHarness.Accounts.User
  alias ApiHarness.Repo

  @doc "Create a user. Hashes the password; rejects duplicate emails."
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc "List all users."
  @spec list_users() :: [User.t()]
  def list_users, do: Repo.all(User)

  @doc "Fetch a user by id (string or integer). Returns `nil` when not found."
  @spec get_user(String.t() | integer()) :: User.t() | nil
  def get_user(id) when is_binary(id), do: get_user(String.to_integer(id))
  def get_user(id) when is_integer(id), do: Repo.get(User, id)

  @doc "Fetch a user by email. Returns `nil` when not found."
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.one(from u in User, where: fragment("lower(?)", u.email) == ^String.downcase(email))
  end

  @doc "Update a user's attributes."
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a user."
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(%User{} = user), do: Repo.delete(user)

  @doc """
  Verify `password` against `user.hashed_password` in constant time.
  Returns `{:ok, user}` or `{:error, :invalid_credentials}`.
  """
  @spec verify_password(User.t(), String.t()) :: {:ok, User.t()} | {:error, :invalid_credentials}
  def verify_password(%User{} = user, password) do
    if Bcrypt.verify_pass(password, user.hashed_password) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end

  @doc """
  Protect against timing attacks when no user is found: run a dummy bcrypt check
  so the response time is indistinguishable from a real failed login.
  """
  @spec no_user_verify() :: :error
  def no_user_verify do
    Bcrypt.no_user_verify()
    :error
  end
end
