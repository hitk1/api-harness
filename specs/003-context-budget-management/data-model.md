# Phase 1 Data Model: Context Budget Management

Derived from the Key Entities and Functional Requirements in [spec.md](./spec.md), refined by the decisions in [research.md](./research.md).

> Convention reminders (constitution): schema fields use `:string` even for `:text` columns; programmatically-set foreign keys are set on the struct, **not** in `cast/3`; OTP primitives with a `:name` are declared in the supervision tree.

---

## Modified Entity: Message

Schema: `lib/api_harness/chats/message.ex` — **MODIFIED**

| Field | Type | Change | Notes |
|-------|------|--------|-------|
| id | bigserial PK | unchanged | |
| chat_id | bigint FK → chats | unchanged | |
| role | `:string` | unchanged | `"user"` \| `"assistant"` |
| content | `:string` (`:text`) | unchanged | |
| **token_count** | `:integer` | **NEW** | Pre-computed at persistence time via `TokenCounter`. Default: `0`. `0` means "not yet counted" — context runtime falls back to live counting for legacy rows. |
| inserted_at / updated_at | utc_datetime | unchanged | |

**Changeset change**: `token_count` is a system-set field — it MUST NOT appear in `cast/3`. It is set explicitly on the struct before insertion, similar to how `user_id` is handled in persistent memories.

**Backfill**: Existing rows keep `token_count = 0` until the one-time mix task `mix api_harness.backfill_token_counts` runs.

---

## Modified Entity: Persistent Memory

Schema: `lib/api_harness/memory/persistent_memory.ex` — **MODIFIED**

| Field | Type | Change | Notes |
|-------|------|--------|-------|
| id | bigserial PK | unchanged | |
| user_id | bigint FK → users | unchanged | |
| category | `:string` | unchanged | `"user"` \| `"task"` \| `"domain"` |
| kind | `:string` | unchanged | `"preference"` \| `"goal"` \| `"constraint"` \| `"fact"` |
| content | `:string` (`:text`) | unchanged | |
| metadata | map (jsonb) | unchanged | |
| embedding | vector(1536) | unchanged | |
| **token_count** | `:integer` | **NEW** | Pre-computed from `content` at persistence time. Updated whenever `content` changes. Default: `0`. |
| inserted_at / updated_at | utc_datetime | unchanged | |

**Changeset change**: `token_count` is system-set, not user-supplied — must not be in `cast/3`. Updated by `Memory.apply_reconciliation/2` on create/update/merge.

---

## Modified Entity: Chat

Schema: `lib/api_harness/chats/chat.ex` — **MODIFIED**

| Field | Type | Change | Notes |
|-------|------|--------|-------|
| id | bigserial PK | unchanged | |
| user_id | bigint FK → users | unchanged | |
| title | `:string` | unchanged | |
| **context_status** | `:string` | **NEW** | State machine field. Values: `"active"` \| `"needs_compaction"` \| `"compacting"` \| `"ready"`. Default: `"active"`. |
| **rolling_summary** | `:string` (`:text`) | **NEW** | Nullable. Populated after first successful compaction. The LLM-generated structured summary of all messages up to the last compaction checkpoint. |
| **rolling_summary_token_count** | `:integer` | **NEW** | Pre-computed token count of `rolling_summary`. Default: `0`. |
| **total_context_tokens** | `:integer` | **NEW** | Last-known total prompt token count from the most recent interaction. Updated post-response by the async analysis step. Default: `0`. |
| **compaction_count** | `:integer` | **NEW** | Number of times compaction has completed for this thread. Default: `0`. |
| **last_compaction_at** | `:utc_datetime` | **NEW** | Nullable. Timestamp of the last successful compaction. |
| inserted_at / updated_at | utc_datetime | unchanged | |

**Context status state machine**:
```
active → needs_compaction → compacting → ready → (back to active on next interaction)
                              ↑
                    On worker failure after exhausting retries:
                    reverts to needs_compaction (not active)
```

On application startup, `Compaction.Bootstrap.enqueue_pending/0` queries:
```sql
SELECT id FROM chats WHERE context_status IN ('needs_compaction', 'compacting')
```
and re-enqueues each for compaction.

