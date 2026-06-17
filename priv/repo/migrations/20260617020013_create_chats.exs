defmodule ApiHarness.Repo.Migrations.CreateChats do
  use Ecto.Migration

  def change do
    create table(:chats) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string

      timestamps(type: :utc_datetime)
    end

    create index(:chats, [:user_id])
  end
end
