defmodule ApiHarness.Chats.Chat do
  @moduledoc "A conversation thread owned by a user (FR-004, FR-006)."
  use Ecto.Schema
  import Ecto.Changeset

  alias ApiHarness.Accounts.User

  @type t :: %__MODULE__{}

  schema "chats" do
    field :title, :string
    field :context_status, :string, default: "active"
    field :rolling_summary, :string
    field :rolling_summary_token_count, :integer, default: 0
    field :total_context_tokens, :integer, default: 0
    field :compaction_count, :integer, default: 0
    field :last_compaction_at, :utc_datetime

    belongs_to :user, User
    has_many :messages, ApiHarness.Chats.Message
    has_one :session_memory, ApiHarness.Memory.SessionMemory

    timestamps(type: :utc_datetime)
  end

  def changeset(chat, attrs) do
    cast(chat, attrs, [:title])
  end
end
