defmodule ApiHarness.Repo.Migrations.AddContextManagementToChats do
  use Ecto.Migration

  def change do
    alter table(:chats) do
      add :context_status, :string, default: "active"
      add :rolling_summary, :text
      add :rolling_summary_token_count, :integer, default: 0
      add :total_context_tokens, :integer, default: 0
      add :compaction_count, :integer, default: 0
      add :last_compaction_at, :utc_datetime
    end

    create index(:chats, [:context_status],
      name: :chats_context_status_needs_attention_idx,
      where: "context_status IN ('needs_compaction', 'compacting')"
    )
  end
end
