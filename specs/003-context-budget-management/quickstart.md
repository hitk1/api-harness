# Quickstart Validation Guide: Context Budget Management

Use this guide to validate that the feature works end-to-end after implementation. For full schema details see [data-model.md](./data-model.md). For contract details see [contracts/messages.md](./contracts/messages.md).

---

## Prerequisites

- Dev server running: `iex -S mix phx.server`
- A user and at least one chat thread created (see `specs/001-legal-ai-agent-harness/quickstart.md`)
- JWT token obtained and saved to `$TOKEN`
- `$CHAT_ID` set to an active chat thread ID

---

## Scenario 1: Token Count Pre-Computation (FR-001, FR-002, SC-003)

**Goal**: Verify `token_count` is populated on persisted messages and persistent memories.

**Steps**:

1. Send a message to the API:
   ```bash
   curl -s -X POST http://localhost:4000/api/chats/$CHAT_ID/messages \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"content": "O cliente se chama João Silva e o contrato é de trabalho."}' \
     | jq
   ```

2. In IEx, inspect the persisted message:
   ```elixir
   msg = ApiHarness.Repo.get_by!(ApiHarness.Chats.Message, chat_id: chat_id)
   msg.token_count  # should be > 0 (e.g., 17–22 for this text)
   ```

**Expected**: Both the user message and assistant message have `token_count > 0`. The assistant message's count reflects the response content.

---

## Scenario 2: Context Metrics in API Response (FR-027, SC-008)

**Goal**: Verify `context_metrics` is returned with each message response.

**Steps**:

1. Send any message:
   ```bash
   curl -s -X POST http://localhost:4000/api/chats/$CHAT_ID/messages \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"content": "Qual é o prazo prescricional para ação trabalhista?"}' \
     | jq '.context_metrics'
   ```

**Expected**:
```json
{
  "total_tokens": <positive integer>,
  "available_budget": 111616,
  "utilization_percentage": <float between 0.0 and 1.0>,
  "context_status": "active",
  "layers": {
    "system": <positive integer>,
    "domain_memory": <integer >= 0>,
    "session_memory": <integer >= 0>,
    "persistent_memory": <integer >= 0>,
    "conversation": <positive integer>,
    "question": <positive integer>
  }
}
```

**Invariant**: `layers.system + layers.domain_memory + layers.session_memory + layers.persistent_memory + layers.conversation + layers.question == total_tokens` (within 1 token of rounding).

---

## Scenario 3: Budget Enforcement (FR-005, FR-006, SC-001)

**Goal**: Verify the total prompt tokens never exceed the available budget.

**Steps** (IEx):

```elixir
# Inspect the Budget Manager directly with a mock over-full scenario
alias ApiHarness.Agent.BudgetManager

profile = BudgetManager.default_profile()
profile.context_window          # should be 128_000
profile.output_reserve          # should be 16_384
profile.available_budget        # should be ~111_616

allocation = BudgetManager.allocate(profile)
# Sum all layer budgets — must be <= available_budget
total = allocation |> Map.drop([:total, :available_budget]) |> Map.values() |> Enum.sum()
total <= profile.available_budget  # must be true
```

**Expected**: `true`.

---

## Scenario 4: Compaction Threshold Detection (FR-024, SC-006)

**Goal**: Verify that when context utilization crosses the threshold, the session is flagged.

**Steps** (IEx, simulated):

```elixir
alias ApiHarness.Chats
alias ApiHarness.Context.PostResponse

# Manually simulate a post-response analysis with high token count
# (threshold is 70% of available_budget = ~78,131 tokens)
chat = Chats.get_chat!(chat_id)
PostResponse.analyze(chat, total_context_tokens: 85_000)  # above 70% threshold

# Verify the chat is now flagged
updated = Chats.get_chat!(chat_id)
updated.context_status  # should be "needs_compaction"
updated.total_context_tokens  # should be 85_000
```

**Expected**: `context_status == "needs_compaction"`.

---

