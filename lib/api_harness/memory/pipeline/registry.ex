defmodule ApiHarness.Memory.Pipeline.Registry do
  @moduledoc "Named Registry tracking in-flight pipeline workers (one per interaction)."

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [[keys: :unique, name: __MODULE__]]},
      type: :supervisor
    }
  end
end
