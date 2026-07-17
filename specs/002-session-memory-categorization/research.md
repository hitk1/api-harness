# Phase 0 Research: Categorized Session Memory

This document resolves the technical unknowns surfaced by the plan's Technical Context, and records the architecture decisions confirmed interactively with the user during `/speckit-specify` and `/speckit-plan`. Each section records **Decision**, **Rationale**, **Alternatives considered**.

---

## 1. Session memory categorization taxonomy

**Decision**: Reuse the same `kind` taxonomy already used by persistent memory — `goal | fact | constraint | preference` — as the category axis for session memory, applied per-thread instead of per-user. No new taxonomy is introduced.

**Rationale**: Explicit user direction (spec Clarifications, Q1). Keeps the two memory systems conceptually aligned — the same four labels already produced by `ApiHarness.Memory.Extractor.extract/1` for persistent memory apply directly to session memory, with no new extraction schema needed.

**Alternatives considered**: legal-case-specific categories (`case_facts`, `active_objective`, ...) — rejected, introduces a second, divergent taxonomy. AI-decided free-form categories — rejected, risks label drift and inconsistent retrieval.

---

## 2. Storage shape for categorized session memory

**Decision**: No new table or migration. The existing `session_memories.state` column (`:map` / jsonb, unchanged schema) now holds a categorized shape instead of the flat `last_question`/`last_answer` pair:

```elixir
%{
  "goal" => [%{"id" => "b3f1...", "content" => "Determinar prazo prescricional..."}],
  "fact" => [%{"id" => "9ac0...", "content" => "Cliente: João Silva"}],
  "constraint" => [%{"id" => "..." , "content" => "..."}],
  "preference" => []
}
```

Each entry carries a stable `"id"` (`Ecto.UUID.generate/0`) so later turns can target it for update/merge without needing a dedicated row per entry.

**Rationale**: `session_memories` already stores an untyped jsonb map (FR-014 always described it as "structured JSON" — the shape was never fixed by migration). Changing only the *shape* written into that column avoids a migration, keeps `ApiHarness.Memory.SessionMemory` schema/changeset unchanged, and keeps session memory lightweight (bounded to one thread's lifetime — no embedding index needed, unlike persistent memory which must search across a whole user's history).

**Alternatives considered**: A new `session_memory_entries` table (one row per category entry, mirroring `persistent_memories`) — rejected as unnecessary weight for data scoped to a single thread's jsonb blob; adds a migration and FK for no retrieval benefit at this scale. Storing entries as plain strings without an `"id"` — rejected, makes targeted update/merge (FR-003) ambiguous when a category has more than one entry.

---

## 3. Reconciliation of session-memory entries (no embeddings)

**Decision**: A new module, `ApiHarness.Memory.SessionReconciler`, reconciles each turn's extracted candidate against the *existing entries already stored in that same category* for the chat (i.e., `state[kind]`, a short, bounded list — not a pgvector nearest-neighbor search). For each candidate, an LLM call (structured output, same shape as the existing persistent-memory `Reconciler`) is given the full list of existing entries in that category plus the new candidate content, and returns `action` (`create | update | merge | discard`) and, for `update`/`merge`, the target entry `"id"` and resulting `content`.

**Rationale**: Session-memory categories are scoped to one thread and are small by construction (a handful of goals/facts/constraints/preferences per conversation) — a full list comparison in a single LLM call is simpler and cheaper than adding a second embedding index (pgvector) purely for ephemeral, thread-scoped data. This mirrors the *decision model* of the persistent-memory Reconciler (create/update/merge/discard, FR-019) exactly, per explicit user direction, while avoiding unnecessary infrastructure.

**Alternatives considered**: Reusing pgvector similarity search scoped by `chat_id` — rejected, requires adding an embedding column to session memory entries and an ANN index for data that rarely exceeds a few dozen short-lived entries; the added complexity is not justified. Simple last-write-wins per category — rejected in favor of full reconciliation per explicit user choice (spec Clarifications, Q2).

---

## 4. Extraction input for the session-memory pipeline

**Decision**: Reuse `ApiHarness.Memory.Extractor.extract/1` unchanged. The session-memory pipeline calls it with a synthetic turn payload combining both sides of the exchange (`"User: #{question}\nAssistant: #{answer}"`) rather than the assistant-only content used by the existing persistent-memory pipeline. This is a second, independent extraction call — it does not share results with the persistent-memory pipeline's own extraction call.

**Rationale**: `Extractor.extract/1` already produces exactly the `{category, kind, content, durable}` shape needed (`kind` doubles as the session-memory category, §1). The thread's *goal* is typically stated in the user's question, not restated in the assistant's answer — combining both sides of the turn is necessary for the `goal` category to be populated meaningfully (spec User Story 2, Acceptance Scenario 1). Unlike the existing persistent-memory pipeline, `durable` is **not** used as a discard filter here: information not durable enough to be useful in 30+ days (persistent-memory's bar, FR-016/FR-018) can still be exactly right for a single thread's lifetime — durability gates persistent memory, not session memory. `FR-008`'s discard criterion for session memory ("not meaningfully useful to retain") is judged by `SessionReconciler`'s own reconciliation call, not by the `durable` flag.

