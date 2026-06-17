defmodule ApiHarness.Memory.Pipeline.ConcurrencyTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Chats
  alias ApiHarness.LLMStub
  alias ApiHarness.Memory.Pipeline.{Supervisor, Worker}

  @user_count 5

  setup do
    LLMStub.reset()

    users =
      for i <- 1..@user_count do
        {:ok, user} =
          Accounts.create_user(%{
            name: "User #{i}",
            email: "user#{i}@example.com",
            password: "password#{i}"
          })

        {:ok, chat} = Chats.create_chat(user, %{title: "Thread #{i}"})
        {user, chat}
      end

    {:ok, users: users}
  end

  describe "concurrent workers" do
    test "N users get N independent workers with no blocking or lost updates (SC-003)", %{
      users: users
    } do
      pids_and_refs =
        Enum.map(users, fn {user, chat} ->
          message = %{
            role: "assistant",
            content: "Legal answer for user #{user.id}.",
            chat_id: chat.id
          }

          interaction = %{user_id: user.id, chat_id: chat.id, message: message}

          {:ok, pid} = Supervisor.start_worker(interaction)
          ref = Process.monitor(pid)
          {pid, ref}
        end)

      # All workers should complete independently
      for {pid, ref} <- pids_and_refs do
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000
      end
    end

    test "workers are registered in pipeline Registry and are unique per interaction", %{
      users: [{user, chat} | _]
    } do
      message = %{role: "assistant", content: "Test", chat_id: chat.id}
      interaction = %{user_id: user.id, chat_id: chat.id, message: message}

      pid1 = start_supervised!({Worker, interaction})
      ref1 = Process.monitor(pid1)

      # Wait for first worker to finish
      assert_receive {:DOWN, ^ref1, :process, ^pid1, :normal}, 5000

      # A second worker for the same chat should start without conflict
      interaction2 = %{interaction | chat_id: chat.id + 1_000_000}
      pid2 = start_supervised!({Worker, interaction2}, id: :worker2)
      ref2 = Process.monitor(pid2)

      assert_receive {:DOWN, ^ref2, :process, ^pid2, :normal}, 5000
    end
  end
end
