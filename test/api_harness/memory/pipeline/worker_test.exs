defmodule ApiHarness.Memory.Pipeline.WorkerTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Accounts
  alias ApiHarness.Chats
  alias ApiHarness.LLMStub
  alias ApiHarness.Memory.Pipeline.Worker

  @user_attrs %{name: "Eduardo", email: "eduardo@example.com", password: "s3cr3tpass"}

  setup do
    LLMStub.reset()
    {:ok, user} = Accounts.create_user(@user_attrs)
    {:ok, chat} = Chats.create_chat(user, %{title: "Test"})
    {:ok, user: user, chat: chat}
  end

  describe "pipeline worker" do
    test "completes normally and stops (constitution: start_supervised!, no Process.sleep)", %{
      user: user,
      chat: chat
    } do
      message = %{role: "assistant", content: "O prazo prescricional é 2 anos.", chat_id: chat.id}
      interaction = %{user_id: user.id, chat_id: chat.id, message: message}

      pid = start_supervised!({Worker, interaction})
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end

    test "retries and eventually discards on repeated LLM failure", %{user: user, chat: chat} do
      LLMStub.set_error({:http_error, 503, %{}})

      message = %{role: "assistant", content: "Content that causes failures.", chat_id: chat.id}
      interaction = %{user_id: user.id, chat_id: chat.id, message: message}

      # Worker should still stop normally (log & discard — no crash)
      pid = start_supervised!({Worker, interaction})
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 10_000
    end
  end
end
