defmodule ApiHarness.Memory.Pipeline.Supervisor do
  @moduledoc """
  Named `DynamicSupervisor` for async memory pipeline workers (FR-023, FR-024).

  Spawns one short-lived `Pipeline.Worker` GenServer per interaction
  (fire-and-forget after the HTTP response is sent). Workers run independently;
  N concurrent users → N isolated workers.
  """
  use DynamicSupervisor

  alias ApiHarness.Memory.Pipeline.Worker

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a pipeline worker for `interaction`. Fire-and-forget."
  @spec start_worker(map()) :: {:ok, pid()} | {:error, term()}
  def start_worker(interaction) when is_map(interaction) do
    DynamicSupervisor.start_child(__MODULE__, {Worker, interaction})
  end
end
