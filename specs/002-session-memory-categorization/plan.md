# Implementation Plan: Categorized Session Memory

**Branch**: `002-session-memory-categorization` | **Date**: 2026-07-14 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-session-memory-categorization/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Refactor the existing per-thread session-memory update flow so it stops overwriting a flat `last_question`/`last_answer` pair every turn and instead organizes retained thread context into four categories (`goal`, `fact`, `constraint`, `preference` — the same taxonomy already used by persistent memory) that are reconciled turn-by-turn (create/update/merge/discard), not blindly replaced. The update runs off the response path through a single, statically-supervised `Coordinator` GenServer that consumes turn events over the application's existing `Phoenix.PubSub`, dispatching per-thread reconciliation jobs concurrently across threads (but sequentially within one thread) via a supervised `Task.Supervisor`. No new database tables, columns, or external dependencies are introduced — only the shape written into the existing `session_memories.state` jsonb column changes, alongside new reconciliation and coordination modules.

## Technical Context

**Language/Version**: Elixir ~> 1.15, Erlang/OTP (BEAM) — same as `001-legal-ai-agent-harness`, no change.

**Primary Dependencies**: No new dependencies. Reuses `Phoenix.PubSub` (already running as `ApiHarness.PubSub` in the supervision tree), OTP `Task.Supervisor`, and the existing `ApiHarness.LLM.Provider` structured-output pattern used by `Extractor`/`Reconciler`.

**Storage**: PostgreSQL, unchanged. No migrations — this feature only changes the JSON shape written into the existing `session_memories.state` column (see [data-model.md](./data-model.md)).

**Testing**: ExUnit (`mix test`). `DataCase` for the new `SessionReconciler` and `Memory.apply_session_reconciliation/2` unit tests. Direct GenServer tests for `Coordinator` using `start_supervised!/1`, `Process.monitor/1` + `assert_receive`, and `Phoenix.PubSub` subscriptions in-test to observe completion (no `Process.sleep/1`, per constitution Test Discipline). OpenAI calls stubbed via the existing `Provider` test double — no live API calls in tests.

**Target Platform**: Linux server (BEAM release), same as `001-legal-ai-agent-harness`. Dev at `localhost:4000`.

**Project Type**: Single Phoenix web-service project (backend only). This feature is an internal refactor of the memory subsystem — no new routes, controllers, or JSON views; the public `/api` contract is unchanged.

**Performance Goals**: The categorized session-memory update MUST NOT add latency to the synchronous chat response (FR-006, SC-004) — it runs entirely after the response is returned. Concurrent users on different threads MUST NOT block one another (FR-006, US4 Acceptance Scenario 2); the same thread's turns are processed in order, one at a time, to avoid racing writes to its own `session_memories` row.

**Constraints**: Session memory categorization/reconciliation failures MUST NOT surface to the user and MUST NOT corrupt prior state (FR-007) — same retry-then-log-and-discard policy as the existing persistent-memory pipeline (2–3 attempts, linear backoff, no dead-letter). Thread isolation MUST be preserved — no category entry may leak across `chat_id`s (FR-004).

**Scale/Scope**: Refactor of one existing subsystem (`ApiHarness.Memory` — session-memory slice only). Touches ~2 existing modules (`ApiHarness.Memory`, `ApiHarness.Agent.Runtime`, `ApiHarnessWeb.MessageController`) and adds ~3 new modules (`SessionReconciler`, `SessionMemory.Coordinator`, plus its static `Task.Supervisor` child spec). The existing persistent-memory pipeline (`Pipeline.{Supervisor,Registry,Worker}`, `Extractor`, `Reconciler`) is untouched.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. API-First Design | ✅ PASS | No routes, controllers, or JSON views added or changed. `/api` contract is untouched — this is an internal memory-subsystem refactor. |
| II. Prescribed Tooling | ✅ PASS | No new dependencies. Reuses `Phoenix.PubSub` (already running) and OTP `Task.Supervisor` (standard library) instead of introducing anything new. |
| III. Elixir Idioms | ✅ PASS (design intent) | `Coordinator` and its `Task.Supervisor` are static children declared with explicit `:name` in `application.ex`. No `String.to_atom/1` on user input (candidate `kind`/`action` values are matched against a fixed, known set of literal strings, never converted to atoms). No list index access via `[]`. |
| IV. Data Integrity | ✅ PASS (design intent) | `chat_id` remains set on the struct/query, never in `cast/3`. `SessionMemory.changeset/2` unchanged. No new migration, so no risk of violating the `:string`-for-`:text` or migration-naming rules. |
| V. Test Discipline | ✅ PASS (design intent) | `Coordinator`/`Task.Supervisor` tests use `start_supervised!/1`; completion awaited via `Process.monitor/1` + `assert_receive` or a `Phoenix.PubSub` subscription — never `Process.sleep/1` or `Process.alive?/1` (see quickstart.md Notes for automated tests). |

**Result**: PASS — no violations. Complexity Tracking not required.

## Project Structure

### Documentation (this feature)

```text
specs/002-session-memory-categorization/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

No `contracts/` directory — this feature adds no new external interface. The public `/api` request/response contract (`specs/001-legal-ai-agent-harness/contracts/messages.md`) is unchanged; only internal memory-subsystem behavior is refactored.

### Source Code (repository root)

```text
lib/
├── api_harness/
│   ├── application.ex                       # MODIFIED: add Coordinator + its Task.Supervisor as static children
│   ├── memory/
│   │   ├── session_memory.ex                # UNCHANGED schema/changeset — only the `state` shape convention changes
│   │   ├── memory.ex                        # MODIFIED: add apply_session_reconciliation/2 (mirrors apply_reconciliation/2)
│   │   ├── extractor.ex                     # UNCHANGED — reused with a combined question+answer input for this flow
│   │   ├── reconciler.ex                    # UNCHANGED — persistent-memory reconciliation, untouched
│   │   ├── session_reconciler.ex            # NEW: per-category create/update/merge/discard decisions (research.md §3)
│   │   ├── session_memory/
│   │   │   └── coordinator.ex               # NEW: static GenServer — PubSub subscriber, per-chat_id queue, Task dispatch
│   │   └── pipeline/                        # UNCHANGED — existing persistent-memory async pipeline, untouched
│   │       ├── supervisor.ex
│   │       ├── registry.ex
│   │       └── worker.ex
│   └── agent/
│       └── runtime.ex                       # MODIFIED: remove inline Memory.update_session_memory/2 call
└── api_harness_web/
    └── controllers/
        └── message_controller.ex            # MODIFIED: dispatch_pipeline/3 also broadcasts the session-memory turn event

test/
└── api_harness/
    └── memory/
        ├── session_reconciler_test.exs      # NEW
        └── session_memory/
            └── coordinator_test.exs         # NEW
```

**Structure Decision**: Stays within the existing single Phoenix project and the existing `lib/api_harness/memory/` bounded context — no new top-level directory. The new `session_memory/coordinator.ex` submodule mirrors the naming pattern of the existing `memory/pipeline/` submodule for the persistent-memory pipeline, keeping the two async flows visually and structurally parallel even though the persistent-memory pipeline uses a `DynamicSupervisor` per interaction and this one uses a single static `Coordinator` (research.md §5–6).

## Complexity Tracking

> No constitution violations. Section intentionally empty.
