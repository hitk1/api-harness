defmodule ApiHarness.Agent.Context.Runtime do
  @moduledoc """
  Assembles the LLM prompt from budget-aware providers (replaces ContextBuilder).
  Returns {messages, context_metrics} where messages is the OpenAI message list
  and context_metrics is the map for the API response.
  """

  alias ApiHarness.Accounts.User
  alias ApiHarness.Agent.Context.BudgetManager

  alias ApiHarness.Agent.Context.Providers.{
    Conversation,
    DomainMemory,
    PersistentMemory,
    SessionMemory,
    SystemPrompt
  }

  alias ApiHarness.Chats.Chat
  alias ApiHarness.LLM.TokenCounter

  require Logger

  @doc """
  Build the prompt message list for user, chat, and current question.
  Returns {messages, context_metrics}.
  """
  @spec build(User.t(), Chat.t(), String.t()) :: {[map()], map()}
  def build(%User{} = user, %Chat{} = chat, question) when is_binary(question) do
    profile = BudgetManager.default_profile()

    opts = [
      user_id: user.id,
      chat_id: chat.id,
      chat: chat,
      question: question
    ]

    # Measure fixed-cost layers first
    {system_content, system_tokens} = SystemPrompt.provide(0, opts)
    question_tokens = TokenCounter.count(question)

    # Allocate budget
    allocation =
      BudgetManager.allocate(profile,
        system_tokens: system_tokens,
        question_tokens: question_tokens
      )

    # Collect variable-cost providers
    {domain_content, domain_tokens} = DomainMemory.provide(allocation.domain, opts)
    {session_content, session_tokens} = SessionMemory.provide(allocation.session, opts)
    {memory_content, memory_tokens} = PersistentMemory.provide(allocation.memory, opts)

    # Conversation returns {summary, prior_turns, tokens} — special 3-tuple
    {_summary, prior_turns, conv_tokens} =
      Conversation.provide(allocation.conversation, opts)

    # Assemble system message content
    system_parts = [system_content]

    system_parts =
      if domain_content != "",
        do: system_parts ++ ["\n## Domain Knowledge\n#{domain_content}"],
        else: system_parts

    system_parts =
      if session_content != "",
        do: system_parts ++ ["\n## Current Session Context\n#{session_content}"],
        else: system_parts

    system_parts =
      if memory_content != "",
        do: system_parts ++ ["\n## Relevant User & Task Context\n#{memory_content}"],
        else: system_parts

    system_msg_content = Enum.join(system_parts, "\n")

    messages =
      [%{role: "system", content: system_msg_content}] ++
        prior_turns ++
        [%{role: "user", content: question}]

    total =
      system_tokens + domain_tokens + session_tokens + memory_tokens + conv_tokens +
        question_tokens

    if total > profile.available_budget do
      Logger.warning(
        "ContextRuntime: total #{total} exceeds available_budget #{profile.available_budget}"
      )
    end

    context_metrics = %{
      total_tokens: total,
      available_budget: profile.available_budget,
      utilization_percentage: total / profile.available_budget,
      context_status: chat.context_status || "active",
      layers: %{
        system: system_tokens,
        domain_memory: domain_tokens,
        session_memory: session_tokens,
        persistent_memory: memory_tokens,
        conversation: conv_tokens,
        question: question_tokens
      }
    }

    {messages, context_metrics}
  end
end
