defmodule ApiHarness.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ApiHarnessWeb.Telemetry,
      ApiHarness.Repo,
      {DNSCluster, query: Application.get_env(:api_harness, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ApiHarness.PubSub},
      # Async memory pipeline: Registry + DynamicSupervisor (one worker per interaction).
      ApiHarness.Memory.Pipeline.Registry,
      ApiHarness.Memory.Pipeline.Supervisor,
      # Session-memory pipeline (spec 002): a single static Coordinator (no
      # DynamicSupervisor) dispatching per-thread jobs onto this Task.Supervisor.
      {Task.Supervisor, name: ApiHarness.Memory.SessionMemory.TaskSupervisor},
      ApiHarness.Memory.SessionMemory.Coordinator,
      # Start to serve requests, typically the last entry
      ApiHarnessWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ApiHarness.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ApiHarnessWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