**Alternatives considered**: Sharing one extraction call's output between both pipelines — rejected; it would couple two independently-failing async flows together and complicate the "assistant-message-only" contract the existing persistent-memory tests already assert on. Extending `Extractor.extract/1`'s signature to accept question+answer explicitly — rejected as unnecessary; passing a combined string as the existing single `content` parameter requires no signature change.

---

## 5. Asynchronous execution architecture

**Decision**: A single, statically-supervised GenServer, `ApiHarness.Memory.SessionMemory.Coordinator`, added as a static child of `ApiHarness.Application` (alongside `Telemetry`, `Repo`, `PubSub`, `Endpoint` — **no `DynamicSupervisor`**). It is the one process responsible for all session-memory categorization/reconciliation demand, for every thread, for every user.

Producer side: after a response is generated (`ApiHarnessWeb.MessageController.dispatch_pipeline/3`, next to the existing persistent-memory dispatch), the controller publishes the turn via the application's existing `Phoenix.PubSub` process (`ApiHarness.PubSub`, already running in the supervision tree) to a topic (`"session_memory:updates"`) — a `Phoenix.PubSub.broadcast/3` call, not a blocking function call.

Consumer side: `Coordinator` subscribes to `"session_memory:updates"` once at `init/1`. Each broadcast arrives as a normal message (`handle_info/2`), is pushed onto an internal `:queue.queue()`, and dispatched to a bounded pool of concurrent jobs via a statically-supervised `Task.Supervisor` (`ApiHarness.Memory.SessionMemory.TaskSupervisor`, also a static `Application` child). The Coordinator tracks in-flight `chat_id`s: at most one job per `chat_id` runs at a time (preserving turn ordering and avoiding a read-modify-write race on the same `session_memories` row), while jobs for *different* `chat_id`s run fully concurrently up to a configured max (default 10). When a Task finishes (`handle_info({ref, result}, ...)` / `:DOWN`), the Coordinator dequeues the next pending job (if any) for that `chat_id`, or starts the next distinct `chat_id`'s job if the concurrency budget allows.

Each dispatched job runs: `Extractor.extract/1` (combined turn text, §4) → `SessionReconciler.reconcile/2` (§3) → `Memory.apply_session_reconciliation/2` (new function, mirrors `apply_reconciliation/2`, writes the categorized `state`). Failures retry up to 3 times with linear backoff (same policy as the existing persistent-memory pipeline), then are logged and discarded — never surfaced to the user (FR-007, mirrors FR-024-A).

**Rationale**: Matches the user's explicit, concrete direction: one dedicated long-lived process (not one spawned-and-torn-down worker per interaction, and not a `DynamicSupervisor`-started process) that can absorb concurrent demand from multiple users via a pub/sub-style, queued dispatch. `Phoenix.PubSub` is already a running, named process in this application's supervision tree (`ApiHarness.PubSub`) — reusing it for the producer→Coordinator handoff satisfies "a pub/sub-like system" with zero new dependencies (constitution Principle II: no new tooling introduced where an existing, prescribed mechanism suffices). Per-`chat_id` in-flight tracking is what actually delivers the spec's non-blocking-between-threads guarantee (US4 Acceptance Scenario 2) — concurrency happens *across* threads, never *within* one thread's own turn sequence, so no reconciliation write for a thread can race against another in-flight write for the same thread. `Task.Supervisor` isolates a crashing job from the Coordinator itself (one user's failure cannot take down the whole subsystem) exactly as `DynamicSupervisor` isolated the existing persistent-memory workers — the isolation property is preserved even though the top-level process is singular and long-lived.

**Alternatives considered**: One `DynamicSupervisor`-started long-lived GenServer per `chat_id` — this was the initial design proposal, but the user explicitly redirected to a single global process instead (plan clarification, Q1/Q2). A single GenServer processing jobs strictly serially in its own `handle_cast`/`handle_info` (no Task offload) — rejected, a slow LLM call for one thread would head-of-line-block every other thread's update, violating the non-blocking-between-threads requirement. `Task.Supervisor.async_stream/3` over a fixed collection — not applicable; work arrives incrementally over time from an open-ended stream of HTTP requests, not a bounded enumerable collection, so a queue + on-demand dispatch fits better than a stream primitive.

---

## 6. Interaction with the existing persistent-memory pipeline

**Decision**: The existing persistent-memory pipeline (`ApiHarness.Memory.Pipeline.{Supervisor,Registry,Worker}`, `Extractor`, `Reconciler`) is left entirely unchanged by this feature. The new session-memory pipeline runs alongside it as an independent subscriber/consumer of its own PubSub topic, with its own extraction call, its own reconciler, and its own failure/retry handling.

**Rationale**: Minimizes regression risk on an already-shipped, already-tested system (US4/US5 of the legal AI agent harness feature). The user separately indicated an intent to migrate persistent memory's pipeline to the same "single dedicated process" pattern in the future — that migration is explicitly out of scope for this feature and is left as a natural follow-up once this pattern is proven here.

**Alternatives considered**: Unifying both pipelines under one Coordinator now — rejected as out of scope; the user's clarification framed this as a separate, later step ("vou refatorar a memória persistente futuramente para ser feito dessa forma também").

---

## Summary of new dependencies

None. This feature adds no new Mix dependencies — it reuses `Phoenix.PubSub` (already running), `Task.Supervisor` (OTP standard library), and the existing `ApiHarness.LLM.Provider` / structured-output pattern already used by `Extractor` and `Reconciler`. No new database tables or migrations are introduced (§2).
