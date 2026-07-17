# Quickstart: Validating Categorized Session Memory

This guide validates the refactored session-memory flow end-to-end. See [data-model.md](./data-model.md) for the `state` shape and [research.md](./research.md) for the architecture behind each step.

## Prerequisites

- `mix setup` already run (dev DB created/migrated/seeded).
- A test/dev user and a JWT obtained via `POST /api/login` (per `specs/001-legal-ai-agent-harness/contracts/auth.md`).
- The OpenAI provider stub/test double configured (no live API calls needed for the scenarios below when run under `mix test`; a real `OPENAI_API_KEY` is needed only for manual dev-server exploration).

## Setup

```bash
mix phx.server            # or: iex -S mix phx.server
```

Create a chat thread (per `specs/001-legal-ai-agent-harness/contracts/chats.md`):

```bash
curl -s -X POST http://localhost:4000/api/chats \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}'
# => {"data": {"id": <chat_id>, ...}}
```

## Scenario 1 — Categorized entries appear after a turn (User Story 2)

```bash
curl -s -X POST http://localhost:4000/api/chats/<chat_id>/messages \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"content": "Preciso saber o prazo prescricional para rescisão indireta do meu cliente João Silva, contrato CLT desde 2019."}'
```

**Expected outcome**: the response returns normally (unaffected by the memory refactor). After a short delay (eventual consistency — the update runs off the response path), inspect the thread's session memory:

```elixir
# iex -S mix
ApiHarness.Memory.get_session_memory(<chat_id>).state
```

**Expected**: `state["goal"]` contains an entry about determining the statute of limitations; `state["fact"]` contains entries about the client name and contract type — not a flat `last_question`/`last_answer` pair (SC-002).

## Scenario 2 — Context continuity across turns (User Story 1)

Send a follow-up message in the **same thread** that depends on facts from Scenario 1 without repeating them:

```bash
curl -s -X POST http://localhost:4000/api/chats/<chat_id>/messages \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"content": "E esse prazo já teria passado?"}'
```

**Expected**: the response reasons about the case using the client/contract facts captured in Scenario 1, even though this message does not restate them (SC-001) — verifiable by inspecting the assembled context in the response or, in a test, asserting the `ContextBuilder` output includes the session-memory facts for this thread.

## Scenario 3 — Reconciliation without duplication (User Story 3)

Send a later message that refines a previously captured fact:

```bash
curl -s -X POST http://localhost:4000/api/chats/<chat_id>/messages \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"content": "Na verdade o contrato começou em 2018, não 2019."}'
```

**Expected**: `ApiHarness.Memory.get_session_memory(<chat_id>).state["fact"]` still has one entry for the contract start date (updated to 2018), not two conflicting entries (SC-003).

## Scenario 4 — Thread isolation preserved (FR-004)

Create a second thread for the same user and send any message to it.

**Expected**: `ApiHarness.Memory.get_session_memory(<second_chat_id>).state` shows no entries from the first thread's Scenarios 1–3 — categories are empty or contain only what this second thread's own turns produced (SC-005).

## Scenario 5 — Non-blocking behavior and graceful failure (User Story 4)

In a test (`test/api_harness/memory/session_memory/coordinator_test.exs` or similar), simulate a slow/failing `Provider` stub for one thread's extraction call while sending a message on a second, unrelated thread concurrently.

**Expected**:
- The HTTP response for both threads returns without waiting on the categorization/reconciliation work (SC-004).
- The second thread's session memory updates normally even while the first thread's job is retrying/failing (US4 Acceptance Scenario 2).
- After the first thread's job exhausts its retries, no error surfaces to the caller, and `get_session_memory/1` for that thread still returns its pre-failure state, unmodified (SC-006, FR-007).

## Notes for automated tests

- Prefer `start_supervised!/1` for the `Coordinator` and its `Task.Supervisor` in tests that exercise them directly (constitution Test Discipline).
- Do not use `Process.sleep/1` to wait for the async job to finish — use `Process.monitor/1` + `assert_receive {:DOWN, ...}` on the dispatched Task, or a `Phoenix.PubSub` subscription in the test itself to await the Coordinator's completion signal.
