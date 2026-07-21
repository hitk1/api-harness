defmodule Mix.Tasks.ApiHarness.BackfillTokenCounts do
  @moduledoc """
  One-time Mix task to populate token_count for existing messages and
  persistent memories that have token_count = 0.

  Usage: mix api_harness.backfill_token_counts
  """
  use Mix.Task
  import Ecto.Query

  alias ApiHarness.Chats.Message
  alias ApiHarness.LLM.TokenCounter
  alias ApiHarness.Memory.PersistentMemory
  alias ApiHarness.Repo

  @shortdoc "Backfill token_count for existing messages and persistent memories"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    backfill_messages()
    backfill_persistent_memories()
  end

  defp backfill_messages do
    rows = Repo.all(from m in Message, where: m.token_count == 0, select: {m.id, m.content})
    Mix.shell().info("Backfilling #{length(rows)} messages...")

    Enum.each(rows, fn {id, content} ->
      tc = TokenCounter.count(content)
      Repo.update_all(from(m in Message, where: m.id == ^id), set: [token_count: tc])
    end)

    Mix.shell().info("Messages done.")
  end

  defp backfill_persistent_memories do
    rows =
      Repo.all(
        from pm in PersistentMemory, where: pm.token_count == 0, select: {pm.id, pm.content}
      )

    Mix.shell().info("Backfilling #{length(rows)} persistent memories...")

    Enum.each(rows, fn {id, content} ->
      tc = TokenCounter.count(content)
      Repo.update_all(from(pm in PersistentMemory, where: pm.id == ^id), set: [token_count: tc])
    end)

    Mix.shell().info("Persistent memories done.")
  end
end