**Changeset**: `context_status`, `rolling_summary`, `rolling_summary_token_count`, `total_context_tokens`, `compaction_count`, `last_compaction_at` are all system-set fields — none appear in `cast/3`. Updated via `Chats.update_context_metrics/2` and `Chats.update_context_status/2` context functions.

---

## Conceptual Entity: Budget Allocation

Not persisted — an in-memory map produced by `ApiHarness.Agent.BudgetManager.allocate/2` for each interaction. Consumed by `ContextRuntime` to pass budgets to providers.

| Field | Type | Notes |
|-------|------|-------|
| system | integer | Token allocation for `SystemPromptProvider` |
| domain | integer | Token allocation for `DomainMemoryProvider` |
| session | integer | Token allocation for `SessionMemoryProvider` |
| memory | integer | Token allocation for `PersistentMemoryProvider` |
| conversation | integer | Token allocation for `ConversationProvider` (rolling_summary + recent messages) |
| question | integer | Token allocation for `UserQuestionProvider` (always = actual question token count) |
| total | integer | Sum of all allocations; guaranteed ≤ available_budget |
| available_budget | integer | context_window - output_reserve - safety_headroom |

**No struct or schema** — represented as a plain Elixir map `%{system: N, domain: N, ...}`.

---

## Conceptual Entity: Context Metrics (API Response)

Not persisted — assembled by `ContextRuntime.build/3` and returned alongside the prompt assembly result. Passed to the controller and included in the JSON response.

| Field | Type | Notes |
|-------|------|-------|
| total_tokens | integer | Actual tokens used in the assembled prompt |
| available_budget | integer | Maximum usable tokens (window - output_reserve) |
| utilization_percentage | float | `total_tokens / available_budget` (0.0–1.0) |
| context_status | string | Current chat's `context_status` field value |
| layers | map | Per-provider token counts (`system`, `domain_memory`, `session_memory`, `persistent_memory`, `conversation`, `question`) |

---

## Conceptual Entity: Compaction Job

Not persisted — the state held by a `Context.Compaction.Worker` GenServer while processing.

| Field | Notes |
|-------|-------|
| chat_id | The chat being compacted |
| user_id | Owner (for LLM call auth if needed) |
| attempt | Current retry attempt (1–3) |
| messages | Loaded from DB at start of processing |
| existing_summary | Previous `rolling_summary` value (nil for first compaction) |

---

## Migrations

Three migrations are required. Use `mix ecto.gen.migration <name_with_underscores>` for each:

### Migration 1: add_token_count_to_messages

```elixir
alter table(:messages) do
  add :token_count, :integer, default: 0, null: false
end
```

### Migration 2: add_token_count_to_persistent_memories

```elixir
alter table(:persistent_memories) do
  add :token_count, :integer, default: 0, null: false
end
```

### Migration 3: add_context_management_to_chats

```elixir
alter table(:chats) do
  add :context_status, :string, default: "active", null: false
  add :rolling_summary, :text
  add :rolling_summary_token_count, :integer, default: 0, null: false
  add :total_context_tokens, :integer, default: 0, null: false
  add :compaction_count, :integer, default: 0, null: false
  add :last_compaction_at, :utc_datetime
end

create index(:chats, [:context_status],
  where: "context_status IN ('needs_compaction', 'compacting')",
  name: :chats_pending_compaction_index
)
```

The partial index on `context_status` accelerates the startup bootstrap query and admin monitoring queries.

---

## Relationship Diagram (delta from specs 001 + 002)

```text
Chat 1──1 SessionMemory                       (unchanged, spec 001)
Chat 1──* Message                             (unchanged, spec 001)
  └── Message.token_count                     (NEW: pre-computed by TokenCounter)
Chat.context_status                           (NEW: state machine)
Chat.rolling_summary                          (NEW: compaction output)
Chat.total_context_tokens                     (NEW: session metric)

User 1──* PersistentMemory                    (unchanged, spec 001)
  └── PersistentMemory.token_count            (NEW: pre-computed by TokenCounter)

Context.Compaction.Worker → Chat              (process-to-row update, no FK)
Context.Compaction.Registry[chat_id]          (process registry key, no DB relationship)
```

No existing FK, table, or index is dropped. `SessionMemory`, `MemoryContextUpdate`, and `FileMetadata` entities from specs 001 + 002 are unaffected.
