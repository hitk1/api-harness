defmodule ApiHarness.Agent.Executor do
  @moduledoc """
  Executes a plan produced by the Planner.

  Sequential steps run in order; groups of consecutive parallel steps (`"parallel": true`)
  are dispatched together through the Coordinator. The final `"answer"` step
  makes a direct LLM call to generate the assistant response.
  """

  alias ApiHarness.Agent.{Coordinator, Planner}
  alias ApiHarness.LLM.Provider

  require Logger

  @doc """
  Execute `steps` given the original prompt `messages`.

  Returns `{:ok, answer}` where `answer` is the assistant response string, or
  `{:error, reason}` on failure.
  """
  @spec execute([map()], [map()]) :: {:ok, String.t()} | {:error, term()}
  def execute(steps, messages) when is_list(steps) and is_list(messages) do
    {tool_steps, answer_step} = split_steps(steps)

    with :ok <- run_tool_steps(tool_steps),
         {:ok, answer} <- generate_answer(answer_step, messages) do
      {:ok, answer}
    end
  end

  defp split_steps(steps) do
    {tool_steps, answer_steps} = Enum.split_with(steps, &(&1["type"] == "tool"))
    answer_step = List.last(answer_steps) || %{"type" => "answer"}
    {tool_steps, answer_step}
  end

  defp run_tool_steps([]), do: :ok

  defp run_tool_steps(steps) do
    {parallel, sequential} = Enum.split_with(steps, & &1["parallel"])

    with :ok <- run_sequential(sequential),
         :ok <- run_parallel(parallel) do
      :ok
    end
  end

  defp run_sequential([]), do: :ok

  defp run_sequential([step | rest]) do
    case ApiHarness.Agent.Tools.Registry.execute(step["tool"], step["input"] || %{}) do
      {:ok, _} -> run_sequential(rest)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_parallel([]), do: :ok

  defp run_parallel(steps) do
    case Coordinator.run(steps) do
      {:ok, _results} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_answer(_answer_step, messages) do
    case Provider.chat_completion(messages) do
      {:ok, content} when is_binary(content) -> {:ok, content}
      {:ok, _other} -> {:error, :llm_unavailable}
      {:error, _reason} -> {:error, :llm_unavailable}
    end
  end

  # Suppress unused Planner alias warning — will be used in future expansions
  _ = Planner
end
