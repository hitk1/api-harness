# Phase 0 Research: Context Budget Management

Derived from the Functional Requirements and Technical Context in [spec.md](./spec.md). Resolves all NEEDS CLARIFICATION items before Phase 1 design begins.

---

## §1 — Token Counting Library

**Decision**: Use the `tiktoken` Hex package as the primary token counter, with a character-based approximation as a fallback.

**Library**: [`tiktoken`](https://hex.pm/packages/tiktoken) v0.4.2+ (MIT, actively maintained — Oct 2025, ~76k downloads)
- GitHub: `connorjacobsen/tiktoken-elixir`
- Mechanism: Rustler NIF compiled from Rust via PyO3
- Build requirement: **Rust toolchain and Python must be available at compile time**

**Build dependency caveat**: The library compiles a Rust NIF that bridges through PyO3, which requires both `rustup` (Rust toolchain) and a Python interpreter at build time. This is non-trivial for CI/deployment but manageable in a study project (both are typically available on development machines).

**Encoding for GPT-4o-mini**: `o200k_base` — **NOT `cl100k_base`**. GPT-4o-mini uses `o200k_base` (same as GPT-4o and o1). The spec mentions `cl100k_base` as an approximate reference — the implementation must use `o200k_base`.

**Fallback strategy**: If the `tiktoken` build fails (Rust/Python unavailable), the `TokenCounter` module falls back to `ceil(byte_size(text) / 4)`. This approximation has a ~5–10% margin of error for English text and ~3.5 chars/token for code. Acceptable for budget management given that budgets include a safety headroom, but logged as a warning.

**API**:
```elixir
{:ok, encoding} = Tiktoken.encoding_for_model("gpt-4o-mini")  # returns o200k_base
{:ok, count}    = Tiktoken.count_tokens("gpt-4o-mini", text, :no_special_tokens)
# Fallback
count = ceil(byte_size(text) / 4)
```

**Alternatives considered**:

| Option | Rejected Because |
|--------|-----------------|
| `ex_tiktoken` | Unmaintained (last update May 2023) |
| HTTP sidecar (tiktoken-counter Flask API) | Extra deployment dependency, network latency |
| Custom Rustler NIF | More work, no benefit over `tiktoken` which already does this |
| `gpt3_tokenizer` | GPT-3 only, wrong encoding |

---

## §2 — Compaction Threshold

**Decision**: 70% of available budget (not 80% as the spec draft assumed).

**Rationale**: Production systems (Claude Code, Cursor) trigger compaction at 70–75%, not 80–90%. Research shows the "lost-in-the-middle" quality degradation starts around 70% capacity. Compacting at 70% preserves quality and avoids the urgency of a 80% trigger that leaves less slack for the compaction LLM call itself.

**Configurable**: `compaction_threshold: 0.70` in application config (0.0–1.0 float), defaulting to 0.70. The spec's FR-024 uses "80%" as a default; this research document overrides that to 0.70 and makes it configurable.

---

## §3 — Rolling Summary Strategy

**Decision**: Full re-summarization for the initial implementation; incremental roll-up architecture available via the same interface for a future upgrade.

**Full re-summarization**: When compaction is triggered, the entire message history for the thread is passed to the LLM for summarization in one call. Simple, proven, produces the best summary quality. Latency cost: 5–15s for a typical thread (acceptable for an async background operation).

**Incremental roll-up** (deferred): When a rolling summary already exists and new messages have accumulated since the last compaction, summarize only the new span and merge with the existing summary. Faster but more complex and risks context drift over many cycles.

**Rolling summary structure**: The LLM prompt for compaction instructs the model to produce a structured summary capturing the following sections (adapted from the user's original list, validated against production systems):

```
1. Pedido e Intenção Primária
   Capture all explicit user requests and intentions verbatim, not paraphrased.

2. Conceitos Técnicos-Chave
   List all technical concepts, technologies, frameworks, patterns, and key
   variable/function/module names discussed.

3. Arquivos e Trechos de Código
   Enumerate files and specific code snippets examined, modified, or created.
   Preserve verbatim for blocks under ~50 lines; summarize with key callouts
   for larger blocks.

4. Erros e Correções
   List all errors that appeared (with verbatim messages where available) and
   how each was corrected.

5. Resolução de Problemas
   Document problems resolved and investigations currently in progress with
   their current status.

6. Mensagens do Usuário
   List ALL user messages (not tool results) verbatim — these are critical for
   preserving intent and are never paraphrased.

7. Tarefas Pendentes
   List all tasks explicitly requested but not yet completed.

8. Trabalho Atual
   Describe in detail precisely what was being done immediately before
   this compaction was triggered, with specific file names and code state.

9. Próximo Passo (Opcional)
   The next concrete action planned, if known.
```

**Summary size cap**: Rolling summary is capped at `rolling_summary_max_tokens` (default: 8,000 tokens). When the summary itself grows beyond this across multiple compaction cycles, a meta-summarization pass condenses it before merging. Stored as `:string` (`:text` column) on the `chats` table — no separate table.

---

## §4 — Storage for Rolling Summary and Session Metrics

**Decision**: Add columns directly to the `chats` table (no new table).

**Rationale**: Session metrics and rolling summary are per-chat data — the `chats` table already has the right FK relationship. Creating a separate `chat_context_metrics` table would require joins on every context assembly and is unnecessary overhead for a study project.

**New columns on `chats`**:

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `context_status` | `:string` | `"active"` | State machine: `active | needs_compaction | compacting | ready` |
| `rolling_summary` | `:string` | `nil` | Nullable; populated after first compaction |
| `rolling_summary_token_count` | `:integer` | `0` | Pre-computed token count of rolling_summary |
| `total_context_tokens` | `:integer` | `0` | Last-known total prompt tokens (updated post-response) |
| `compaction_count` | `:integer` | `0` | How many compactions have run for this thread |
| `last_compaction_at` | `:utc_datetime` | `nil` | Timestamp of last successful compaction |

**New columns on `messages`**:

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `token_count` | `:integer` | `0` | Computed at persistence time by `TokenCounter` |

**New columns on `persistent_memories`**:

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `token_count` | `:integer` | `0` | Computed at persistence time by `TokenCounter` |

**Backfill**: Existing records have `token_count = 0` (migration default). A one-time Mix task `mix api_harness.backfill_token_counts` will backfill all existing messages and persistent memories using `TokenCounter`. The `ContextRuntime` uses stored counts when non-zero; falls back to live counting when `0`.

---

## §5 — Context Runtime Architecture

**Decision**: Rename `ContextBuilder` to `ContextRuntime`, introduce a `ContextProvider` behaviour, implement six provider modules, and add `BudgetManager` as a stateless module.

**Provider modules** (all under `lib/api_harness/agent/context/`):

| Module | Layer | Replaces |
|--------|-------|---------|
| `Providers.SystemPrompt` | System instruction | Hardcoded string in `ContextBuilder` |
| `Providers.DomainMemory` | Domain memories | `Memory.list_persistent_memories_by_category(user_id, "domain")` call |
| `Providers.SessionMemory` | Session state | `Memory.get_session_memory(chat.id)` call |
| `Providers.PersistentMemory` | User + task memories | `Retriever.retrieve/3` call |
| `Providers.Conversation` | Recent messages + rolling summary | `Chats.list_recent_messages/2` call |
| `Providers.UserQuestion` | Current user question | Final `user` message |

**Budget flow**:
1. `BudgetManager.allocate(model_profile, opts)` → returns `%{system: N1, domain: N2, session: N3, memory: N4, conversation: N5, question: N6}` where all Nx are token counts
2. Each provider receives its allocation and returns `{content, actual_tokens_used}`
3. `ContextRuntime` assembles the prompt and validates total ≤ available budget

**Stateless modules**: `BudgetManager` and all providers are pure functions (no GenServer state). This keeps them testable and eliminates process overhead.

---

## §6 — Budget Distribution Proportions (Initial Defaults)

For a 128,000-token window with 16,384-token output reserve:
- **Available input budget**: 111,616 tokens

**Fixed-cost layers** (reserved first):
- System prompt: ~400 tokens (measured from existing `@system_instruction`)
- Current question: dynamic (always included, measured from incoming message)
- Safety headroom: 2% = ~2,232 tokens (buffers approximation errors)

**Remaining variable-cost budget** after fixed reservations (~109,000 tokens — available for distribution):
- Conversation history: **70%** (~76,300 tokens) — largest share; most valuable for continuity
- Persistent memory (user + task): **15%** (~16,350 tokens)
- Domain memory: **10%** (~10,900 tokens)
- Session memory: **5%** (~5,450 tokens)

**Rationale for proportions**:
- Conversation history dominates because the rolling summary + recent messages are the most contextually grounded data
- Persistent memory gets a meaningful slice for cross-session personalization
- Domain memory (legal knowledge) gets a smaller slice as it changes rarely and is less interaction-specific
- Session memory is compact by design (structured entries, not raw text) so 5% is sufficient

**Configurable**: All proportions are set in application config under `config :api_harness, :context_budget`. Unused tokens from smaller providers are redistributed to conversation in a single pass.

---

## §7 — Compaction Pipeline OTP Pattern

**Decision**: Mirror the existing persistent-memory pipeline pattern (`DynamicSupervisor` + `Registry`), not the session-memory `Coordinator` pattern.

**Rationale**:
- Compaction is an occasional, heavyweight one-time job (not a high-frequency per-turn event)
- It needs Registry-based deduplication (prevent two compactions for the same chat)
- `DynamicSupervisor` + temporary GenServer workers is the established pattern in this codebase for one-shot async jobs

**Registry key**: `{chat_id}` — prevents simultaneous compaction for the same thread

**Startup re-enqueue**: `ApiHarness.Context.Compaction.Bootstrap.enqueue_pending/0` is called from `Application.start/2` after the supervision tree is running. It queries for sessions in `needs_compaction` or `compacting` status and starts a worker for each.

**Supervision children** (added to `ApiHarness.Application`):
```elixir
{Registry, keys: :unique, name: ApiHarness.Context.Compaction.Registry},
{DynamicSupervisor, name: ApiHarness.Context.Compaction.Supervisor, strategy: :one_for_one}
```

**Worker lifecycle**: starts → transitions chat to `compacting` → calls LLM → persists rolling summary → updates metrics → transitions to `ready` → terminates. On failure: retries up to 3 times (linear backoff, same policy as memory pipeline); on exhaustion: logs and transitions back to `needs_compaction` (not `active`) so the next startup will re-enqueue.

---

## §8 — Context Metrics in API Response

**Decision**: Add `context_metrics` as a top-level key in the existing message response JSON, not a separate endpoint.

**Rationale**: The user requires per-interaction visibility into context window state, which is available immediately after context is assembled and the response generated. Embedding in the response avoids a round-trip for the frontend.

**Shape** (added to `MessageJSON.show/1`):
```json
{
  "message": { ... existing message fields ... },
  "context_metrics": {
    "total_tokens": 45321,
    "available_budget": 111616,
    "utilization_percentage": 0.406,
    "context_status": "active",
    "layers": {
      "system": 387,
      "domain_memory": 2100,
      "session_memory": 890,
      "persistent_memory": 4200,
      "conversation": 37100,
      "question": 644
    }
  }
}
```

The `layers` breakdown is included for development and debugging; it can be elided in production builds via config.

---

## §9 — Interaction with Existing Memory Pipelines

**No changes** to the persistent memory pipeline (`Memory.Pipeline.*`) or session memory pipeline (`Memory.SessionMemory.Coordinator`). Both remain untouched. The new post-response analysis (compaction threshold check) runs as an additional step in `MessageController.dispatch_pipeline/3`, alongside the existing pipeline dispatches.

**Execution order** after response delivery:
1. `Memory.Pipeline.Worker` dispatch (persistent memory) — unchanged
2. Session memory turn event broadcast — unchanged
3. **NEW**: `Context.PostResponse.analyze/2` — computes total context tokens, updates `chats.total_context_tokens`, and if threshold exceeded, sets `context_status = "needs_compaction"` and starts a compaction worker

All three are fire-and-forget from the controller.
