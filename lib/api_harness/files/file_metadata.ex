defmodule ApiHarness.Files.FileMetadata do
  @moduledoc "Placeholder schema for user-uploaded document metadata (FR-027). No ingestion logic."
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "file_metadata" do
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :metadata, :map, default: %{}

    belongs_to :user, ApiHarness.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(fm, attrs) do
    cast(fm, attrs, [:filename, :content_type, :byte_size, :metadata])
  end
end
