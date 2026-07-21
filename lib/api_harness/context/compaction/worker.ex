defmodule ApiHarness.Context.Compaction.Worker do
  @moduledoc """
  GenServer that performs context compaction for a single chat thread.
  Transitions context_status: needs_compaction -> compacting -> ready.
  Retries up to 3 times with linear backoff on LLM failure.
  """
  use GenServer, restart: :temporary
  require Logger

  alias ApiHarness.Chats
  alias ApiHarness.Context.Compaction.Prompt
  alias ApiHarness.LLM.TokenCounter

  @max_retries 3
  @base_backoff_ms 200

  def start_link({chat_id, user_id}) do
    GenServer.start_link(__MODULE__, {chat_id, user_id}, name: via(chat_id))
  end

  defp via(chat_id) do
    {:via, Registry, {ApiHarness.Context.Compaction.Registry, {:compaction, chat_id}}}
  end

  @impl true
  def init({chat_id, user_id}) do
    {:ok, %{chat_id: chat_id, user_id: user_id, attempt: 0}, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, state) do
    %{chat_id: chat_id} = state
    Logger.info("Compaction.Worker starting for chat_id=#{chat_id}")

    case Chats.update_context_status(chat_id, "compacting") do
      {:ok, _} ->
        do_compact(state)

      {:error, reason} ->
        Logger.error("Compaction.Worker: failed to set compacting status: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  defp do_compact(%{chat_id: chat_id, attempt: attempt} = state) when attempt < @max_retries do
    chat = Chats.get_chat!(chat_id)
    messages = Chats.list_all_messages(chat_id)
    prompt_text = Prompt.build(messages, chat.rolling_summary)

    llm_messages = [%{role: "user", content: prompt_text}]
    provider = Application.get_env(:api_harness, ApiHarness.LLM)[:provider]

    case provider.chat_completion(llm_messages, []) do
      {:ok, summary} ->
        summary_tokens = TokenCounter.count(summary)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        attrs = %{
          rolling_summary: summary,
          rolling_summary_token_count: summary_tokens,
          total_context_tokens: 0,
          compaction_count: (chat.compaction_count || 0) + 1,
          last_compaction_at: now
        }

        case Chats.update_context_metrics(chat_id, attrs) do
          {:ok, _} ->
            Chats.update_context_status(chat_id, "ready")

            Logger.info(
              "Compaction.Worker: completed for chat_id=#{chat_id}, summary_tokens=#{summary_tokens}"
            )

            {:stop, :normal, state}

          {:error, reason} ->
            Logger.error("Compaction.Worker: failed to persist summary: #{inspect(reason)}")
            retry(state)
        end

      {:error, reason} ->
        Logger.warning(
          "Compaction.Worker: LLM error (attempt #{attempt + 1}/#{@max_retries}): #{inspect(reason)}"
        )

        retry(state)
    end
  end

  defp do_compact(%{chat_id: chat_id, attempt: attempt} = state) do
    Logger.error(
      "Compaction.Worker: exhausted #{attempt} retries for chat_id=#{chat_id}, reverting to needs_compaction"
    )

    Chats.update_context_status(chat_id, "needs_compaction")
    {:stop, :normal, state}
  end

  defp retry(%{attempt: attempt} = state) do
    backoff = @base_backoff_ms * (attempt + 1)
    Process.sleep(backoff)
    do_compact(%{state | attempt: attempt + 1})
  end
end
