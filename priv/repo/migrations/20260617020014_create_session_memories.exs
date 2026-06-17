defmodule ApiHarness.Repo.Migrations.CreateSessionMemories do
  use Ecto.Migration

  def change do
    create table(:session_memories) do
      add :chat_id, references(:chats, on_delete: :delete_all), null: false
      add :state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:session_memories, [:chat_id])
  end
end
