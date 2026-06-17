defmodule ApiHarness.Chats.Chat do
  @moduledoc "A conversation thread owned by a user (FR-004, FR-006)."
  use Ecto.Schema
  import Ecto.Changeset

  alias ApiHarness.Accounts.User

  @type t :: %__MODULE__{}

  schema "chats" do
    field :title, :string

    belongs_to :user, User
    has_many :messages, ApiHarness.Chats.Message
    has_one :session_memory, ApiHarness.Memory.SessionMemory

    timestamps(type: :utc_datetime)
  end

  def changeset(chat, attrs) do
    cast(chat, attrs, [:title])
  end
end
