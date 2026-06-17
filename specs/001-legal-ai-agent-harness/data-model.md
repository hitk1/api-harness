# Phase 1 Data Model: Legal AI Agent Harness

Derived from the Key Entities and Functional Requirements in [spec.md](./spec.md). All tables live in PostgreSQL via Ecto. Timestamps are `:utc_datetime` (project default). Primary keys are `bigserial` unless noted. The `vector` type requires the pgvector extension (enabled in its own migration).

> Convention reminders (constitution): schema fields use `:string` even for `:text` columns; programmatically-set foreign keys (`user_id`, `chat_id`) are set on the struct, **not** in `cast/3`; associations are preloaded when serialized.

---

## Entity: User

Represents a system operator / end user. Created via the REPL (FR-001) and authenticated via JWT (FR-000).

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | |
| name | string | required |
| email | string | required, **unique** (FR-003), citext or downcased + unique index |
| hashed_password | string | bcrypt hash; never expose in JSON |
| token_version | integer | default `0`; bumped to revoke all JWTs (research §1) |
| inserted_at / updated_at | utc_datetime | |

**Relationships**: has_many chats; has_many persistent_memories; has_many file_metadata.

**Validations**: name present; email present + valid format + unique; password (virtual) min length on create → hashed. `validate_number` not used here.

**Indexes**: unique index on `lower(email)` (or citext unique).

---

## Entity: Chat (Thread)

A conversation thread owned by a user (FR-004, FR-006). Each thread has exactly one session memory.

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | |
| user_id | bigint FK → users | required, set on struct |
| title | string | optional; may be auto-derived from first message |
| inserted_at / updated_at | utc_datetime | |

**Relationships**: belongs_to user; has_many messages (ordered by inserted_at); has_one session_memory.

**Validations**: user_id present (association required).

**Indexes**: index on `user_id`.

---

## Entity: Message

A single conversational turn — user or assistant (FR-013). Persisted for both the user message and the AI response.

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | |
| chat_id | bigint FK → chats | required, set on struct |
| role | string | `"user"` or `"assistant"` (enum-validated, not `String.to_atom` on input) |
| content | string | `:text` column, `:string` field type |
| inserted_at / updated_at | utc_datetime | timestamp ordering = conversation order |

**Relationships**: belongs_to chat.

**Validations**: role in `["user", "assistant"]`; content present (non-empty — rejects empty/malformed message edge case → 400); chat_id present.

**Indexes**: index on `chat_id`; composite index `(chat_id, inserted_at)` for windowed recent-message retrieval.

---

## Entity: Session Memory

Structured JSON capturing current task state for **one** thread (FR-014, FR-015). Re-initialized per thread; never shared across threads.

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | |
| chat_id | bigint FK → chats | required, **unique** (one per thread) |
| state | map (`:map` / jsonb) | structured insights/facts/notes JSON; defaults to `%{}` |
| inserted_at / updated_at | utc_datetime | |

**Relationships**: belongs_to chat.

**Lifecycle**: created when a thread is created (or lazily on first message); updated in place by the memory pipeline; not carried to other threads.

**Indexes**: unique index on `chat_id`.

---

## Entity: Persistent Memory

Durable, per-user knowledge managed by reconciliation — **not** append-only (FR-016, FR-017). Carries an embedding for relevance retrieval (research §5).

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | |
| user_id | bigint FK → users | required, set on struct |
| category | string | `"user"` \| `"task"` \| `"domain"` (the three categories, FR-016) |
| kind | string | `"preference"` \| `"goal"` \| `"constraint"` \| `"fact"` (extraction types, FR-018) |
| content | string | `:text`; the knowledge statement |
| metadata | map (jsonb) | optional structured attributes |
| embedding | vector(1536) | `text-embedding-3-small`; for cosine-similarity retrieval |
| inserted_at / updated_at | utc_datetime | `updated_at` reflects last reconciliation |

**Relationships**: belongs_to user; has_many memory_context_updates (audit trail).

**Validations**: category in the three allowed values; kind in the four allowed values; content present; user_id present.

**State transitions** (via Reconciler, FR-019): `create` (new row) · `update` (replace content/embedding in place) · `merge` (fold candidate into existing row, update content/embedding) · `discard` (no row written). No blind append.

**Indexes**: index on `(user_id, category)`; pgvector index (ivfflat/hnsw) on `embedding` for ANN search, scoped by user at query time.

---

## Entity: Memory Context Update

Audit record of every memory state change produced by reconciliation (FR-021). Enables reconstructing memory evolution.

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | |
| user_id | bigint FK → users | required |
| persistent_memory_id | bigint FK → persistent_memories | nullable (null for `discard`) |
| chat_id | bigint FK → chats | source interaction thread (nullable) |
| action | string | `"create"` \| `"update"` \| `"merge"` \| `"discard"` |
| before | map (jsonb) | prior content snapshot (null on create) |
| after | map (jsonb) | new content snapshot (null on discard) |
| inserted_at | utc_datetime | append-only audit log (this table *is* a log, intentionally) |

**Relationships**: belongs_to user; belongs_to persistent_memory (optional); belongs_to chat (optional).

**Indexes**: index on `user_id`; index on `persistent_memory_id`.

---

## Entity: File Metadata *(placeholder)*

Structural placeholder for user-uploaded document metadata (FR-027). Upload/ingestion are out of scope — the table exists for modeling completeness only.

| Field | Type | Notes |
|-------|------|-------|
| id | bigserial PK | |
| user_id | bigint FK → users | required |
| filename | string | |
| content_type | string | optional |
| byte_size | integer | optional |
| metadata | map (jsonb) | arbitrary fictional metadata |
| inserted_at / updated_at | utc_datetime | |

**Relationships**: belongs_to user.

**Note**: No file storage, parsing, or ingestion logic is implemented.

---

## Relationship Diagram (textual)

```text
User 1──* Chat 1──* Message
User 1──* PersistentMemory 1──* MemoryContextUpdate
User 1──* FileMetadata
Chat 1──1 SessionMemory
Chat 1──* MemoryContextUpdate   (source thread, optional)
```

## Migration order

1. Enable pgvector extension (`CREATE EXTENSION IF NOT EXISTS vector`).
2. users
3. chats (FK → users)
4. messages (FK → chats)
5. session_memories (FK → chats, unique chat_id)
6. persistent_memories (FK → users, vector column + ANN index)
7. memory_context_updates (FKs → users, persistent_memories, chats)
8. file_metadata (FK → users)

All migrations generated with `mix ecto.gen.migration <name_with_underscores>` (constitution).
