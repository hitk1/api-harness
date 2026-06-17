# Phase 0 Research: Legal AI Agent Harness

This document resolves the technical unknowns surfaced in the plan's Technical Context. Each section records the **Decision**, **Rationale**, and **Alternatives considered**.

---

## 1. JWT issuance & verification (non-expiring, revocable)

**Decision**: Use `joken` (`{:joken, "~> 2.6}`) to sign and verify JWTs. Tokens omit the `exp` claim (non-expiring per FR-000-A) and carry `sub` (user id) plus a `jti` (token id). Revocation is enforced by storing a per-user `token_version` (integer) on the users table and embedding it as a claim; verification rejects tokens whose `token_version` claim ≠ the user's current value. Bumping `token_version` revokes all outstanding tokens for that user.

**Rationale**: Joken is a thin, well-maintained JWT library with no opinion on web framework — it fits a pure JSON API better than Guardian's plug/pipeline machinery. Non-expiring tokens (the clarified requirement) eliminate refresh complexity; the `token_version` claim restores a revocation lever without a token blocklist table. Signing uses HS256 with a secret from `.env`.

**Alternatives considered**:
- **Guardian**: heavier, brings pipelines/plugs and an error-handler protocol; overkill for one login endpoint and one auth plug.
- **Phoenix.Token**: simple but ties identity to the endpoint secret and is awkward for standard `Authorization: Bearer` interop expected by an external frontend.
- **DB session tokens (phx.gen.auth style)**: rejected — clarification explicitly chose JWT.

---

## 2. Password hashing for login

**Decision**: Use `bcrypt_elixir` (`{:bcrypt_elixir, "~> 3.1"}`). Users get a `hashed_password` column; the Accounts context hashes on create/update and exposes a `verify_password/2`-style check used by the login flow.

**Rationale**: Bcrypt is the Phoenix-default password hash (what `phx.gen.auth` uses), battle-tested, with a constant-time `no_user_verify/0` to mitigate user-enumeration timing attacks on login.

**Alternatives considered**:
- **argon2_elixir**: stronger memory-hardness but heavier NIF build; bcrypt is sufficient for a study project and lighter to compile.
- **pbkdf2_elixir**: acceptable but bcrypt is the more common default.

---

## 3. `.env` configuration loading

**Decision**: Use `dotenvy` (`{:dotenvy, "~> 0.9"}`) loaded at the top of `config/runtime.exs` to source `.env` (and `.env.<env>`) into the environment, then read all secrets (`DATABASE_URL`, `OPENAI_API_KEY`, `JWT_SECRET`, `SECRET_KEY_BASE`) via `System.fetch_env!/1` / `Dotenvy.env!/2`. `.env` is git-ignored; a committed `.env.example` documents required keys.

**Rationale**: Elixir does not natively read `.env` files. `dotenvy` is purpose-built, integrates cleanly with `runtime.exs` (the idiomatic place for runtime secrets), and works in all environments including releases. FR-025 explicitly requires `.env`-based config.

**Alternatives considered**:
- **Shell-sourced env vars only** (no lib): doesn't satisfy "read from a `.env` file" and burdens the developer.
- **`dotenv` (older lib)**: less maintained than `dotenvy` and not release-friendly.

---

## 4. OpenAI integration via Req (chat + embeddings)

**Decision**: Implement `ApiHarness.LLM.Provider` as a behaviour with `chat_completion/2` and `embed/2` callbacks, and `ApiHarness.LLM.OpenAI` as the Req-based implementation. Chat uses `POST https://api.openai.com/v1/chat/completions` with model `gpt-4o-mini`. Knowledge extraction and plan generation use **structured outputs** via `response_format: {type: "json_schema", json_schema: …}` so the model returns schema-valid JSON. Embeddings (for memory retrieval) use `POST /v1/embeddings` with `text-embedding-3-small`. The configured provider module is injected via application config so tests swap in a stub.

