defmodule ApiHarness.Memory.SessionMemory.Coordinator do
  @moduledoc """
  Single, statically-supervised GenServer handling ALL session-memory
  categorization/reconciliation demand, for every thread and every user
  (spec 002, FR-006/FR-007, research.md §5). Added as a static child of
  `ApiHarness.Application` — there is no `DynamicSupervisor` spawning one
  process per interaction or per thread.

  Subscribes at `init/1` to the configured `Phoenix.PubSub` topic, on which
  `ApiHarnessWeb.MessageController.dispatch_pipeline/3` broadcasts one turn
  event per interaction (a lightweight pub/sub handoff — no new dependency,
  `Phoenix.PubSub` already runs in the application's supervision tree).

  Each received turn is queued and dispatched to a supervised `Task` under
  `ApiHarness.Memory.SessionMemory.TaskSupervisor`. Distinct chat threads run
  fully concurrently (up to `max_concurrency`), but a single chat thread never
  has more than one job in flight at a time — this preserves per-turn
  ordering and avoids two jobs racing a read-modify-write on the same
  `session_memories` row, while guaranteeing one thread's slow/failing job
  never blocks another thread's update (US4 Acceptance Scenario 2).

  Each job runs extraction → session reconciliation → persistence, retrying
  up to `@max_retries` times with linear backoff; on exhaustion it logs and
  discards — failure never surfaces to the user (FR-007).

  `start_link/1` accepts `:name`, `:topic`, `:task_supervisor`, and
  `:max_concurrency` overrides (all default to the production singleton's
  values) so tests can start an isolated instance — unregistered (`name: nil`)
  or under a different name, listening on a different topic, dispatching to a
  different `Task.Supervisor` — without colliding with the one production
  instance started by `ApiHarness.Application`.
  """
  use GenServer

  require Logger

  alias ApiHarness.Memory
  alias ApiHarness.Memory.{Extractor, SessionReconciler}

  @max_retries 3
  @retry_base_ms 200
  @default_topic "session_memory:updates"
  @default_max_concurrency 10
  @default_task_supervisor ApiHarness.Memory.SessionMemory.TaskSupervisor

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Publish a turn event for `chat_id` on the production singleton's topic.
  Fire-and-forget — never blocks the caller on the Coordinator's own
  processing.
  """
  @spec enqueue(integer(), integer(), String.t(), String.t()) :: :ok
  def enqueue(chat_id, user_id, question, answer) do
    Phoenix.PubSub.broadcast(
      ApiHarness.PubSub,
      default_topic(),
      {:session_memory_turn,
       %{chat_id: chat_id, user_id: user_id, question: question, answer: answer}}
    )
  end

  @doc "Block until `pid` has processed every message queued before this call."
  @spec sync(GenServer.server()) :: :ok
  def sync(pid), do: GenServer.call(pid, :sync)

  defp default_topic, do: config()[:topic] || @default_topic

  defp config, do: Application.get_env(:api_harness, :session_memory, [])

  # --- GenServer callbacks ---------------------------------------------------

  @impl GenServer
  def init(opts) do
    topic = Keyword.get(opts, :topic, default_topic())
    Phoenix.PubSub.subscribe(ApiHarness.PubSub, topic)

    max_concurrency =
      Keyword.get(
        opts,
        :max_concurrency,
        Keyword.get(config(), :max_concurrency, @default_max_concurrency)
      )

    task_supervisor = Keyword.get(opts, :task_supervisor, @default_task_supervisor)

    {:ok,
     %{
       task_supervisor: task_supervisor,
       max_concurrency: max_concurrency,
       # chat_id => task ref currently running for that chat_id (at most one)
       in_flight: %{},
       # task ref => chat_id (reverse lookup for handle_info completion)
       refs: %{},
       # chat_id => :queue of {question, answer} awaiting that chat_id's turn
       pending: %{},
       # chat_ids waiting for a first global concurrency slot (may contain
       # harmless stale duplicates — see dispatch_waiting/1)
       waiting: :queue.new()
     }}
  end

  @impl GenServer
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl GenServer
  def handle_info(
        {:session_memory_turn, %{chat_id: chat_id, question: question, answer: answer}},
        state
      ) do
    {:noreply, enqueue_job(state, chat_id, {question, answer})}
  end

  def handle_info({ref, _result}, %{refs: refs} = state) when is_map_key(refs, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, job_finished(state, ref)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{refs: refs} = state)
      when is_map_key(refs, ref) do
    {:noreply, job_finished(state, ref)}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # --- queueing / dispatch ---------------------------------------------------

  defp enqueue_job(state, chat_id, job) do
    cond do
      Map.has_key?(state.in_flight, chat_id) ->
        push_pending(state, chat_id, job)

      map_size(state.in_flight) < state.max_concurrency ->
        start_job(state, chat_id, job)

      true ->
        state
        |> push_pending(chat_id, job)
        |> push_waiting(chat_id)
    end
  end

  defp push_pending(state, chat_id, job) do
    queue = Map.get(state.pending, chat_id, :queue.new())
    %{state | pending: Map.put(state.pending, chat_id, :queue.in(job, queue))}
  end

  defp push_waiting(state, chat_id) do
    %{state | waiting: :queue.in(chat_id, state.waiting)}
  end

  defp pop_pending(state, chat_id) do
    case Map.get(state.pending, chat_id) do
      nil ->
        {nil, state}

      queue ->
        case :queue.out(queue) do
          {{:value, job}, rest} ->
            pending =
              if :queue.is_empty(rest),
                do: Map.delete(state.pending, chat_id),
                else: Map.put(state.pending, chat_id, rest)

            {job, %{state | pending: pending}}

          {:empty, _} ->
            {nil, %{state | pending: Map.delete(state.pending, chat_id)}}
        end
    end
  end

  defp start_job(state, chat_id, {question, answer}) do
    %Task{ref: ref} =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        run_job(chat_id, question, answer)
      end)

    %{
      state
      | in_flight: Map.put(state.in_flight, chat_id, ref),
        refs: Map.put(state.refs, ref, chat_id)
    }
  end

  defp job_finished(state, ref) do
    {chat_id, refs} = Map.pop(state.refs, ref)
    state = %{state | refs: refs, in_flight: Map.delete(state.in_flight, chat_id)}

    case pop_pending(state, chat_id) do
      {nil, state} -> dispatch_waiting(state)
      {job, state} -> start_job(state, chat_id, job)
    end
  end

  # Pull the next distinct chat_id waiting for a first concurrency slot.
  # Entries can be harmless stale duplicates (see enqueue_job/3's `true`
  # branch) — skip a stale entry (already running, or already drained)
  # without losing its pending job.
  defp dispatch_waiting(state) do
    case :queue.out(state.waiting) do
      {:empty, _} ->
        state

      {{:value, chat_id}, rest} ->
        state = %{state | waiting: rest}

        cond do
          Map.has_key?(state.in_flight, chat_id) ->
            dispatch_waiting(state)

          map_size(state.in_flight) >= state.max_concurrency ->
            %{state | waiting: :queue.in(chat_id, state.waiting)}

          true ->
            case pop_pending(state, chat_id) do
              {nil, state} -> dispatch_waiting(state)
              {job, state} -> start_job(state, chat_id, job)
            end
        end
    end
  end

  # --- job execution (runs inside the supervised Task) -----------------------

  defp run_job(chat_id, question, answer) do
    turn_text = "User: #{question}\nAssistant: #{answer}"
    run_with_retries(chat_id, turn_text, 0)
  end

  defp run_with_retries(chat_id, turn_text, attempt) do
    case run_pipeline(chat_id, turn_text) do
      :ok ->
        :ok

      {:error, _reason} when attempt < @max_retries - 1 ->
        Process.sleep(@retry_base_ms * (attempt + 1))
        run_with_retries(chat_id, turn_text, attempt + 1)

      {:error, reason} ->
        Logger.error(
          "Session memory pipeline failed for chat #{chat_id} after #{@max_retries} attempts: " <>
            "#{inspect(reason)}. Discarding."
        )

        :ok
    end
  end

  defp run_pipeline(chat_id, turn_text) do
    with {:ok, candidates} <- Extractor.extract(%{content: turn_text}),
         {:ok, reconciled} <- SessionReconciler.reconcile(chat_id, candidates),
         :ok <- apply_all(chat_id, reconciled) do
      :ok
    end
  end

  defp apply_all(chat_id, reconciled) do
    Enum.reduce_while(reconciled, :ok, fn candidate, :ok ->
      case Memory.apply_session_reconciliation(chat_id, candidate) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
