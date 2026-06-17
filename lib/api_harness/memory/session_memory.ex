defmodule ApiHarness.Memory.SessionMemory do
  @moduledoc """
  Per-thread structured JSON state (FR-014, FR-015). One per chat thread;
  not shared across threads. Initialized empty on thread creation; updated
  in place by the async memory pipeline.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ApiHarness.Chats.Chat

  @type t :: %__MODULE__{}

  schema "session_memories" do
    field :state, :map, default: %{}

    belongs_to :chat, Chat

    timestamps(type: :utc_datetime)
  end

  def changeset(session_memory, attrs) do
    session_memory
    |> cast(attrs, [:state])
    |> validate_required([:state])
  end
end
