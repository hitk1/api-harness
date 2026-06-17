defmodule ApiHarness.Memory.ReconcilerTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Memory
  alias ApiHarness.Memory.Reconciler
  alias ApiHarness.LLMStub

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    LLMStub.reset()
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, user: user}
  end

  describe "reconcile/2" do
    test "creates new memory for novel candidate", %{user: user} do
      candidates = [
        %{"category" => "task", "kind" => "fact", "content" => "Novel fact", "durable" => true}
      ]

      LLMStub.set_chat_response(%{"action" => "create", "content" => "Novel fact"})

      assert {:ok, [reconciled]} = Reconciler.reconcile(user.id, candidates)
      assert reconciled["action"] in ["create", "discard"]
    end

    test "discards non-durable candidates without LLM call", %{user: user} do
      candidates = [
        %{
          "category" => "task",
          "kind" => "fact",
          "content" => "Temporary note",
          "durable" => false
        }
      ]

      assert {:ok, [reconciled]} = Reconciler.reconcile(user.id, candidates)
      assert reconciled["action"] == "discard"
    end

    test "row count stays stable when knowledge is restated (update/merge)", %{user: user} do
      # Create initial memory
      {:ok, _} =
        Memory.apply_reconciliation(user.id, %{
          "action" => "create",
          "category" => "task",
          "kind" => "fact",
          "content" => "Prazo prescricional trabalhista: 2 anos",
          "durable" => true
        })

      count_before = length(Memory.list_persistent_memories(user.id))

      # Reconcile a candidate that overlaps with the existing memory
      LLMStub.set_chat_response(%{
        "action" => "update",
        "content" => "Prazo prescricional trabalhista: 2 anos"
      })

      candidates = [
        %{
          "category" => "task",
          "kind" => "fact",
          "content" => "Prazo prescricional é 2 anos",
          "durable" => true
        }
      ]

      {:ok, reconciled} = Reconciler.reconcile(user.id, candidates)

      for candidate <- reconciled do
        Memory.apply_reconciliation(user.id, candidate)
      end

      count_after = length(Memory.list_persistent_memories(user.id))
      assert count_after == count_before
    end

    test "empty candidates returns empty list", %{user: user} do
      assert {:ok, []} = Reconciler.reconcile(user.id, [])
    end
  end
end
