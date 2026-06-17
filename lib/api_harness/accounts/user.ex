defmodule ApiHarness.Accounts.User do
  @moduledoc """
  A system operator / end user. Created via the REPL (FR-001) and authenticated
  via JWT (FR-000). Passwords are bcrypt-hashed; `token_version` is bumped to
  revoke all outstanding JWTs for the user.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ApiHarness.Accounts.User

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder, only: [:id, :name, :email, :inserted_at, :updated_at]}
  schema "users" do
    field :name, :string
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :token_version, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating a user. Hashes `password` into
  `hashed_password`. `token_version` is programmatic and intentionally excluded
  from `cast/3` (set on the struct via `revoke_tokens_changeset/1`).
  """
  def changeset(%User{} = user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, max: 72)
    |> update_change(:email, &String.downcase/1)
    |> unsafe_validate_unique(:email, ApiHarness.Repo)
    |> unique_constraint(:email, name: :users_email_lower_index)
    |> put_password_hash()
  end

  @doc """
  Bumps `token_version`, revoking every JWT previously issued to the user.
  """
  def revoke_tokens_changeset(%User{} = user) do
    change(user, token_version: user.token_version + 1)
  end

  defp put_password_hash(changeset) do
    case fetch_change(changeset, :password) do
      {:ok, password} ->
        changeset
        |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)

      :error ->
        changeset
    end
  end
end