## Scenario 5: Compaction Worker Lifecycle (FR-022, FR-023, FR-025, SC-007)

**Goal**: Verify a session flagged for compaction transitions through the lifecycle correctly.

**Steps** (IEx):

```elixir
alias ApiHarness.Context.Compaction

# Start a compaction worker for the flagged chat
{:ok, pid} = Compaction.enqueue(chat_id)

# Worker starts in `compacting` state
chat = ApiHarness.Chats.get_chat!(chat_id)
chat.context_status  # "compacting"

# Wait for compaction to finish (monitor the process)
ref = Process.monitor(pid)
receive do
  {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
end, 30_000

# Verify final state
chat = ApiHarness.Chats.get_chat!(chat_id)
chat.context_status           # "ready"
chat.rolling_summary          # non-nil string with structured summary
chat.rolling_summary_token_count  # > 0
chat.compaction_count         # 1
chat.last_compaction_at       # non-nil datetime
```

**Expected**: All assertions pass. The rolling summary is a non-empty structured text.

---

## Scenario 6: Blocked Interaction During Compaction (FR-025, US5 acceptance 4)

**Goal**: Verify that messages to a thread in `compacting` status return 409.

**Steps**:

1. In IEx, force the chat to `compacting` status:
   ```elixir
   ApiHarness.Chats.update_context_status(chat_id, "compacting")
   ```

2. Attempt to send a message:
   ```bash
   curl -s -X POST http://localhost:4000/api/chats/$CHAT_ID/messages \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"content": "Olá, pode me ajudar?"}' \
     | jq
   ```

**Expected**:
```json
HTTP 409 Conflict
{
  "errors": {
    "detail": "Session compaction is in progress. Please wait a moment and try again."
  }
}
```

---

## Scenario 7: Startup Re-Enqueue (FR-026, SC-007)

**Goal**: Verify that sessions flagged at shutdown are re-processed on startup.

**Steps**:

1. In IEx, flag a session:
   ```elixir
   ApiHarness.Chats.update_context_status(chat_id, "needs_compaction")
   ```

2. Restart the application:
   ```bash
   # Stop and restart the dev server
   mix phx.server
   ```

3. In IEx after restart, check the chat:
   ```elixir
   # Give it a few seconds for Bootstrap to run
   Process.sleep(3_000)
   chat = ApiHarness.Chats.get_chat!(chat_id)
   chat.context_status  # "ready" or "compacting" (compaction in progress)
   ```

**Expected**: The session was discovered by `Compaction.Bootstrap` and a worker was started. Eventually transitions to `"ready"`.

---

## Scenario 8: Rolling Summary Content (FR-019, SC-005)

**Goal**: Verify that the rolling summary captures content from early conversation turns.

**Steps**:

1. Send 5 messages establishing facts in a thread:
   - "O cliente se chama João Silva"
   - "O contrato é de trabalho por tempo indeterminado"
   - "O valor do salário é R$ 5.000 mensais"
   - "A empresa se chama Acme Ltda"
   - "João foi demitido sem justa causa em março"

2. Manually trigger compaction (from IEx).

3. Inspect the rolling summary:
   ```elixir
   chat = ApiHarness.Chats.get_chat!(chat_id)
   IO.puts(chat.rolling_summary)
   ```

**Expected**: The summary contains references to João Silva, Acme Ltda, R$ 5.000, demissão sem justa causa — i.e., facts from early turns that would otherwise have been outside the recent-messages window.

---

## Notes

- Tests for `BudgetManager`, `TokenCounter`, `ContextRuntime`, and each provider are in `test/api_harness/agent/` — run with `mix test test/api_harness/agent/`.
- The compaction worker calls the real LLM in integration tests using `ApiHarness.LLMStub` — no live API calls.
- Run `mix api_harness.backfill_token_counts` once after migration to populate `token_count` for pre-existing rows.
- Run `mix precommit` before committing — this feature adds the `tiktoken` dependency which requires Rust; ensure `rustup` is available in the build environment.
