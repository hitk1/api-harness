defmodule ApiHarness.Agent.Coordinator do
  @moduledoc """
  Runs parallelizable plan steps concurrently using `Task.async_stream/3`
  with `timeout: :infinity` (constitution Principle III, research §7).

  Fail-total: if any worker returns an error or raises, the coordinator
  halts and returns an error — no partial results (FR-011).
  """

  alias ApiHarness.Agent.Tools.Registry, as: ToolRegistry

  @doc """
  Execute `steps` (a list of tool-step maps) in parallel. Each step must have
  a `"tool"` name and `"input"` map.

  Returns `{:ok, results}` where `results` is a list of `{:ok, value}` tuples in
  step order, or `{:error, reason}` if any step fails (fail-total).
  """
  @spec run([map()]) :: {:ok, [term()]} | {:error, term()}
  def run(steps) when is_list(steps) do
    results =
      Task.async_stream(
        steps,
        fn %{"tool" => tool, "input" => input} -> ToolRegistry.execute(tool, input) end,
        timeout: :infinity,
        on_timeout: :kill_task
      )
      |> Enum.reduce_while([], fn
        {:ok, {:ok, result}}, acc -> {:cont, [result | acc]}
        {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
        {:exit, reason}, _acc -> {:halt, {:error, {:worker_exit, reason}}}
      end)

    case results do
      {:error, reason} -> {:error, reason}
      list -> {:ok, Enum.reverse(list)}
    end
  end
end
