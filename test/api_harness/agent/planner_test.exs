defmodule ApiHarness.Agent.PlannerTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Agent.Planner
  alias ApiHarness.LLMStub

  @messages [%{role: "user", content: "What is the statute of limitations?"}]

  setup do
    LLMStub.reset()
    :ok
  end

  describe "plan/1" do
    test "returns {:ok, steps} when LLM produces a valid steps list" do
      LLMStub.set_chat_response_for("agent_plan", %{
        "steps" => [
          %{"type" => "answer", "tool" => nil, "input" => %{}, "parallel" => false}
        ]
      })

      assert {:ok, steps} = Planner.plan(@messages)
      assert is_list(steps)
      assert length(steps) > 0
    end

    test "returns {:error, :planner_failed} when LLM echoes the schema descriptor" do
      LLMStub.set_chat_response_for("agent_plan", %{
        "properties" => %{"steps" => []},
        "type" => "object"
      })

      assert {:error, :planner_failed} = Planner.plan(@messages)
    end

    test "returns {:error, :planner_failed} when LLM returns an empty steps list" do
      LLMStub.set_chat_response_for("agent_plan", %{"steps" => []})

      assert {:error, :planner_failed} = Planner.plan(@messages)
    end

    test "returns {:error, :llm_unavailable} when the LLM provider fails" do
      LLMStub.set_error({:http_error, 503, %{}})

      assert {:error, :llm_unavailable} = Planner.plan(@messages)
    end
  end
end
