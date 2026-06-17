defmodule ApiHarness.Memory.RetrieverTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Memory
  alias ApiHarness.Memory.Retriever
  alias ApiHarness.LLMStub

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    LLMStub.reset()
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, user: user}
  end

  describe "retrieve/3" do
    test "returns top-K relevant memories", %{user: user} do
      for i <- 1..3 do
        Memory.apply_reconciliation(user.id, %{
          "action" => "create",
          "category" => "task",
          "kind" => "fact",
          "content" => "Legal fact #{i}",
          "durable" => true
        })
      end

      assert {:ok, results} = Retriever.retrieve(user.id, "legal question", k: 2)
      assert length(results) <= 2
    end

    test "category filter excludes unrelated memories", %{user: user} do
      Memory.apply_reconciliation(user.id, %{
        "action" => "create",
        "category" => "domain",
        "kind" => "fact",
        "content" => "Domain knowledge",
        "durable" => true
      })

      Memory.apply_reconciliation(user.id, %{
        "action" => "create",
        "category" => "user",
        "kind" => "preference",
        "content" => "User prefers summaries",
        "durable" => true
      })

      assert {:ok, results} = Retriever.retrieve(user.id, "question", category: "domain")
      assert Enum.all?(results, &(&1.category == "domain"))
    end

    test "returns empty list when user has no memories", %{user: user} do
      assert {:ok, []} = Retriever.retrieve(user.id, "any question")
    end
  end
end
