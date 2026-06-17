defmodule ApiHarness.Repo.Migrations.CreatePersistentMemories do
  use Ecto.Migration

  def change do
    create table(:persistent_memories) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :category, :string, null: false
      add :kind, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}
      add :embedding, :vector, size: 1536

      timestamps(type: :utc_datetime)
    end

    create index(:persistent_memories, [:user_id, :category])
    # ANN index for cosine similarity search (pgvector ivfflat).
    # Lists=100 is a reasonable starting point for a study project.
    execute(
      "CREATE INDEX persistent_memories_embedding_cosine_idx ON persistent_memories USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX IF EXISTS persistent_memories_embedding_cosine_idx"
    )
  end
end
