---
description: "Task list for Legal AI Agent Harness implementation"
---

# Tasks: Legal AI Agent Harness

**Input**: Design documents from `/specs/001-legal-ai-agent-harness/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included. The constitution's Test Discipline principle (V) is MUST-level and the spec defines acceptance scenarios + measurable success criteria; each story therefore gets ExUnit context/controller tests. OpenAI is always stubbed in tests (no live calls).

**Organization**: Tasks are grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1–US5)
- All paths are relative to the repository root

## Path Conventions

Single Phoenix project: domain under `lib/api_harness/`, web under `lib/api_harness_web/`, tests under `test/`. Migrations via `mix ecto.gen.migration <name>` into `priv/repo/migrations/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add dependencies and runtime configuration.

- [X] T001 Add `joken ~> 2.6`, `bcrypt_elixir ~> 3.1`, `dotenvy ~> 0.9`, `pgvector ~> 0.3` to `deps/0` in `mix.exs`
- [X] T002 Run `mix deps.get` and confirm clean compile with `mix compile --warnings-as-errors`
- [X] T003 [P] Load `.env` via `Dotenvy` at the top of `config/runtime.exs`; create `.env.example` (DATABASE_URL, OPENAI_API_KEY, JWT_SECRET, SECRET_KEY_BASE) and add `.env` to `.gitignore`
- [X] T004 [P] Add OpenAI + JWT config in `config/config.exs` and `config/runtime.exs` (model `gpt-4o-mini`, embeddings `text-embedding-3-small`, base URL, `:openai_api_key`, `:jwt_secret`, configurable `:recent_messages_window` default 10, configurable LLM provider module for test injection)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Base entity, auth framework, LLM provider, and error handling that ALL user stories depend on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T005 Generate migration enabling pgvector (`mix ecto.gen.migration enable_pgvector`) with `CREATE EXTENSION IF NOT EXISTS vector` in `priv/repo/migrations/`
- [X] T006 [P] Create User schema in `lib/api_harness/accounts/user.ex` (name, email, hashed_password, token_version) + migration `create_users` with unique index on `lower(email)`; programmatic fields excluded from `cast/3`
- [X] T007 [P] Define LLM provider behaviour in `lib/api_harness/llm/provider.ex` (`chat_completion/2`, `embed/2`)
- [X] T008 Implement Req-based OpenAI client in `lib/api_harness/llm/openai.ex` (chat completions with structured outputs + embeddings); resolve provider module from config for injection
- [X] T009 [P] Add LLM test stub in `test/support/llm_stub.ex` implementing the provider behaviour with canned responses
- [X] T010 [P] Implement JWT token module in `lib/api_harness/accounts/token.ex` using Joken (no `exp`, claims `sub` + `token_version`); `generate/1` and `verify/1`
- [X] T011 Implement authentication plug in `lib/api_harness_web/plugs/authenticate.ex` (parse Bearer token, verify, check `token_version`, assign `conn.assigns.current_user`; 401 on failure)
- [X] T012 Add authenticated `:api_auth` pipeline and protected scope in `lib/api_harness_web/router.ex`
- [X] T013 [P] Add `FallbackController` + extend `ErrorJSON` in `lib/api_harness_web/controllers/` to render 400/401/404/422/502/503 as `{"errors": {"detail": ...}}`

**Checkpoint**: Foundation ready — user story implementation can begin.

---

## Phase 3: User Story 1 - User Registration and Management (Priority: P1) 🎯 MVP

**Goal**: Create/manage users from the Elixir REPL and authenticate via JWT login.

**Independent Test**: In IEx, create/list/update/delete a user and confirm persistence; duplicate email errors; `POST /api/login` returns a token (quickstart Scenarios 1–2).

### Tests for User Story 1

- [X] T014 [P] [US1] Accounts context test in `test/api_harness/accounts_test.exs` (create/list/update/delete, bcrypt hashing, duplicate-email rejection, password verification) using `DataCase`
- [X] T015 [P] [US1] Login controller test in `test/api_harness_web/controllers/auth_controller_test.exs` (200 + token, 400 missing fields, 401 bad credentials) using `ConnCase`

### Implementation for User Story 1

