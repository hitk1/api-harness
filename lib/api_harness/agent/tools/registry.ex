defmodule ApiHarness.Agent.Tools.Registry do
  @moduledoc """
  Tool Registry — dispatch surface for the Executor (FR-012).

  Tools are registered as functions under atom names. The executor calls
  `execute/2` with the tool name from the plan step and an input map; the
  registry looks up the module and delegates. All tool calls go through here
  (no direct module calls from the executor).
  """

  @tools %{
    "read_document" => ApiHarness.Agent.Tools.ReadDocument,
    "search_entities" => ApiHarness.Agent.Tools.SearchEntities,
    "generate_report" => ApiHarness.Agent.Tools.GenerateReport
  }

  @doc """
  Execute the named tool with `input`. Returns `{:ok, result}` or
  `{:error, reason}`.
  """
  @spec execute(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute(tool_name, input) when is_binary(tool_name) do
    case Map.get(@tools, tool_name) do
      nil -> {:error, {:unknown_tool, tool_name}}
      module -> module.run(input)
    end
  end

  @doc "List all registered tool names."
  @spec list() :: [String.t()]
  def list, do: Map.keys(@tools)
end
