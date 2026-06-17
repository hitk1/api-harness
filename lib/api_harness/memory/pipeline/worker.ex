defmodule ApiHarness.Memory.Pipeline.Worker do
  @moduledoc """
  Short-lived GenServer that runs one interaction's async memory pipeline
  (FR-023, FR-024, research §6):

    extraction → classification → reconciliation → persistence

  Retries each stage up to 3 times with linear backoff. On exhaustion, logs
  and discards — failure never surfaces to the user (FR-024-A). No dead-letter.

  Registered in `ApiHarness.Memory.Pipeline.Registry` under `chat_id` so in-
  flight jobs are observable.
  """
  use GenServer, restart: :temporary

  require Logger

  alias ApiHarness.Memory
  alias ApiHarness.Memory.{Extractor, Reconciler}

  @max_retries 3
  @retry_base_ms 200

  def start_link(interaction) do
    GenServer.start_link(__MODULE__, interaction,
      name: via(interaction[:chat_id] || interaction["chat_id"])
    )
  end

  @impl GenServer
  def init(interaction) do
    send(self(), :run)
    {:ok, %{interaction: interaction, attempt: 0}}
  end

  @impl GenServer
  def handle_info(:run, %{interaction: interaction, attempt: attempt} = state) do
    case run_pipeline(interaction) do
      :ok ->
        {:stop, :normal, state}

      {:error, reason} when attempt < @max_retries ->
        Logger.warning(
          "Memory pipeline attempt #{attempt + 1} failed: #{inspect(reason)}. Retrying."
        )

        Process.send_after(self(), :run, @retry_base_ms * (attempt + 1))
        {:noreply, %{state | attempt: attempt + 1}}

      {:error, reason} ->
        Logger.error(
          "Memory pipeline failed after #{@max_retries} retries: #{inspect(reason)}. Discarding."
        )

        {:stop, :normal, state}
    end
  end

  defp run_pipeline(interaction) do
    user_id = interaction[:user_id] || interaction["user_id"]
    chat_id = interaction[:chat_id] || interaction["chat_id"]
    message = interaction[:message] || interaction["message"]

    with {:ok, candidates} <- Extractor.extract(message),
         {:ok, reconciled} <- Reconciler.reconcile(user_id, candidates),
         :ok <- persist_results(user_id, chat_id, reconciled) do
      :ok
    end
  end

  defp persist_results(user_id, _chat_id, reconciled_candidates) do
    Enum.reduce_while(reconciled_candidates, :ok, fn candidate, :ok ->
      case Memory.apply_reconciliation(user_id, candidate) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp via(nil), do: {:via, Registry, {ApiHarness.Memory.Pipeline.Registry, make_ref()}}
  defp via(id), do: {:via, Registry, {ApiHarness.Memory.Pipeline.Registry, id}}
end