- [X] T016 [US1] Implement Accounts context in `lib/api_harness/accounts/accounts.ex`: `create_user/1` (bcrypt hash, unique email), `list_users/0`, `get_user/1`, `update_user/2`, `delete_user/1`, `verify_password/2` with constant-time `no_user_verify`
- [X] T017 [US1] Implement `AuthController` `POST /api/login` in `lib/api_harness_web/controllers/auth_controller.ex` + `auth_json.ex` (verify credentials, issue JWT via T010, return token + user per contracts/auth.md)
- [X] T018 [US1] Add public route `POST /api/login` in `lib/api_harness_web/router.ex` (outside `:api_auth`)
- [X] T019 [US1] Validate REPL user CRUD per quickstart Scenario 1 (manual smoke check — requires live DB)

**Checkpoint**: Users manageable from REPL; login issues working JWTs (SC-007).

---

## Phase 4: User Story 2 - Chat Session Management (Priority: P2)

**Goal**: Authenticated users create, list, and open chat threads; each new thread gets a fresh session memory.

**Independent Test**: Create a thread via `POST /api/chats`, list it, confirm a `session_memories` row exists and is scoped to the thread (quickstart Scenario 3).

**Depends on**: Foundational (auth, User). Threads are a prerequisite for US3.

### Tests for User Story 2

- [X] T020 [P] [US2] Chats context test in `test/api_harness/chats_test.exs` (create initializes session memory, list scoped to user, get preloads messages) using `DataCase`
- [X] T021 [P] [US2] Chat controller test in `test/api_harness_web/controllers/chat_controller_test.exs` (201 create, 200 list, 404 foreign thread, 401 unauthenticated) using `ConnCase`

### Implementation for User Story 2

- [X] T022 [P] [US2] Create Chat schema in `lib/api_harness/chats/chat.ex` (user_id, title) + migration `create_chats` (index on user_id)
- [X] T023 [P] [US2] Create SessionMemory schema in `lib/api_harness/memory/session_memory.ex` (chat_id, state map default `%{}`) + migration `create_session_memories` (unique chat_id)
- [X] T024 [US2] Implement Chats context in `lib/api_harness/chats/chats.ex`: `create_chat/2` (sets user_id on struct, initializes session memory), `list_chats/1` (scoped to user), `get_chat/2` (ownership-checked, preload messages ordered by inserted_at)
- [X] T025 [US2] Implement `ChatController` (`POST`/`GET /api/chats`, `GET /api/chats/:id`) in `lib/api_harness_web/controllers/chat_controller.ex` + `chat_json.ex` per contracts/chats.md (404 on missing/foreign)
- [X] T026 [US2] Add chat routes under the `:api_auth` scope in `lib/api_harness_web/router.ex`

**Checkpoint**: Threads create/list/open with isolated session memory (SC-008).

---

## Phase 5: User Story 3 - AI-Powered Legal Chat (Priority: P1)

**Goal**: Send a message to a thread and receive a synchronous AI response driven by the Agent Runtime; persist both messages.

**Independent Test**: `POST /api/chats/:id/messages` returns an assistant message; both messages persist; empty content → 400, foreign thread → 404, OpenAI outage → 502/503 (quickstart Scenario 4).

**Depends on**: Foundational + US1 (auth) + US2 (threads + session memory).

### Tests for User Story 3

- [X] T027 [P] [US3] Message controller test in `test/api_harness_web/controllers/message_controller_test.exs` (200 with assistant message, 400 empty content, 404 foreign thread, 502 on stubbed OpenAI error) using `ConnCase` + LLM stub
- [X] T028 [P] [US3] Agent runtime + planner test in `test/api_harness/agent/runtime_test.exs` (planner always runs; single-step and multi-step plans; fail-total coordinator) using LLM stub
- [X] T029 [P] [US3] Context builder test in `test/api_harness/agent/context_builder_test.exs` (six layers in correct order)

### Implementation for User Story 3

