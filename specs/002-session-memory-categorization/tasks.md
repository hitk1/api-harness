---
description: "Task list for Categorized Session Memory implementation"
---

# Tasks: Categorized Session Memory

**Input**: Design documents from `/specs/002-session-memory-categorization/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Included. The constitution's Test Discipline principle (V) is MUST-level; each story gets ExUnit context/GenServer tests. OpenAI is always stubbed in tests (no live calls), same convention as `001-legal-ai-agent-harness`.

**Organization**: Tasks are grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1–US4)
- All paths are relative to the repository root

## Path Conventions

Single Phoenix project: domain under `lib/api_harness/`, web under `lib/api_harness_web/`, tests under `test/`. No new migrations for this feature — see `data-model.md`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Configuration this feature needs. No new Mix dependencies (research.md — Summary of new dependencies: none).

- [X] T001 [P] Add session-memory pipeline config (`config :api_harness, :session_memory, topic: "session_memory:updates", max_concurrency: 10`) in `config/config.exs`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared data contract every user story reads and writes.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Update the moduledoc of `lib/api_harness/memory/session_memory.ex` to document the categorized `state` shape (`%{"goal" => [%{"id" => uuid, "content" => string}], "fact" => [...], "constraint" => [...], "preference" => [...]}` per data-model.md) that all subsequent tasks read/write — no schema/changeset code changes, documentation only (no migration, per data-model.md)

**Checkpoint**: Shared `state` shape contract documented — user story implementation can begin.

---

## Phase 3: User Story 2 - Categorized Session Memory (Priority: P2) 🎯 sequenced first (see dependency note)

**Goal**: Replace the flat `last_question`/`last_answer` overwrite with categorized entries (`goal`/`fact`/`constraint`/`preference`) reconciled per-category, wired synchronously into the existing request path for now (async dispatch is introduced in US4).

**Independent Test**: After a turn, inspect `ApiHarness.Memory.get_session_memory(chat_id).state` and confirm it is structured into the four categories rather than a single `last_question`/`last_answer` pair (SC-002).

### Tests for User Story 2

- [X] T003 [P] [US2] `SessionReconciler` test in `test/api_harness/memory/session_reconciler_test.exs` (candidate with no existing entries in its category → `create` with a new uuid; candidate overlapping an existing entry → `update`/`merge` targeting that entry's id) using the LLM stub
- [X] T004 [P] [US2] `Memory.apply_session_reconciliation/2` test in `test/api_harness/memory_test.exs` (new file) covering `create` appends an entry to `state[kind]`, `update`/`merge` replaces only the matching-id entry's content, `discard` leaves `state` unchanged, and other categories are never touched by an action targeting one category

### Implementation for User Story 2

- [X] T005 [US2] Implement `SessionReconciler` in `lib/api_harness/memory/session_reconciler.ex`: for each extracted candidate, compare its `content` against the existing entries in `state[kind]` for the chat via one LLM call (structured output: `action` + optional target `id` + resulting `content`), per research.md §3
- [X] T006 [US2] Implement `Memory.apply_session_reconciliation/2` in `lib/api_harness/memory/memory.ex` (mirrors `apply_reconciliation/2`): `create` generates a new `Ecto.UUID.generate/0` entry and appends it to `state[kind]`; `update`/`merge` replace the content of the entry matching the given id; `discard` is a no-op; writes via `SessionMemory.changeset/2`
- [X] T007 [US2] In `lib/api_harness/agent/runtime.ex`, replace the inline `Memory.update_session_memory(chat.id, %{"last_question" => ..., "last_answer" => ...})` call with: build combined turn text (`"User: #{question}\nAssistant: #{answer}"`) → `Extractor.extract/1` → `SessionReconciler.reconcile/2` → `Memory.apply_session_reconciliation/2` per candidate (still synchronous/inline here — moved off the request path in US4, T020)
- [X] T008 [US2] Update `test/api_harness/agent/runtime_test.exs` to assert session memory reflects categorized entries (`goal`/`fact`/`constraint`/`preference`) after a turn instead of `last_question`/`last_answer`

**Checkpoint**: Session memory for a thread is categorized and reconciled per-category (SC-002), still running inline on the request path.

---

## Phase 4: User Story 3 - Reconciled Updates Without Duplication (Priority: P2)

**Goal**: Prove and harden that overlapping information updates/merges existing entries rather than duplicating, and that not-meaningfully-useful information is discarded — building directly on US2's `SessionReconciler`.

**Independent Test**: Establish a fact, then send a later message in the same thread that revises it; confirm the category ends with one updated entry, not two conflicting ones (SC-003).

**Depends on**: US2 (T005, T006 — the reconciler and apply function this story hardens).

### Tests for User Story 3

- [X] T009 [P] [US3] Extend `test/api_harness/memory/session_reconciler_test.exs` with a refinement scenario: an existing `fact` entry (e.g. contract start year) plus a candidate that corrects it → `action == "update"` targeting the existing entry's id, not `"create"`
- [X] T010 [P] [US3] Extend `test/api_harness/memory/session_reconciler_test.exs` with a discard scenario: a candidate with no meaningful new information (e.g. small talk / redundant restatement of an existing entry) → `action == "discard"`

### Implementation for User Story 3

- [X] T011 [US3] Refine the reconciliation prompt/schema in `lib/api_harness/memory/session_reconciler.ex` so the LLM reliably distinguishes `update` (overlapping/refining existing entry), `create` (unrelated new information), and `discard` (not meaningfully useful) per FR-003/FR-008
- [X] T012 [US3] Add an integration test in `test/api_harness/agent/runtime_test.exs` sending 3 sequential turns in one thread (establish a fact → refine that same fact → introduce an unrelated new fact) and asserting the category ends with exactly one updated entry for the refined fact plus one new entry for the unrelated fact — no duplicates (SC-003) — *implemented in this file during US3; superseded in US4 (T021) once `Runtime.run/3` stopped touching session memory directly. The no-duplication guarantee it proved is now covered at the reconciler/apply layer by `session_reconciler_test.exs` and `memory_test.exs` instead.*

**Checkpoint**: Categorized session memory reconciles without duplication or noise on the synchronous path.

---

## Phase 5: User Story 1 - Thread-Aware Context Continuity (Priority: P1) — sequenced after US2/US3 (see dependency note)

**Goal**: Later responses in a thread are grounded in the full accumulated categorized session memory, not just the immediately preceding turn, and the categorized state is rendered legibly (not as raw JSON with internal ids) in the LLM prompt.

**Independent Test**: Establish facts across several early turns; a later turn's question, which does not repeat those facts, still receives a response that reflects them (SC-001).

**Depends on**: US2 (categorized storage exists) + US3 (reconciliation is duplicate-free, so accumulated state stays clean over many turns).

### Tests for User Story 1

- [X] T013 [P] [US1] Extend `test/api_harness/agent/context_builder_test.exs`: given a session memory with entries across multiple categories, assert the rendered system message contains legible labeled sections (e.g. "Goal", "Facts", "Constraints", "Preferences") built from each entry's `content`, and does **not** leak internal `"id"` values into the prompt text
- [X] T014 [US1] Add an end-to-end test (`test/api_harness/agent/runtime_test.exs` or `test/api_harness_web/controllers/message_controller_test.exs`) simulating quickstart Scenario 2: a fact is established in turn 1; by turn 3 (which does not repeat it), assert — via the LLM stub's captured prompt — that the constructed context still includes the turn-1 fact — *initially added to `context_builder_test.exs` via `Runtime.run/3`; after US4 (T021) moved session-memory updates off `Runtime.run/3` onto the async Coordinator, this scenario now lives in `message_controller_test.exs`'s "categorized session memory" test, which drives the real HTTP → Coordinator → session memory path end-to-end.*

### Implementation for User Story 1

- [X] T015 [US1] Update `build_system_message/3` in `lib/api_harness/agent/context_builder.ex` (layer 3) to render `session_memory.state`'s categorized entries as labeled sections built from each entry's `content` field only, replacing the current raw `Jason.encode!(state)` dump
- [X] T016 [US1] Run quickstart.md Scenarios 1–2 manually against the dev server (or via the test suite with the LLM stub) to confirm cross-turn continuity end-to-end (SC-001)

**Checkpoint**: Responses are grounded in the thread's accumulated categorized context, rendered legibly (SC-001) — still synchronous under the hood.

---

## Phase 6: User Story 4 - Non-Blocking Updates (Priority: P3)

**Goal**: Move the categorization/reconciliation work (US2/US3's logic, currently inline per T007) off the response path via a single static `Coordinator` GenServer consuming turn events over `Phoenix.PubSub`, dispatching concurrently across threads but sequentially within one thread (research.md §5), without changing what that logic does.

**Independent Test**: The AI response returns before the session-memory update for that turn is guaranteed complete; a slow/failing job for one thread does not delay another thread's update; failures never surface to the user (SC-004, SC-006).

**Depends on**: US2 + US3 (the logic being moved off the request path) + T001 (config).

### Tests for User Story 4

- [X] T017 [P] [US4] `Coordinator` test in `test/api_harness/memory/session_memory/coordinator_test.exs`: receiving a broadcast enqueues and dispatches a job that runs extraction → reconciliation → apply; a stage failure retries up to 3 times with backoff then logs and discards without crashing the `Coordinator` (FR-007) — using `start_supervised!/1` and `Process.monitor/1` + `assert_receive` (no `Process.sleep/1`)
- [X] T018 [P] [US4] Concurrency test in `test/api_harness/memory/session_memory/coordinator_test.exs` (or a new `concurrency_test.exs` alongside it): jobs for two different `chat_id`s run concurrently (neither waits on the other), while two jobs queued for the *same* `chat_id` run strictly one after the other

### Implementation for User Story 4

- [X] T019 [US4] Implement `ApiHarness.Memory.SessionMemory.Coordinator` GenServer in `lib/api_harness/memory/session_memory/coordinator.ex`: subscribe to the configured PubSub topic at `init/1`; maintain an internal `:queue.queue()` per pending job; track in-flight `chat_id`s so at most one job per `chat_id` runs at a time while distinct `chat_id`s run concurrently via a supervised `Task.Supervisor`, up to `max_concurrency` (T001); each job runs `Extractor.extract/1` (combined turn text) → `SessionReconciler.reconcile/2` → `Memory.apply_session_reconciliation/2`; retries 2–3 times with linear backoff, then logs and discards (FR-007, mirrors the existing persistent-memory pipeline's policy)
- [X] T020 [US4] Add `ApiHarness.Memory.SessionMemory.Coordinator` and its named `Task.Supervisor` (`ApiHarness.Memory.SessionMemory.TaskSupervisor`) as static children of `ApiHarness.Application` in `lib/api_harness/application.ex`, alongside the existing persistent-memory pipeline's `Registry`/`DynamicSupervisor`
- [X] T021 [US4] Remove the inline extraction/reconciliation call from `lib/api_harness/agent/runtime.ex` (introduced in T007) — `Runtime.run/3` no longer touches session memory itself
- [X] T022 [US4] In `ApiHarnessWeb.MessageController.dispatch_pipeline/3` (`lib/api_harness_web/controllers/message_controller.ex`), broadcast the turn event (`chat_id`, `user_id`, `question`, `answer`) via `Phoenix.PubSub.broadcast/3` to the session-memory topic, alongside the existing persistent-memory pipeline dispatch

**Checkpoint**: Session-memory updates run fully off the response path, isolated per thread, with identical behavior to the synchronous version (SC-004, SC-006, FR-006, FR-007).

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation consistency and final validation gates.

- [X] T023 [P] Update the moduledocs of `lib/api_harness/memory/memory.ex` and `lib/api_harness/agent/runtime.ex` to reference this feature (002) alongside the existing 001 FR references, describing the new session-memory flow
- [X] T024 [P] Run quickstart.md Scenarios 3–5 end-to-end (reconciliation without duplication, thread isolation, non-blocking/graceful failure)
- [X] T025 Run `mix precommit` (compile warnings-as-errors, unused deps, format, full test suite — requires live Postgres)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **US2 (Phase 3)**: Depends on Foundational.
- **US3 (Phase 4)**: Depends on US2 (T005, T006).
- **US1 (Phase 5)**: Depends on US2 + US3 (categorized, duplicate-free storage to read from).
- **US4 (Phase 6)**: Depends on US2 + US3 (the logic it moves off the request path) + T001.
- **Polish (Phase 7)**: Depends on desired stories being complete.

### Story Priority vs. Dependency Note

Spec priorities are US1 (P1) > US2 (P2) = US3 (P2) > US4 (P3). US1 is the user-facing value, but its independent test requires categorized, duplicate-free storage (US2, US3) to already exist and be rendered into the prompt — so, exactly as `001-legal-ai-agent-harness` sequenced its P2 thread story before a P1 chat story for the same reason, US2 and US3 are implemented before US1 here. US4 is a pure "move this existing, already-correct logic off the request path" enhancement, so it naturally comes last regardless of its own priority.

### Within Each User Story

- Tests written first and expected to fail before implementation.
- Reconciler/apply logic before wiring into the request path; request-path wiring before prompt-rendering changes; synchronous correctness (US2/US3/US1) before the async refactor (US4).

### Parallel Opportunities

- Setup: only T001 (single task).
- US2: T003, T004 in parallel (distinct test files).
- US3: T009, T010 in parallel (same file, independent test cases — still safe to draft in parallel, sequence the actual file edits).
- US1: T013 can proceed in parallel with US4's test-writing (T017, T018) since they touch different files; T014 depends on T013's assertions existing conceptually but is a distinct file.
- US4: T017, T018 in parallel (distinct/independent test scenarios).
- Polish: T023, T024 in parallel.

---

## Parallel Example: User Story 2

```bash
# Tests for US2 together:
Task: "SessionReconciler test in test/api_harness/memory/session_reconciler_test.exs"
Task: "Memory.apply_session_reconciliation/2 test in test/api_harness/memory_test.exs"
```

---

## Implementation Strategy

### MVP First (User Stories 2 + 3)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US2 → 4. Phase 4 US3 → **STOP & VALIDATE**: session memory is categorized and duplicate-free on the synchronous path. This alone already fixes the core complaint (session memory no longer holds only the last Q&A pair).

### Incremental Delivery

Foundation → US2 (categorized, reconciled storage) → US3 (dedup hardening) → US1 (continuity + legible prompt rendering, the user-facing payoff) → US4 (non-blocking async refactor) → Polish. Each story adds value and is independently testable; US1's product value only becomes externally visible once US2/US3 exist, and US4 changes *when* the work happens without changing *what* it produces.

---

## Notes

- `[P]` = different files, no incomplete dependencies.
- No new Mix dependencies and no new migrations (research.md, data-model.md).
- All OpenAI calls are stubbed in tests via the existing configured provider behaviour (no live API).
- Constitution musts: named OTP primitives (`Coordinator`, `Task.Supervisor` both carry `:name`); no `String.to_atom/1` on user input (candidate `kind`/`action` values are matched as literal strings); `chat_id` set on the struct, not in `cast/3`; no `Process.sleep/1`/`Process.alive?/1` in tests; `start_supervised!/1` for Coordinator/Task.Supervisor tests.
- Commit after each task or logical group; run `mix precommit` before committing.
