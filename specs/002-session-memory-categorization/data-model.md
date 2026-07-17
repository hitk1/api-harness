# Phase 1 Data Model: Categorized Session Memory

Derived from the Key Entities and Functional Requirements in [spec.md](./spec.md), refined by the decisions in [research.md](./research.md). **No migrations are introduced by this feature** — the existing `session_memories` table and `ApiHarness.Memory.SessionMemory` schema are reused unchanged; only the *shape* of data written into the existing `state` jsonb column changes.

> Convention reminders (constitution): schema fields use `:string` even for `:text` columns; programmatically-set foreign keys are set on the struct, **not** in `cast/3`; OTP primitives with a `:name` are used for the new static processes.

---

## Entity: Session Memory (revised)

Unchanged schema (`lib/api_harness/memory/session_memory.ex`), reused as-is:

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | unchanged |
| chat_id | bigint FK → chats | unchanged, **unique** (one per thread) |
| state | map (jsonb) | **shape changes** — see below; defaults to `%{}` |
| inserted_at / updated_at | utc_datetime | unchanged |

**Revised `state` shape** (conceptual — not a new Ecto schema, just the convention this feature writes/reads):

```elixir
%{
  "goal"       => [%{"id" => uuid_string, "content" => string}, ...],
  "fact"       => [%{"id" => uuid_string, "content" => string}, ...],
  "constraint" => [%{"id" => uuid_string, "content" => string}, ...],
  "preference" => [%{"id" => uuid_string, "content" => string}, ...]
}
```

- Keys are exactly the four categories from FR-002 (`goal | fact | constraint | preference`); a category with no entries yet is either absent or an empty list.
- Each entry's `"id"` (`Ecto.UUID.generate/0`) is assigned once, at creation, and is stable across later `update`/`merge` reconciliation actions targeting that entry (research.md §2–3).
- Superseded shape (pre-refactor): `%{"last_question" => string, "last_answer" => string}` — no longer written by this feature; any pre-existing rows in that shape are simply overwritten by the first turn processed after this feature ships (no backfill; see Assumptions in spec.md).

**Relationships**: unchanged — `belongs_to :chat`.

**Lifecycle**: unchanged creation timing (inserted empty on chat creation, per existing `Chats.create_chat/2`). Updated in place per turn by the new session-memory pipeline (research.md §5) instead of being merged with two fixed keys.

**Indexes**: unchanged — unique index on `chat_id`.

---

## Conceptual entity: Turn Extraction Candidate

Not a persisted table — the in-memory shape produced by `ApiHarness.Memory.Extractor.extract/1` (unchanged module) when called with a turn's combined question+answer text (research.md §4):

| Field | Type | Notes |
|-------|------|-------|
| category | string | `"user"` \| `"task"` \| `"domain"` — persistent-memory axis, ignored by the session pipeline |
| kind | string | `"preference"` \| `"goal"` \| `"constraint"` \| `"fact"` — **this is the session-memory category** (FR-002) |
| content | string | the extracted knowledge statement |
| durable | boolean | persistent-memory discard signal only; **not** used to discard for session memory (research.md §4) |

## Conceptual entity: Session Reconciliation Decision

Produced by the new `ApiHarness.Memory.SessionReconciler` for each candidate, consumed by a new `ApiHarness.Memory.apply_session_reconciliation/2` (mirrors the existing `apply_reconciliation/2` for persistent memory):

| Field | Type | Notes |
|-------|------|-------|
| action | string | `"create"` \| `"update"` \| `"merge"` \| `"discard"` (FR-003, FR-008) |
| kind | string | which category of `state` this decision applies to |
| id | string (uuid) | target entry id — present only for `update`/`merge` |
| content | string | resulting entry content — absent for `discard` |

**State transitions** (mirrors persistent memory's model, FR-017 analog): `create` (append a new `%{"id" => new_uuid, "content" => content}` to `state[kind]`) · `update` (replace the `content` of the entry matching `id` in `state[kind]`) · `merge` (fold the candidate into the entry matching `id`, replacing its `content` with the merged text) · `discard` (no change to `state`). No blind overwrite of the whole `state` map — only the targeted category/entry is touched.

## Conceptual entity: Session Memory Turn Event (PubSub payload)

Not persisted — the message published by `ApiHarnessWeb.MessageController.dispatch_pipeline/3` to the `"session_memory:updates"` topic and received by `ApiHarness.Memory.SessionMemory.Coordinator` (research.md §5):

| Field | Type | Notes |
|-------|------|-------|
| chat_id | integer | identifies the thread whose session memory is updated; also used for in-flight/ordering tracking |
| user_id | integer | carried through for consistency with the persistent-memory interaction payload; not required for session-memory reconciliation itself |
| question | string | the user's message for this turn |
| answer | string | the assistant's response for this turn |

---

## Relationship diagram (textual, delta from 001)

```text
Chat 1──1 SessionMemory                 (unchanged relationship)
Chat --(pubsub: chat_id, question, answer)--> SessionMemory.Coordinator (new, process not a DB relationship)
SessionMemory.Coordinator --(per chat_id, sequential)--> Task.Supervisor jobs --> SessionMemory.state (targeted category/entry update)
```

No FK, table, or column is added or removed. `PersistentMemory`, `MemoryContextUpdate`, and `FileMetadata` entities from `specs/001-legal-ai-agent-harness/data-model.md` are unaffected.

## Migration order

None — no migrations for this feature.