- [X] T030 [P] [US3] Create Message schema in `lib/api_harness/chats/message.ex` (chat_id, role in `["user","assistant"]`, content `:text`) + migration `create_messages` (composite index `(chat_id, inserted_at)`)
- [X] T031 [P] [US3] Add `add_message/3` and `list_recent_messages/2` (windowed) to `lib/api_harness/chats/chats.ex`
- [X] T032 [P] [US3] Implement Tool Registry in `lib/api_harness/agent/tools/registry.ex` + stub tool modules in `lib/api_harness/agent/tools/` (read_document, search_entities, generate_report — stubs)
- [X] T033 [US3] Implement `ContextBuilder` in `lib/api_harness/agent/context_builder.ex` assembling the six layers (system instruction + legal domain context, session memory, persistent memory placeholder for now, recent messages window, current question) per FR-022
- [X] T034 [US3] Implement `Planner` in `lib/api_harness/agent/planner.ex` (always runs; emits single- or multi-step structured plan via OpenAI structured outputs; 422 mapping when no valid plan)
- [X] T035 [US3] Implement `Coordinator` in `lib/api_harness/agent/coordinator.ex` using `Task.async_stream/3` (`timeout: :infinity`); fail-total on any worker error (FR-011)
- [X] T036 [US3] Implement `Executor` in `lib/api_harness/agent/executor.ex` (runs plan steps, dispatching parallelizable steps through the Coordinator and actions through the Tool Registry)
- [X] T037 [US3] Implement Agent `Runtime` in `lib/api_harness/agent/runtime.ex` (persist user message → build context → plan → execute → persist assistant message → return response)
- [X] T038 [US3] Implement `MessageController` `POST /api/chats/:chat_id/messages` (synchronous) in `lib/api_harness_web/controllers/message_controller.ex` + `message_json.ex` per contracts/messages.md
- [X] T039 [US3] Add message route under `:api_auth` in `lib/api_harness_web/router.ex`
- [X] T040 [US3] Map OpenAI errors to fail-fast 502/503 (no retry, no fallback) in the runtime/controller path (FR-013-A)

**Checkpoint**: Core synchronous AI chat works end-to-end (SC-001).

---

## Phase 6: User Story 4 - Intelligent Memory System (Priority: P2)

**Goal**: Extract structured knowledge, retrieve relevant memory by similarity, and reconcile persistent memory (create/update/merge/discard) without append-only growth.

**Independent Test**: After interactions, session memory reflects extracted facts; restating known knowledge does not grow persistent-memory row count; retrieval returns only relevant memories (quickstart Scenario 5).

**Depends on**: US3 (interactions to extract from) + Foundational (LLM, pgvector).

### Tests for User Story 4

- [X] T041 [P] [US4] Reconciler test in `test/api_harness/memory/reconciler_test.exs` (create vs update vs merge vs discard; non-durable discarded; audit row written; row count stable on overlap → SC-005)
- [X] T042 [P] [US4] Retriever test in `test/api_harness/memory/retriever_test.exs` (relevance-scoped top-K, category filter excludes unrelated → SC-006) using LLM stub embeddings
- [X] T043 [P] [US4] Extractor test in `test/api_harness/memory/extractor_test.exs` (structured JSON: preferences/goals/constraints/facts)

### Implementation for User Story 4

- [X] T044 [P] [US4] Create PersistentMemory schema in `lib/api_harness/memory/persistent_memory.ex` (user_id, category, kind, content `:text`, metadata, `embedding vector(1536)`) + migration `create_persistent_memories` (index `(user_id, category)` + pgvector ANN index)
- [X] T045 [P] [US4] Create MemoryContextUpdate schema in `lib/api_harness/memory/memory_context_update.ex` (user_id, persistent_memory_id?, chat_id?, action, before, after) + migration `create_memory_context_updates`
- [X] T046 [US4] Implement Knowledge `Extractor` in `lib/api_harness/memory/extractor.ex` (LLM structured output → typed candidates)
- [X] T047 [US4] Implement `Retriever` in `lib/api_harness/memory/retriever.ex` (embed task context, pgvector cosine top-K scoped by user + optional category filter)
- [X] T048 [US4] Implement `Reconciler` in `lib/api_harness/memory/reconciler.ex` (per candidate: nearest existing → LLM decides create/update/merge/discard incl. ≥30-day durability; write audit row; never blind-append → FR-017)
- [X] T049 [US4] Implement Memory context API in `lib/api_harness/memory/memory.ex` (`get_session_memory/1`, `update_session_memory/2`, `list_persistent_memories/1`, `apply_reconciliation/2`)
- [X] T050 [US4] Wire `Retriever` into `ContextBuilder` layer 4 (replace the placeholder from T033) so relevant persistent memory feeds the prompt
- [X] T051 [US4] Update session-memory `state` from each interaction's extracted facts (FR-014)

**Checkpoint**: Memory behaves as managed knowledge, retrieved by relevance (SC-004/005/006).

---

## Phase 7: User Story 5 - Asynchronous Memory Update Pipeline (Priority: P3)

**Goal**: Run extraction → classification → reconciliation → persistence off the request path via supervised GenServer workers, one per interaction, scalable and non-blocking.

**Independent Test**: Response returns before memory writes; memory appears shortly after; concurrent users each get an independent worker with no blocking/loss (quickstart Scenarios 5–6).

**Depends on**: US4 (the stages the pipeline runs).

### Tests for User Story 5

