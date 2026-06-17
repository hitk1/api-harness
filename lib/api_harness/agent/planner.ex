defmodule ApiHarness.Agent.Planner do
  @moduledoc """
  Produces a structured execution plan for every message (FR-010, research §8).

  Always runs — no conditional bypass. Emits a single-step plan (direct answer)
  or a multi-step plan via OpenAI structured outputs. Returns
  `{:error, :planner_failed}` when the LLM cannot produce a valid plan
  (FR-010-B → 422).
  """

  alias ApiHarness.LLM.Provider

  @plan_schema %{
    type: "object",
    properties: %{
      steps: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            type: %{type: "string", enum: ["answer", "tool"]},
            tool: %{type: ["string", "null"]},
            input: %{type: "object"},
            parallel: %{type: "boolean"}
          },
          required: ["type", "tool", "input", "parallel"],
          additionalProperties: false
        }
      }
    },
    required: ["steps"],
    additionalProperties: false
  }

  @doc """
  Plan the next action given the assembled `messages` (the six-layer prompt).

  Returns `{:ok, steps}` where `steps` is a list of step maps, or
  `{:error, :planner_failed}` if the LLM cannot produce a valid plan.
  """
  @spec plan([map()]) :: {:ok, [map()]} | {:error, :planner_failed}
  def plan(messages) when is_list(messages) do
    planning_messages =
      messages ++
        [
          %{
            role: "user",
            content:
              "Based on the above context and question, produce a step-by-step execution plan in JSON. Use type \"answer\" for a direct response, or \"tool\" steps when tools are needed."
          }
        ]

    opts = [json_schema: @plan_schema, schema_name: "agent_plan"]

    case Provider.chat_completion(planning_messages, opts) do
      {:ok, %{"steps" => steps}} when is_list(steps) and steps != [] ->
        {:ok, steps}

      {:ok, _invalid} ->
        {:error, :planner_failed}

      {:error, _reason} ->
        {:error, :llm_unavailable}
    end
  end
end