**Rationale**: Req is mandatory per constitution (Principle II). A behaviour + config-injected implementation makes the LLM mockable in ExUnit without live calls (Test Discipline). Structured outputs give deterministic, parseable JSON for the Planner and Knowledge Extractor, removing brittle free-text parsing. `text-embedding-3-small` is low-cost and sufficient for semantic memory retrieval.

**Alternatives considered**:
- **`openai_ex` / other client libs**: forbidden by spirit of Principle II (Req is the required HTTP client); also unnecessary wrapping.
- **JSON mode (`response_format: json_object`)** instead of `json_schema`: weaker guarantees (valid JSON but not schema-conformant); json_schema is preferred where supported by `gpt-4o-mini`.
- **Function/tool calling for extraction**: viable but structured outputs are simpler for a fixed extraction schema.

---

## 5. Relevance-based memory retrieval

**Decision**: Use **pgvector** (`{:pgvector, "~> 0.3"}` + Postgres `vector` extension) for semantic retrieval. Each `persistent_memory` row stores an `embedding vector(1536)` (from `text-embedding-3-small`). At retrieval time, the current task context (derived from the user message + active session memory) is embedded, and the top-K most similar persistent memories are fetched via cosine distance, **optionally filtered by category**. This satisfies FR-020 ("understand the task, retrieve only relevant memories") instead of dumping all memory.

