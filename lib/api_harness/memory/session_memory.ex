defmodule ApiHarness.Memory.SessionMemory do
  @moduledoc """
  Per-thread structured JSON state (FR-014, FR-015). One per chat thread;
  not shared across threads. Initialized empty on thread creation; updated
  in place by the session-memory pipeline.

  `state` (spec 002, FR-002/FR-003) is organized into four categories —
  `"goal"`, `"fact"`, `"constraint"`, `"preference"` — the same taxonomy
  already used by `ApiHarness.Memory.PersistentMemory`'s `kind` field, applied
  at thread scope instead of user scope. Each category holds a list of
  entries, each with a stable `"id"` (`Ecto.UUID.generate/0`) so later turns
  can target a specific entry for `update`/`merge` (see `SessionReconciler`
  and `Memory.apply_session_reconciliation/2`) instead of overwriting the
  whole map:

      %{
        "goal" => [%{"id" => uuid, "content" => "..."}],
        "fact" => [%{"id" => uuid, "content" => "..."}],
        "constraint" => [],
        "preference" => []
      }

  A category absent from the map or holding an empty list means no entry has
  been reconciled into it yet.
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
