defmodule ApiHarness.Context.Compaction.Supervisor do
  @moduledoc "DynamicSupervisor for per-chat compaction workers."
  use DynamicSupervisor

  alias ApiHarness.Context.Compaction.Worker

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a compaction worker for chat_id if not already running."
  def start_worker(chat_id, user_id) do
    case Registry.lookup(ApiHarness.Context.Compaction.Registry, {:compaction, chat_id}) do
      [] ->
        DynamicSupervisor.start_child(__MODULE__, {Worker, {chat_id, user_id}})

      _ ->
        {:error, :already_running}
    end
  end
end