- [X] T052 [P] [US5] Pipeline worker test in `test/api_harness/memory/pipeline/worker_test.exs` (stages run in order; retries then log+discard on stage failure) using `start_supervised!/1` + `Process.monitor` + `assert_receive` (no `Process.sleep`)
- [X] T053 [P] [US5] Concurrency test in `test/api_harness/memory/pipeline/concurrency_test.exs` (N interactions → N independent workers, no lost updates → SC-003)

### Implementation for User Story 5

- [X] T054 [P] [US5] Implement named `Registry` for in-flight jobs in `lib/api_harness/memory/pipeline/registry.ex`
- [X] T055 [P] [US5] Implement named `DynamicSupervisor` in `lib/api_harness/memory/pipeline/supervisor.ex`
- [X] T056 [US5] Implement pipeline `Worker` GenServer in `lib/api_harness/memory/pipeline/worker.ex` (extraction→classification→reconciliation→persistence; 2–3 retries with backoff, then log & discard; failure never surfaces → FR-024-A)
- [X] T057 [US5] Add the pipeline Registry + DynamicSupervisor to the supervision tree in `lib/api_harness/application.ex`
- [X] T058 [US5] Dispatch the pipeline from the Agent `Runtime` after the response is returned (fire-and-forget; must not block the response → FR-023/SC-002)

**Checkpoint**: Memory updates run fully asynchronously under concurrency.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Placeholder entity, seeds, and validation gates.

- [X] T059 [P] Create FileMetadata placeholder schema in `lib/api_harness/files/file_metadata.ex` (user_id, filename, content_type, byte_size, metadata) + migration `create_file_metadata` (FR-027; no ingestion logic)
- [X] T060 [P] Add example seed data in `priv/repo/seeds.exs` (`import Ecto.Query`; sample user)
- [X] T061 [P] Document required env keys in `.env.example` and update `README.md` setup notes
- [X] T062 Run all quickstart.md validation scenarios end-to-end (requires live Postgres + pgvector)
- [X] T063 Run `mix precommit` (requires live Postgres for test suite)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **US1 (Phase 3)**: Depends on Foundational. MVP.
- **US2 (Phase 4)**: Depends on Foundational (+ US1 auth in practice).
- **US3 (Phase 5)**: Depends on US1 (auth) + US2 (threads/session memory).
- **US4 (Phase 6)**: Depends on US3 (interactions) + Foundational (LLM/pgvector).
- **US5 (Phase 7)**: Depends on US4 (stages it orchestrates).
- **Polish (Phase 8)**: Depends on desired stories being complete.

### Story Priority vs. Dependency Note

US1 and US3 are both P1; US3 is the core value but cannot function without US2 (P2) threads, so US2 is sequenced before US3. US2 before US3 is a hard data dependency (messages belong to a chat), documented here intentionally.

### Within Each User Story

- Tests written first and expected to fail before implementation.
- Schemas/migrations before contexts; contexts before controllers; core before integration.

### Parallel Opportunities

- Setup: T003, T004 in parallel.
- Foundational: T006, T007, T009, T010, T013 in parallel (distinct files); T008 after T007; T011 after T010+T006; T012 after T011.
- Each story's `[P]` tests run together; `[P]` schemas within a story run together.
- After Foundational, US-level work can proceed; respect the dependency note above.

---

## Parallel Example: User Story 3

```bash
# Tests for US3 together:
Task: "Message controller test in test/api_harness_web/controllers/message_controller_test.exs"
Task: "Agent runtime + planner test in test/api_harness/agent/runtime_test.exs"
Task: "Context builder test in test/api_harness/agent/context_builder_test.exs"

# Independent building blocks together:
Task: "Create Message schema in lib/api_harness/chats/message.ex"
Task: "Implement Tool Registry in lib/api_harness/agent/tools/registry.ex"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & VALIDATE** (REPL CRUD + login). Deploy/demo.

### Incremental Delivery

Foundation → US1 (users/auth, MVP) → US2 (threads) → US3 (core AI chat) → US4 (memory) → US5 (async pipeline) → Polish. Each story adds value and is independently testable.

---

## Notes

- `[P]` = different files, no incomplete dependencies.
- All OpenAI calls are stubbed in tests via the configured provider behaviour (no live API).
- Constitution musts: Req-only OpenAI client; named OTP primitives (Registry/DynamicSupervisor); `Task.async_stream(timeout: :infinity)`; `:string` schema fields; FKs set on struct (not `cast/3`); no `Process.sleep`/`Process.alive?` in tests; `start_supervised!/1`; migrations via `mix ecto.gen.migration`.
- Commit after each task or logical group; run `mix precommit` before committing.
