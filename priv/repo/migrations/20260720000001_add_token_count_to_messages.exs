defmodule ApiHarness.Repo.Migrations.AddTokenCountToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :token_count, :integer, default: 0, null: false
    end
  end
end
