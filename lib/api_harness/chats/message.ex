defmodule ApiHarness.Chats.Message do
  @moduledoc "A single conversational turn — user or assistant — persisted under a chat thread."
  use Ecto.Schema
  import Ecto.Changeset

  alias ApiHarness.Chats.Chat

  @type t :: %__MODULE__{}

  @valid_roles ~w(user assistant)

  schema "messages" do
    field :role, :string
    field :content, :string
    field :token_count, :integer, default: 0

    belongs_to :chat, Chat

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content])
    |> validate_required([:role, :content])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_length(:content, min: 1)
  end
end
