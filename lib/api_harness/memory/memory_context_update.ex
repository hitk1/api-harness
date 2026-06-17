defmodule ApiHarness.Memory.MemoryContextUpdate do
  @moduledoc """
  Append-only audit record of every memory state change produced by
  reconciliation (FR-021). This table intentionally IS a log.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_actions ~w(create update merge discard)

  schema "memory_context_updates" do
    field :action, :string
    field :before, :map
    field :after, :map

    belongs_to :user, ApiHarness.Accounts.User
    belongs_to :persistent_memory, ApiHarness.Memory.PersistentMemory
    belongs_to :chat, ApiHarness.Chats.Chat

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(mcu, attrs) do
    mcu
    |> cast(attrs, [:action, :before, :after, :user_id, :persistent_memory_id, :chat_id])
    |> validate_required([:action, :user_id])
    |> validate_inclusion(:action, @valid_actions)
  end
end
