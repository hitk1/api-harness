defmodule ApiHarness.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :token_version, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, ["lower(email)"], name: :users_email_lower_index)
  end
end
