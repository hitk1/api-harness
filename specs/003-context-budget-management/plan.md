# Implementation Plan: Context Budget Management

**Branch**: `003-context-budget-management` | **Date**: 2026-07-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-context-budget-management/spec.md`

## Summary

Replace the current unlimited `ContextBuilder` with a `ContextRuntime` that treats the LLM's context window as a finite budget, distributing tokens across six provider modules via a stateless `BudgetManager`. Pre-computed `token_count` columns (on `messages` and `persistent_memories`) eliminate live tokenization on the request path. A new async compaction pipeline generates LLM rolling summaries when session utilization crosses 70% of the available budget, preserving conversation continuity indefinitely. Sessions in compaction expose a state machine (`active → needs_compaction → compacting → ready`) with startup re-enqueue for resilience. Every message response includes a `context_metrics` object for frontend visibility. No new HTTP routes are introduced; the only API change is the addition of `context_metrics` to the existing message response.

## Technical Context

**Language/Version**: Elixir ~> 1.15, Erlang/OTP — same as `001` and `002`, no change.

**Primary Dependencies**:
- NEW: [`tiktoken`](https://hex.pm/packages/tiktoken) ~> 0.4 — Rustler NIF for exact token counting using `o200k_base` encoding (GPT-4o-mini). Requires Rust toolchain at compile time. Falls back to `ceil(byte_size(text) / 4)` if the NIF fails to load.
- Existing: `Phoenix.PubSub`, OTP `DynamicSupervisor`, `Registry`, `Task.Supervisor`, `ApiHarness.LLM.Provider` — no new deps beyond `tiktoken`.

**Storage**: PostgreSQL, three migrations:
1. `add_token_count_to_messages` — `:integer default 0`
2. `add_token_count_to_persistent_memories` — `:integer default 0`
3. `add_context_management_to_chats` — `context_status`, `rolling_summary`, `rolling_summary_token_count`, `total_context_tokens`, `compaction_count`, `last_compaction_at` + partial index

See [data-model.md](./data-model.md) for full column specs.

**Testing**: ExUnit (`mix test`). `DataCase` for schema/changeset tests. `ConnCase` for the 409 compacting response test. GenServer tests for `Compaction.Worker` using `start_supervised!/1` + `Process.monitor/1` + `assert_receive`. Unit tests for `BudgetManager` and `TokenCounter` are pure function tests (no process overhead). OpenAI calls stubbed via the existing `ApiHarness.LLMStub` — no live API calls in tests.

**Target Platform**: Same as `001` — Linux server BEAM release. Dev at `localhost:4000`. Rust toolchain required in CI/build environment for `tiktoken`.

**Project Type**: Single Phoenix web-service project (backend only). No new routes or controllers.

**Performance Goals**:
- Budget calculation adds < 1ms to request path (pure math, no I/O)
- Token counting is pre-computed at persistence time — zero overhead on request path for counted rows
- Compaction runs async (5–15s acceptable for a background job)

**Constraints**:
- Total assembled prompt MUST NOT exceed `context_window - output_reserve` for configured model (FR-001)
- Compaction MUST NOT run during LLM response generation (FR-021)
- Sessions in `compacting` status MUST reject new messages with 409 (FR-025)
- Budget distribution and provider abstraction MUST NOT add dependencies or break the existing `Agent.Runtime` flow (FR-010)

**Scale/Scope**: Medium. Touches ~6 existing modules and adds ~10 new modules. Three migrations. One new Mix task (`mix api_harness.backfill_token_counts`). No schema shape changes to existing `session_memories` or `memory_context_updates`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. API-First Design | ✅ PASS | No new routes or controllers. The only API change is adding `context_metrics` to the existing `POST /api/chats/:id/messages` response. All endpoints remain under `/api` and return JSON. |
| II. Prescribed Tooling | ✅ PASS | `tiktoken` is the only new dependency, added for token counting — a new capability with no existing prescribed alternative. HTTP client remains `Req`; JSON remains `Jason`; HTTP server remains `Bandit`. The character fallback (`byte_size/4`) uses only the Elixir standard library. |
| III. Elixir Idioms | ✅ PASS (design intent) | `BudgetManager` is a plain stateless module (pure functions). `Compaction.Supervisor` and `Compaction.Registry` are declared with explicit `:name` in `application.ex`. No `String.to_atom/1` on user input; `context_status` values are matched against a known fixed atom set. No list index access via `[]`. Providers return plain maps, not structs accessed with map-access syntax. |
| IV. Data Integrity | ✅ PASS (design intent) | `token_count`, `context_status`, `rolling_summary`, and all new columns are system-set fields — never in `cast/3`. Set explicitly on struct. Migrations generated via `mix ecto.gen.migration`. Fields use `:string` for text columns (`rolling_summary`, `context_status`). |
| V. Test Discipline | ✅ PASS (design intent) | `Compaction.Worker` tests use `start_supervised!/1`; completion awaited via `Process.monitor/1` + `assert_receive`. No `Process.sleep/1` or `Process.alive?/1`. `BudgetManager` and `TokenCounter` tested as pure functions without processes. |

**Result**: PASS — no violations. Complexity Tracking not required.

## Project Structure

### Documentation (this feature)

```text
specs/003-context-budget-management/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output (tokenizer, thresholds, OTP patterns)
├── data-model.md        # Phase 1 output (schema changes, conceptual entities)
├── quickstart.md        # Phase 1 output (validation scenarios)
├── contracts/
│   └── messages.md      # Delta contract for message response (context_metrics + 409)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
lib/
├── api_harness/
│   ├── application.ex                          # MODIFIED: add Compaction.Registry + Compaction.Supervisor;
│   │                                           # call Compaction.Bootstrap.enqueue_pending/0 after startup
│   ├── llm/
│   │   ├── open_ai.ex                          # UNCHANGED
│   │   └── token_counter.ex                    # NEW: wraps tiktoken NIF with character fallback;
│   │                                           # TokenCounter.count(text) :: integer
│   ├── chats/
│   │   ├── chat.ex                             # MODIFIED: add context_status, rolling_summary,
│   │   │                                       # rolling_summary_token_count, total_context_tokens,
│   │   │                                       # compaction_count, last_compaction_at fields
│   │   ├── message.ex                          # MODIFIED: add token_count field
│   │   └── chats.ex                            # MODIFIED: add_message/3 now sets token_count;
│   │                                           # new update_context_status/2, update_context_metrics/2
│   ├── memory/
│   │   ├── persistent_memory.ex                # MODIFIED: add token_count field;
│   │   │                                       # apply_reconciliation/2 sets token_count on create/update/merge
│   │   └── (all other memory modules)          # UNCHANGED
│   └── agent/
│       ├── context_builder.ex                  # REPLACED by context/runtime.ex (kept for backwards-compat
│       │                                       # or removed — runtime.ex is the new entry point)
│       ├── runtime.ex                          # MODIFIED: replace ContextBuilder.build call with
│       │                                       # Context.Runtime.build; receive and thread context_metrics
│       ├── context/
│       │   ├── runtime.ex                      # NEW: orchestrator — calls BudgetManager + providers,
│       │   │                                   # assembles prompt, returns {messages, context_metrics}
│       │   ├── budget_manager.ex               # NEW: stateless module; allocate/2 → %{system: N, ...}
│       │   └── providers/
│       │       ├── behaviour.ex                # NEW: @callback plan(opts) and provide(budget, opts)
│       │       ├── system_prompt.ex            # NEW: wraps @system_instruction; fixed cost
│       │       ├── domain_memory.ex            # NEW: wraps Memory.list_persistent_memories_by_category("domain")
│       │       ├── session_memory.ex           # NEW: wraps Memory.get_session_memory/1 + render
│       │       ├── persistent_memory.ex        # NEW: wraps Retriever.retrieve/3 (user + task categories)
│       │       ├── conversation.ex             # NEW: rolling_summary + Chats.list_recent_messages/2;
│       │       │                               # respects budget by fitting as many recent msgs as possible
│       │       └── user_question.ex            # NEW: current question; always included in full
│       └── context/
│           └── post_response.ex               # NEW: async analysis — updates total_context_tokens,
│                                              # flags needs_compaction if threshold exceeded
│   ├── context/
│   │   └── compaction/
│   │       ├── supervisor.ex                  # NEW: DynamicSupervisor(:name => Compaction.Supervisor)
│   │       ├── registry.ex                    # NEW: Registry(:unique, :name => Compaction.Registry)
│   │       ├── worker.ex                      # NEW: GenServer — loads messages, calls LLM, persists summary,
│   │       │                                  # transitions context_status; retry 3x linear backoff
│   │       ├── bootstrap.ex                   # NEW: enqueue_pending/0 — queries chats with
│   │       │                                  # context_status IN ('needs_compaction','compacting')
│   │       │                                  # and starts a Worker for each
│   │       └── prompt.ex                      # NEW: builds the LLM compaction prompt from messages +
│   │                                          # existing rolling_summary (9-section structure)
│
└── api_harness_web/
    └── controllers/
        ├── message_controller.ex               # MODIFIED: check context_status before processing (409 if
        │                                       # compacting); dispatch_pipeline/3 adds PostResponse.analyze;
        │                                       # pass context_metrics to JSON view
        └── message_json.ex                     # MODIFIED: render context_metrics in show/1

