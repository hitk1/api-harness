defmodule ApiHarness.Memory.SessionReconcilerTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Chats
  alias ApiHarness.LLMStub
  alias ApiHarness.Memory
  alias ApiHarness.Memory.SessionReconciler

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    LLMStub.reset()
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, chat} = Chats.create_chat(user, %{title: "Test"})
    {:ok, chat: chat}
  end

  describe "reconcile/2" do
    test "candidate for an empty category becomes create with no LLM call", %{chat: chat} do
      candidates = [
        %{"category" => "task", "kind" => "fact", "content" => "Cliente: João Silva"}
      ]

      assert {:ok, [reconciled]} = SessionReconciler.reconcile(chat.id, candidates)
      assert reconciled["action"] == "create"
      assert is_nil(reconciled["id"])
      assert reconciled["content"] == "Cliente: João Silva"
    end

    test "unknown kind is discarded", %{chat: chat} do
      candidates = [%{"category" => "task", "kind" => "unknown", "content" => "whatever"}]

      assert {:ok, [reconciled]} = SessionReconciler.reconcile(chat.id, candidates)
      assert reconciled["action"] == "discard"
    end

    test "empty candidates returns empty list", %{chat: chat} do
      assert {:ok, []} = SessionReconciler.reconcile(chat.id, [])
    end

    test "candidate overlapping an existing entry asks the LLM and targets its id", %{
      chat: chat
    } do
      {:ok, session_memory} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "fact",
          "content" => "Contrato iniciado em 2019"
        })

      [%{"id" => existing_id}] = session_memory.state["fact"]

      LLMStub.set_chat_response_for("session_reconciliation", %{
        "action" => "update",
        "id" => existing_id,
        "content" => "Contrato iniciado em 2018"
      })

      candidates = [
        %{"category" => "task", "kind" => "fact", "content" => "Na verdade foi em 2018"}
      ]

      assert {:ok, [reconciled]} = SessionReconciler.reconcile(chat.id, candidates)
      assert reconciled["action"] == "update"
      assert reconciled["id"] == existing_id
      assert reconciled["content"] == "Contrato iniciado em 2018"
    end

    test "LLM discard decision for redundant information", %{chat: chat} do
      {:ok, _session_memory} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "preference",
          "content" => "Prefere respostas objetivas"
        })

      LLMStub.set_chat_response_for("session_reconciliation", %{
        "action" => "discard",
        "id" => nil,
        "content" => ""
      })

      candidates = [
        %{"category" => "user", "kind" => "preference", "content" => "Oi, tudo bem?"}
      ]

      assert {:ok, [reconciled]} = SessionReconciler.reconcile(chat.id, candidates)
      assert reconciled["action"] == "discard"
    end
  end
end
