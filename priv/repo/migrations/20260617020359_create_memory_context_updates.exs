defmodule ApiHarness.Repo.Migrations.CreateMemoryContextUpdates do
  use Ecto.Migration

  def change do
    create table(:memory_context_updates) do
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :persistent_memory_id, references(:persistent_memories, on_delete: :nilify_all)
      add :chat_id, references(:chats, on_delete: :nilify_all)
      add :action, :string, null: false
      add :before, :map
      add :after, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:memory_context_updates, [:user_id])
    create index(:memory_context_updates, [:persistent_memory_id])
  end
end