lib/mix/tasks/
└── api_harness.backfill_token_counts.ex        # NEW: one-time Mix task to populate token_count
                                                # on existing messages + persistent_memories

priv/repo/migrations/
├── YYYYMMDDHHMMSS_add_token_count_to_messages.exs
├── YYYYMMDDHHMMSS_add_token_count_to_persistent_memories.exs
└── YYYYMMDDHHMMSS_add_context_management_to_chats.exs

test/
└── api_harness/
    ├── llm/
    │   └── token_counter_test.exs              # NEW: count/1 with real text; fallback behaviour
    └── agent/
        ├── context/
        │   ├── runtime_test.exs                # NEW: prompt assembly + metrics correctness
        │   ├── budget_manager_test.exs         # NEW: allocation sums, proportions, redistribution
        │   └── providers/
        │       ├── conversation_provider_test.exs  # NEW: rolling summary + recent messages; budget fit
        │       ├── persistent_memory_provider_test.exs
        │       └── budget_enforcement_test.exs  # NEW: each provider returns ≤ allocated budget
        └── context/
            └── compaction/
                ├── worker_test.exs             # NEW: full lifecycle; retry behaviour; 409 guard
                └── bootstrap_test.exs          # NEW: enqueue_pending/0 discovers flagged sessions
```

**Structure Decision**: New modules live under `lib/api_harness/agent/context/` (providers, runtime, budget_manager, post_response) and `lib/api_harness/context/compaction/` (compaction pipeline). This keeps the agent's context assembly under `agent/context/` while separating the compaction OTP subsystem into `context/compaction/` to mirror the naming convention of `memory/pipeline/` for the persistent memory pipeline. The token counter lives under `llm/` since it's tightly coupled to the LLM model choice.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
