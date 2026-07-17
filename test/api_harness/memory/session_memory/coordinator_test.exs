defmodule ApiHarness.Memory.SessionMemory.CoordinatorTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Chats
  alias ApiHarness.LLMStub
  alias ApiHarness.Memory
  alias ApiHarness.Memory.SessionMemory.Coordinator

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    LLMStub.reset()
    {:ok, user} = Accounts.create_user(@user_attrs)
    task_sup = start_supervised!(Task.Supervisor)

    coordinator =
      start_supervised!({Coordinator, name: nil, task_supervisor: task_sup, max_concurrency: 10})

    {:ok, user: user, task_sup: task_sup, coordinator: coordinator}
  end

  describe "single turn" do
    test "processes a turn end-to-end without crashing the Coordinator", %{
      user: user,
      coordinator: coordinator
    } do
      {:ok, chat} = Chats.create_chat(user, %{title: "T"})

      send(
        coordinator,
        {:session_memory_turn,
         %{chat_id: chat.id, user_id: user.id, question: "Qual o prazo?", answer: "2 anos."}}
      )

      Coordinator.sync(coordinator)
      wait_for_idle(coordinator, chat.id)

      assert Process.alive?(coordinator)
      state = Memory.get_session_memory(chat.id).state
      assert Map.keys(state) -- ~w(goal fact constraint preference) == []
    end

    test "retries on repeated failure, then logs and discards without crashing", %{
      user: user,
      coordinator: coordinator
    } do
      {:ok, chat} = Chats.create_chat(user, %{title: "T"})
      LLMStub.set_error({:http_error, 503, %{}})

      send(
        coordinator,
        {:session_memory_turn, %{chat_id: chat.id, user_id: user.id, question: "Q", answer: "A"}}
      )

      Coordinator.sync(coordinator)
      wait_for_idle(coordinator, chat.id)

      assert Process.alive?(coordinator)
      assert Memory.get_session_memory(chat.id).state == %{}
    end
  end

  describe "concurrency across threads, ordering within a thread" do
    test "different chat_ids run concurrently; the same chat_id never overlaps itself", %{
      user: user,
      coordinator: coordinator
    } do
      {:ok, chat_a} = Chats.create_chat(user, %{title: "A"})
      {:ok, chat_b} = Chats.create_chat(user, %{title: "B"})
      test_pid = self()

      LLMStub.set_chat_response_for("knowledge_extraction", fn _messages, _opts ->
        send(test_pid, {:extraction_started, self()})

        receive do
          :release -> :ok
        end

        {:ok, %{"items" => []}}
      end)

      # Turn 1 for chat_a starts and blocks inside extraction.
      send(
        coordinator,
        {:session_memory_turn,
         %{chat_id: chat_a.id, user_id: user.id, question: "Qa1", answer: "Aa1"}}
      )

      Coordinator.sync(coordinator)
      assert_receive {:extraction_started, task_a1_pid}, 1000

      # Turn 2 for the SAME chat_id must queue, not start a second task.
      send(
        coordinator,
        {:session_memory_turn,
         %{chat_id: chat_a.id, user_id: user.id, question: "Qa2", answer: "Aa2"}}
      )

      Coordinator.sync(coordinator)
      refute_receive {:extraction_started, _}, 200

      state = :sys.get_state(coordinator)
      assert map_size(state.in_flight) == 1
      assert Map.has_key?(state.pending, chat_a.id)

      # A turn for a DIFFERENT chat_id must start immediately, concurrently —
      # chat_a's turn 1 is still blocked at this point.
      send(
        coordinator,
        {:session_memory_turn,
         %{chat_id: chat_b.id, user_id: user.id, question: "Qb1", answer: "Ab1"}}
      )

      Coordinator.sync(coordinator)
      assert_receive {:extraction_started, task_b1_pid}, 1000
      assert task_b1_pid != task_a1_pid

      # Release chat_b's turn and wait for it to fully finish.
      ref_b1 = Process.monitor(task_b1_pid)
      send(task_b1_pid, :release)
      assert_receive {:DOWN, ^ref_b1, :process, ^task_b1_pid, :normal}, 5000
      wait_for_idle(coordinator, chat_b.id)

      # Release chat_a's turn 1 — only now should turn 2 for chat_a start.
      ref_a1 = Process.monitor(task_a1_pid)
      send(task_a1_pid, :release)
      assert_receive {:DOWN, ^ref_a1, :process, ^task_a1_pid, :normal}, 5000
      assert_receive {:extraction_started, task_a2_pid}, 1000
      assert task_a2_pid != task_a1_pid

      ref_a2 = Process.monitor(task_a2_pid)
      send(task_a2_pid, :release)
      assert_receive {:DOWN, ^ref_a2, :process, ^task_a2_pid, :normal}, 5000
      wait_for_idle(coordinator, chat_a.id)

      final_state = :sys.get_state(coordinator)
      assert final_state.in_flight == %{}
      assert final_state.pending == %{}
    end
  end

  # Busy-poll `:sys.get_state/1` (constitution-endorsed synchronization
  # primitive) until `chat_id` has no in-flight or pending job left. Bounded,
  # not time-based — no `Process.sleep/1`.
  defp wait_for_idle(coordinator, chat_id, attempts \\ 5_000_000)

  defp wait_for_idle(_coordinator, chat_id, 0) do
    flunk("Coordinator never went idle for chat_id=#{chat_id}")
  end

  defp wait_for_idle(coordinator, chat_id, attempts) do
    state = :sys.get_state(coordinator)

    if Map.has_key?(state.in_flight, chat_id) or Map.has_key?(state.pending, chat_id) do
      wait_for_idle(coordinator, chat_id, attempts - 1)
    else
      :ok
    end
  end
end
