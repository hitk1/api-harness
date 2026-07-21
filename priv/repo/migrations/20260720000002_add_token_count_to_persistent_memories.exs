defmodule ApiHarness.Repo.Migrations.AddTokenCountToPersistentMemories do
  use Ecto.Migration

  def change do
    alter table(:persistent_memories) do
      add :token_count, :integer, default: 0, null: false
    end
  end
end
