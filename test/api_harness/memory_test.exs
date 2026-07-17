defmodule ApiHarness.MemoryTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Chats
  alias ApiHarness.Memory

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, chat} = Chats.create_chat(user, %{title: "Test"})
    {:ok, chat: chat}
  end

  describe "apply_session_reconciliation/2" do
    test "create appends a new entry with a generated id", %{chat: chat} do
      assert {:ok, session_memory} =
               Memory.apply_session_reconciliation(chat.id, %{
                 "action" => "create",
                 "kind" => "fact",
                 "content" => "Cliente: João Silva"
               })

      assert [%{"id" => id, "content" => "Cliente: João Silva"}] = session_memory.state["fact"]
      assert is_binary(id)
    end

    test "update replaces only the targeted entry's content, leaving other entries untouched", %{
      chat: chat
    } do
      {:ok, session_memory} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "fact",
          "content" => "Contrato iniciado em 2019"
        })

      [%{"id" => target_id}] = session_memory.state["fact"]

      {:ok, _session_memory} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "fact",
          "content" => "Cliente: João Silva"
        })

      {:ok, session_memory} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "update",
          "kind" => "fact",
          "id" => target_id,
          "content" => "Contrato iniciado em 2018"
        })

      facts = session_memory.state["fact"]
      assert length(facts) == 2
      assert Enum.find(facts, &(&1["id"] == target_id))["content"] == "Contrato iniciado em 2018"
      assert Enum.any?(facts, &(&1["content"] == "Cliente: João Silva"))
    end

    test "discard leaves state unchanged", %{chat: chat} do
      {:ok, _} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "goal",
          "content" => "Determinar prazo prescricional"
        })

      {:ok, session_memory} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "discard",
          "kind" => "goal",
          "content" => "irrelevant"
        })

      assert length(session_memory.state["goal"]) == 1
    end

    test "an action targeting one category never touches other categories", %{chat: chat} do
      {:ok, _} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "constraint",
          "content" => "Não citar jurisprudência de outros estados"
        })

      {:ok, session_memory} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "fact",
          "content" => "Cliente: João Silva"
        })

      assert length(session_memory.state["constraint"]) == 1
      assert length(session_memory.state["fact"]) == 1
    end

    test "categorized session memory never leaks across chat threads (FR-004, SC-005)", %{
      chat: chat
    } do
      {:ok, user} = Accounts.create_user(%{@user_attrs | email: "other@example.com"})
      {:ok, other_chat} = Chats.create_chat(user, %{title: "Other"})

      {:ok, _} =
        Memory.apply_session_reconciliation(chat.id, %{
          "action" => "create",
          "kind" => "fact",
          "content" => "Cliente: João Silva"
        })

      assert Memory.get_session_memory(other_chat.id).state == %{}
    end
  end
end