**Rationale**: Semantic similarity search is the canonical implementation of relevance-based retrieval and directly demonstrates the harness concept central to this study project. pgvector keeps everything in the existing PostgreSQL store (no new datastore). Category filtering composes with vector search to scope retrieval (e.g., exclude unrelated domain memories — the spec's "family law vs labor law" example).

**Alternatives considered**:
- **LLM-as-retriever** (ask the model which stored memories are relevant): no extra extension, but adds latency/token cost per request and scales poorly as memory grows.
- **Keyword/category filter only** (no embeddings): simpler but misses semantic relevance; weak for paraphrased queries.
- **External vector DB (Pinecone/Qdrant)**: unnecessary infrastructure for a study project; violates "keep it in Postgres" simplicity.

---

## 6. Asynchronous memory pipeline topology

**Decision**: Model the pipeline as supervised GenServer jobs. A named `DynamicSupervisor` (`ApiHarness.Memory.Pipeline.Supervisor`) spawns one short-lived `Pipeline.Worker` GenServer per interaction; a named `Registry` tracks in-flight jobs. The Agent Runtime, after delivering the response, casts the interaction payload to start a worker (fire-and-forget — never blocks the response). Each worker runs the stages **extraction → classification → reconciliation → persistence**, retrying a failed stage **2–3 times** with backoff, then logging and discarding on exhaustion (FR-024-A). No dead-letter table.

**Rationale**: The PRD explicitly mandates GenServer-based async processing that scales to N users without message loss. Per-interaction processes under a DynamicSupervisor give true isolation (one user's failure can't block another), bounded by BEAM scheduling rather than a single mailbox bottleneck. A named Registry satisfies the constitution's "OTP primitives must declare `:name`" rule and enables observability. Short-lived workers avoid unbounded state growth.

**Alternatives considered**:
- **Single GenServer processing a queue**: serializes all users → head-of-line blocking and a single point of message loss; violates FR-024.
- **`Task.Supervisor` async_nolink tasks**: simpler, but GenServer is the PRD-specified primitive and gives clearer retry/state handling per job.
- **Oban (DB-backed jobs)**: would give durable retries/dead-letter, but the clarified decision is explicitly *no* dead-letter and *log-and-discard*; adding Oban contradicts that scope and adds a dependency the requirements don't call for.

---

## 7. Coordinator parallel worker execution

**Decision**: The `Coordinator` distributes plan sub-tasks to workers using `Task.async_stream/3` with `timeout: :infinity` and `on_timeout: :kill_task`, collecting results. If any worker returns an error (or raises), the Coordinator halts consumption, ensures remaining tasks are torn down, and returns a structured error so the whole request fails (FR-011) — no partial results.

**Rationale**: `Task.async_stream/3` is the constitution-mandated concurrency primitive (Principle III) and naturally maps to "run workers in parallel, gather results." Fail-total semantics are implemented by short-circuiting on the first error result.

**Alternatives considered**:
- **Manual `Task.async` + `Task.await_many`**: works but `async_stream` is the prescribed idiom and gives back-pressure.
- **Returning partial results**: rejected by clarification (fail-total).

---

## 8. Agent Runtime: Planner-always with single/multi-step plans

**Decision**: The `Planner` runs on every message (FR-010-A) and emits a structured plan via OpenAI structured outputs: either a **single-step** plan (`{steps: [{tool: "answer", …}]}` — a direct answer for simple questions) or a **multi-step** plan whose steps the `Executor` runs, dispatching parallelizable steps through the `Coordinator`. The runtime loop is uniform: `Planner → Executor → (Coordinator/Workers via Tool Registry) → assemble response`.

**Rationale**: A uniform path (no conditional bypass) is simpler to reason about and test, honors the PRD's "planning separated from execution" principle for all interactions, and was the clarified choice. Single-step plans keep overhead minimal for trivial questions while reusing the same code path as complex tasks.

**Alternatives considered**:
- **Conditional triage** (skip planner for "simple" messages): branchy, harder to test, and rejected by clarification.
- **Always multi-step**: wasteful for trivial questions.

---

## 9. Context Builder layering

**Decision**: `ContextBuilder` assembles the prompt in the exact six-layer order from FR-022: (1) system instruction (legal-domain agent role), (2) domain context (general legal preferences/notes), (3) session memory (current thread JSON state), (4) relevant persistent memory (top-K from pgvector retrieval), (5) recent conversation messages (windowed — default last 10, configurable), (6) current user question. Layers map to OpenAI chat messages: layers 1–4 composed into the `system` message (or leading context), layer 5 as prior `user`/`assistant` turns, layer 6 as the final `user` message.

**Rationale**: Mirrors the spec's prescribed structure exactly and keeps prompt assembly in one testable module. A configurable recent-message window resolves the Assumptions note without overcommitting.

**Alternatives considered**:
- **Dumping full history**: explicitly rejected by the spec ("memory is knowledge, not history").
- **Hard-coded window size**: less flexible; config value chosen instead.

---

## 10. Memory reconciliation & durable-knowledge threshold

**Decision**: The `Reconciler` receives extracted candidate facts (typed: preference | goal | constraint | fact, each with a category) and, for each, retrieves the most similar existing persistent memory (pgvector). An LLM call (structured output) decides the action: **create / update / merge / discard**. Durability is judged by the same LLM step using the spec's heuristic ("useful in ≥30 days?") — non-durable candidates are discarded. Every applied change writes a `memory_context_update` audit row. Persistent memory is never appended blindly (FR-017).

**Rationale**: Reconciliation is inherently semantic (is this the same knowledge, evolved?), so an LLM decision over the nearest existing record is the natural fit and matches the PRD's reconciler description. The audit table enables reconstructing memory evolution and debugging the "no append-only" guarantee.

**Alternatives considered**:
- **Deterministic rule-based reconciliation**: brittle for natural-language knowledge; can't judge semantic equivalence or durability well.
- **Always create** (append-only): explicitly forbidden (FR-017).

---

## Summary of new dependencies

| Dependency | Version | Purpose | Constitution impact |
|------------|---------|---------|---------------------|
| `joken` | ~> 2.6 | JWT sign/verify | New capability; no prescribed tool replaced |
| `bcrypt_elixir` | ~> 3.1 | Password hashing | New capability |
| `dotenvy` | ~> 0.9 | `.env` loading (FR-025) | New capability |
| `pgvector` | ~> 0.3 | Semantic memory retrieval | Extends Ecto/Postgres (prescribed store) |

All OpenAI HTTP traffic goes through **Req** (mandatory). No prescribed dependency is swapped. No constitution violations introduced.
