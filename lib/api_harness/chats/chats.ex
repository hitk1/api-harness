defmodule ApiHarness.Chats do
  @moduledoc """
  Chat thread and message management context (US2, US3).
  """
  import Ecto.Query

  alias ApiHarness.Accounts.User
  alias ApiHarness.Chats.{Chat, Message}
  alias ApiHarness.Memory.SessionMemory
  alias ApiHarness.Repo

  # ---------------------------------------------------------------------------
  # Chats
  # ---------------------------------------------------------------------------

  @doc """
  Create a chat thread for `user` and initialize an empty session memory for it.
  `user_id` is set on the struct — excluded from `cast/3` (Data Integrity).
  """
  @spec create_chat(User.t(), map()) :: {:ok, Chat.t()} | {:error, Ecto.Changeset.t()}
  def create_chat(%User{} = user, attrs \\ %{}) do
    Repo.transaction(fn ->
      chat =
        %Chat{user_id: user.id}
        |> Chat.changeset(attrs)
        |> Repo.insert!()

      %SessionMemory{chat_id: chat.id}
      |> SessionMemory.changeset(%{state: %{}})
      |> Repo.insert!()

      chat
    end)
  end

  @doc "List all chat threads belonging to `user`, newest first."
  @spec list_chats(User.t()) :: [Chat.t()]
  def list_chats(%User{} = user) do
    Repo.all(from c in Chat, where: c.user_id == ^user.id, order_by: [desc: c.inserted_at])
  end

  @doc """
  Fetch one thread by id, verifying ownership. Preloads messages ordered by
  `inserted_at`. Returns `nil` when not found or not owned by `user`.
  """
  @spec get_chat(User.t(), integer() | String.t()) :: Chat.t() | nil
  def get_chat(%User{} = user, id) do
    query =
      from c in Chat,
        where: c.id == ^to_id(id) and c.user_id == ^user.id,
        preload: [messages: ^from(m in Message, order_by: [asc: m.inserted_at])]

    Repo.one(query)
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  @doc """
  Persist a message in `chat`. `role` is `\"user\"` or `\"assistant\"`. `chat_id`
  is set on the struct — excluded from `cast/3`.
  """
  @spec add_message(Chat.t(), String.t(), String.t()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def add_message(%Chat{} = chat, role, content) do
    %Message{chat_id: chat.id}
    |> Message.changeset(%{role: role, content: content})
    |> Repo.insert()
  end

  @doc """
  Return up to `limit` most recent messages in `chat`, in chronological order
  (ascending `inserted_at`). Used by `ContextBuilder` for layer 5 of the prompt.
  """
  @spec list_recent_messages(Chat.t(), non_neg_integer()) :: [Message.t()]
  def list_recent_messages(%Chat{} = chat, limit) do
    Repo.all(
      from m in Message,
        where: m.chat_id == ^chat.id,
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^limit
    )
    |> Enum.reverse()
  end

  defp to_id(id) when is_binary(id), do: String.to_integer(id)
  defp to_id(id), do: id
end
