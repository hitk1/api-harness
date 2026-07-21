defmodule ApiHarness.Context.Compaction.Bootstrap do
  @moduledoc """
  Re-enqueues sessions that were flagged for compaction or left in
  compacting state when the application was last stopped.
  Called once from Application.start/2.
  """
  import Ecto.Query
  require Logger

  alias ApiHarness.Chats.Chat
  alias ApiHarness.Context.Compaction
  alias ApiHarness.Repo

  @doc "Find all pending/interrupted sessions and start compaction workers."
  @spec enqueue_pending() :: :ok
  def enqueue_pending do
    rows =
      Repo.all(
        from c in Chat,
          where: c.context_status in ["needs_compaction", "compacting"],
          select: {c.id, c.user_id}
      )

    count = length(rows)

    if count > 0 do
      Logger.info("Compaction.Bootstrap: re-enqueuing #{count} session(s)")

      Enum.each(rows, fn {chat_id, user_id} ->
        case Compaction.Supervisor.start_worker(chat_id, user_id) do
          {:ok, _} ->
            :ok

          {:error, :already_running} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Compaction.Bootstrap: could not start worker for chat_id=#{chat_id}: #{inspect(reason)}"
            )
        end
      end)
    end

    :ok
  end
end
