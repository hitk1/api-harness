defmodule ApiHarness.Memory.PersistentMemory do
  @moduledoc """
  Durable per-user knowledge entry (FR-016, FR-017). Never append-only —
  managed by the Reconciler via create/update/merge/discard.
  Carries a pgvector embedding for semantic retrieval (FR-020).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ApiHarness.Accounts.User

  @type t :: %__MODULE__{}

  @valid_categories ~w(user task domain)
  @valid_kinds ~w(preference goal constraint fact)

  schema "persistent_memories" do
    field :category, :string
    field :kind, :string
    field :content, :string
    field :metadata, :map, default: %{}
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(pm, attrs) do
    pm
    |> cast(attrs, [:category, :kind, :content, :metadata, :embedding])
    |> validate_required([:category, :kind, :content])
    |> validate_inclusion(:category, @valid_categories)
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_length(:content, min: 1)
  end
end
