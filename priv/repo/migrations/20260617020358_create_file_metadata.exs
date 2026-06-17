defmodule ApiHarness.Repo.Migrations.CreateFileMetadata do
  use Ecto.Migration

  def change do
    create table(:file_metadata) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :filename, :string
      add :content_type, :string
      add :byte_size, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:file_metadata, [:user_id])
  end
end
