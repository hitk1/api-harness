# Implementation Plan: Legal AI Agent Harness

**Branch**: `001-legal-ai-agent-harness` | **Date**: 2026-06-16 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-legal-ai-agent-harness/spec.md`

## Summary

A Phoenix 1.8 JSON API that exposes an intelligent legal-domain chat agent. Users authenticate via non-expiring JWT, manage chat threads, and send messages to a synchronous endpoint that drives an **Agent Runtime** (Planner → Executor → Coordinator/Workers → Tool Registry → Context Builder → OpenAI `gpt-4o-mini`). Every interaction yields two products: the user-facing response (synchronous) and structured knowledge that flows through an **asynchronous memory pipeline** (extraction → classification → reconciliation → persistence) running off the request path via supervised GenServer processes. Memory is treated as managed knowledge — not an append-only log — with session memory scoped per thread and persistent memory reconciled (create/update/merge/discard) per user. Relevance-based retrieval feeds only pertinent memory into each prompt.

## Technical Context

**Language/Version**: Elixir ~> 1.15, Erlang/OTP (BEAM)

**Primary Dependencies**: Phoenix 1.8.3 (JSON API, no LiveView/HTML), Ecto SQL 3.13 + Postgrex, Bandit 1.5 (HTTP server), Req 0.5 (OpenAI HTTP client — mandatory per constitution), Jason. **New deps to add**: `joken` (JWT issue/verify), `bcrypt_elixir` (password hashing), `dotenvy` (`.env` loading), `pgvector` (memory similarity search).

**Storage**: PostgreSQL. Tables: users, chats (threads), messages, session_memories, persistent_memories (with `vector` embedding column), memory_context_updates, file_metadata (placeholder). pgvector extension enabled via migration.

**Testing**: ExUnit (`mix test`). `ConnCase` for controller tests, `DataCase` for Ecto/context tests. OpenAI calls stubbed via a behaviour + test double (Req `:plug`/test adapter) — no live API calls in tests.

**Target Platform**: Linux server (BEAM release). Dev at `localhost:4000`.

**Project Type**: Single Phoenix web-service project (backend only; all routes under `/api`).

**Performance Goals**: Synchronous chat response bounded by OpenAI latency (no added blocking). Memory pipeline strictly off the response path. Support N concurrent users, each with an independent pipeline process, no message loss between stages.

**Constraints**: JSON-only responses under `/api`. Fail-fast on OpenAI errors (HTTP 502/503, no retry, no fallback). Coordinator worker failure → whole request fails (no partial results). Async pipeline failure → 2–3 retries then log & discard (no dead-letter). JWT tokens non-expiring, revocable. Config/secrets loaded from `.env`.

**Scale/Scope**: Study project — correctness and architecture clarity over throughput tuning. 7 entities, 1 chat endpoint + auth + thread/user management, ~5 user stories.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. API-First Design | ✅ PASS | All routes under `/api` via `:api` pipeline (`accepts: ["json"]`). No browser pipeline, no LiveView, no HTML views except `ErrorJSON`. |
| II. Prescribed Tooling | ✅ PASS | OpenAI integration uses **Req** only. Bandit/Jason/Swoosh/Ecto+Postgrex retained. New deps (`joken`, `bcrypt_elixir`, `dotenvy`, `pgvector`) serve tasks not covered by the prescribed list and do not replace any prescribed tool. Date/time via stdlib. |
| III. Elixir Idioms | ✅ PASS (design intent) | GenServers/DynamicSupervisor/Registry will declare `:name`. Coordinator uses `Task.async_stream/3` with `timeout: :infinity`. No `String.to_atom/1` on user input. Predicate fns end with `?`. Enforced at review. |
| IV. Data Integrity | ✅ PASS (design intent) | `user_id`/`chat_id` set on struct, excluded from `cast/3`. Associations preloaded where serialized. Migrations via `mix ecto.gen.migration`. Schema fields `:string` even for `:text`. |
| V. Test Discipline | ✅ PASS (design intent) | `start_supervised!/1` for processes. No `Process.sleep/1`/`Process.alive?/1`. Monitor + `assert_receive` for termination; `:sys.get_state/1` for sync. |

**Result**: PASS — no violations. Complexity Tracking not required.

## Project Structure

### Documentation (this feature)

```text
specs/001-legal-ai-agent-harness/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (API endpoint contracts)
│   ├── auth.md
│   ├── chats.md
│   └── messages.md
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
lib/
├── api_harness/                      # Domain contexts & business logic
│   ├── application.ex                # Supervision tree (add Agent + Memory supervisors)
│   ├── repo.ex
│   ├── accounts/                     # User context
│   │   ├── user.ex                   # Ecto schema
│   │   └── accounts.ex               # CRUD (REPL-callable)
│   ├── chats/                        # Chat/thread + message context
│   │   ├── chat.ex
│   │   ├── message.ex
│   │   └── chats.ex
│   ├── memory/                       # Memory system
│   │   ├── session_memory.ex         # Ecto schema (per-thread JSON state)
│   │   ├── persistent_memory.ex      # Ecto schema (per-user, vector embedding)
│   │   ├── memory_context_update.ex  # Audit/change-log schema
│   │   ├── memory.ex                 # Context API (retrieval, reconcile persistence)
│   │   ├── retriever.ex              # Relevance-based retrieval (pgvector)
│   │   ├── reconciler.ex             # create/update/merge/discard decisions
│   │   ├── extractor.ex              # Knowledge extraction (LLM → structured JSON)
│   │   └── pipeline/                 # Async pipeline
│   │       ├── supervisor.ex         # DynamicSupervisor (:name)
│   │       ├── registry.ex           # Registry (:name)
│   │       └── worker.ex             # GenServer: extract→classify→reconcile→persist + retry
│   ├── agent/                        # Agent runtime (harness)
│   │   ├── runtime.ex                # Orchestrator (reasoning loop)
│   │   ├── planner.ex                # Produces structured action plan (always runs)
│   │   ├── executor.ex              # Executes plan steps
│   │   ├── coordinator.ex            # Parallel workers (Task.async_stream)
│   │   ├── context_builder.ex        # 6-layer prompt assembly
│   │   └── tools/                    # Tool registry
│   │       ├── registry.ex           # Tool lookup/dispatch
│   │       └── *.ex                  # Individual tool modules (stubs)
│   ├── llm/                          # LLM provider abstraction
│   │   ├── provider.ex               # Behaviour
│   │   └── openai.ex                 # Req-based OpenAI client (chat + embeddings)
│   └── files/                        # File metadata placeholder context
│       ├── file_metadata.ex
│       └── files.ex
└── api_harness_web/
    ├── router.ex                     # /api routes + auth pipeline
    ├── controllers/
    │   ├── auth_controller.ex        # POST /api/login
    │   ├── chat_controller.ex        # CRUD threads
    │   ├── message_controller.ex     # POST /api/chats/:id/messages
    │   └── *_json.ex                 # JSON views
    └── plugs/
        └── authenticate.ex           # JWT verification plug (assigns current user)

test/
├── api_harness/                      # Context/unit tests (DataCase)
└── api_harness_web/                  # Controller tests (ConnCase)
```

**Structure Decision**: Single Phoenix project. Domain logic lives under `lib/api_harness/` organized by bounded context (`accounts`, `chats`, `memory`, `agent`, `llm`, `files`); web layer under `lib/api_harness_web/`. The agent harness (`agent/`) and memory system (`memory/`) are the architectural core and get dedicated context trees. The async pipeline is supervised independently of the request path.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
