# Feature Specification: Context Budget Management

**Feature Branch**: `003-context-budget-management`

**Created**: 2026-07-20

**Status**: Draft

**Input**: User analysis (pt-BR): implementar controle de janela de contexto (quantidade de tokens por sessao), adaptando conceitos de Context Runtime com Budget Manager, Token Counter, Providers e compaction strategy ao harness existente. O sistema hoje concatena informacoes sem controle de budget — deve tratar a janela de contexto como recurso finito, distribuindo orcamento entre providers, compactando sessoes longas, e expondo metricas ao frontend.

---

## Gap Analysis: Current State vs. Proposed Architecture

Before the user stories, this section maps the concepts from `analise-context-management.md` against the current implementation, identifying what exists, what can be adapted, and what must be built.

### What already exists and aligns

| Concept from Analysis | Current Implementation | Adaptation |
|---|---|---|
| Providers (sources of information) | `ContextBuilder` queries 6 distinct sources (system prompt, domain memories, session memory, user/task memories, recent messages, current question) | Each source becomes a formal `Provider` module conforming to a behaviour |
| Context never stored as a prompt | Context is rebuilt from sources every interaction via `ContextBuilder.build/3` | Already aligned — no change needed |
| Session memory organized in levels | Session memory has categorized entries (goal/fact/constraint/preference) since spec 002 | Already aligned — can be extended with `token_count` tracking |
| Async post-response pipelines | Both persistent memory and session memory pipelines run async after response delivery | Compaction pipeline follows the same pattern |
| Importance/relevance-based retrieval | `Memory.Retriever` uses pgvector cosine similarity for persistent memories | Extend with importance scoring for budget-constrained selection |

### What is missing and must be built

| Concept from Analysis | Gap | Priority |
|---|---|---|
| Token Counter | No token counting anywhere — no pre-computed counts on messages, memories, or system prompt | P1 — foundation for everything else |
| Budget Manager | No concept of a token budget — all sources dump unlimited content | P1 — prevents context overflow |
| Context Runtime (orchestrator) | `ContextBuilder` concatenates directly; no budget negotiation between sources | P1 — replaces current `ContextBuilder` |
| Provider behaviour with detail levels | Sources have no concept of FULL/SUMMARY/ESSENTIAL representations | P2 — enables graceful degradation |
| Rolling Summary | Old messages are simply truncated (last N window) — no summarization | P2 — preserves context across long sessions |
| Session metrics | No tracking of per-session token usage or context utilization | P2 — enables frontend visibility and compaction triggers |
| Session states (NEEDS_COMPACTION) | No compaction mechanism; long sessions degrade silently | P2 — resilient compaction lifecycle |
| Compaction pipeline | No mechanism to compress context when session approaches limit | P2 — extends session lifetime |
| Frontend metrics exposure | No API surface for context window utilization | P3 — user feedback |
| Context Planner (dynamic strategy) | No intelligence about what kind of context each interaction needs | Deferred — future enhancement |

### What is explicitly deferred

- **Context Planner**: The analysis proposes a Context Planner that dynamically decides budget allocation strategy per interaction (e.g., "this question needs more memory, less conversation history"). This is deferred to a future feature — the initial implementation uses static proportional allocation, which can be replaced later without changing the provider/budget interface.
- **Importance Score on all entities**: The analysis proposes `0.0–1.0` importance scoring on every stored element. This feature introduces `token_count` tracking but defers full importance scoring to a future iteration. Priority-based pruning uses the existing category hierarchy (system > memories > conversation) rather than per-element scores.
- **Model switching**: Budget parameters are configurable per model profile, but runtime model selection remains out of scope.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Predictable Context Window Usage (Priority: P1)

As a system operator, I want the system to never exceed the LLM's context window limit regardless of how long a conversation runs or how many memories accumulate, so that every interaction produces a valid response instead of failing with a token overflow error.

**Why this priority**: This is the foundational problem. Without budget enforcement, every other feature (compaction, metrics, graceful degradation) is moot. Today, the system has no protection against overflow — a sufficiently long conversation or rich memory set will silently exceed the context window and cause API errors.

**Independent Test**: Create a chat thread with a large volume of persistent memories (>50 entries) and session memory entries, send 20+ messages to build up conversation history, then send one more message. Verify the total prompt sent to the LLM does not exceed the configured context window limit, and the response is returned successfully.

**Acceptance Scenarios**:

1. **Given** a user has accumulated extensive persistent memories and a long conversation history in a thread, **When** they send a new message, **Then** the assembled prompt's total token count does not exceed the model's context window limit minus the output reserve.
2. **Given** the system constructs context for a message, **When** the total available information exceeds the budget, **Then** lower-priority layers are reduced (summarized or truncated) rather than exceeding the limit.
3. **Given** a configured context window of N tokens and output reserve of M tokens, **When** context is assembled, **Then** the prompt uses at most N - M tokens, and this constraint is enforced by the Budget Manager before the prompt is sent to the LLM.

---

### User Story 2 - Token Budget Distribution Across Providers (Priority: P1)

As a system operator, I want the available context window to be distributed as a budget across the different information sources (system prompt, memories, conversation, tools) with each source respecting its allocation, so that no single source can monopolize the context window and crowd out other essential information.

**Why this priority**: Budget distribution is the mechanism that makes US1 enforceable. Without it, a user with 200 persistent memories would consume the entire window before conversation history is included. This story establishes the Provider behaviour and Budget Manager as the core architectural components.

**Independent Test**: Configure a model with a small context window (e.g., 4,000 tokens) and verify that each provider receives and respects its allocated budget — system prompt is present, at least some memory is included, at least some conversation history is included, and the current question is always included in full.

**Acceptance Scenarios**:

1. **Given** a context window budget is calculated, **When** the Budget Manager distributes it, **Then** each provider receives a non-negative integer budget in tokens and the sum of all budgets does not exceed the available window.
2. **Given** a provider receives a budget of B tokens, **When** it assembles its content, **Then** the returned content uses at most B tokens.
3. **Given** the system prompt and current user question are fixed-cost layers, **When** the Budget Manager distributes the budget, **Then** these layers are reserved first (guaranteed allocation) before distributing the remaining budget to variable-cost layers (memories, conversation).
4. **Given** a provider has less content than its allocated budget, **When** it returns content, **Then** the unused portion of the budget is available for redistribution to other providers.

---

### User Story 3 - Pre-Computed Token Accounting (Priority: P2)

As a system operator, I want token counts to be calculated and stored when messages and memories are persisted, so that context construction does not require expensive tokenization on the critical request path and session metrics can be maintained incrementally.

**Why this priority**: Pre-computed counts are the enabler for efficient budget management. Without them, every context assembly would need to re-tokenize all candidate content, adding latency to the response path. Depends on US1/US2 establishing the budget framework that consumes these counts.

**Independent Test**: Persist a message via the API and verify the database record includes a `token_count` column with a value consistent with the message's content length. Verify that `ContextBuilder` (now Context Runtime) uses stored token counts instead of re-counting during assembly.

**Acceptance Scenarios**:

1. **Given** a user sends a message, **When** the message is persisted to the `messages` table, **Then** the `token_count` column is populated with the token count of the message content.
2. **Given** the assistant generates a response, **When** the assistant message is persisted, **Then** its `token_count` is also stored.
3. **Given** a persistent memory entry is created or updated, **When** it is persisted, **Then** the `token_count` column reflects the current content's token count.
4. **Given** the Context Runtime is selecting messages for the conversation window, **When** it evaluates which messages fit within the budget, **Then** it uses the pre-computed `token_count` values, not a live re-tokenization.

---

### User Story 4 - Conversation Compaction via Rolling Summary (Priority: P2)

As a user having a long conversation in a thread, I want the system to automatically compress older parts of the conversation into a structured summary rather than simply dropping them, so that I do not lose important context even as the conversation grows beyond what the raw message window can hold.

**Why this priority**: This is the primary strategy for extending session lifetime. Without compaction, once conversation history exceeds its budget, older messages are silently dropped (current behavior with the fixed window of N messages). With compaction, older messages are summarized and the summary is included alongside recent messages, preserving continuity. Depends on US3 for token accounting.

**Independent Test**: Create a conversation with 30+ turns in a single thread. Verify that the context sent to the LLM contains a rolling summary of older turns plus the most recent turns, and that information from early turns (e.g., a client name mentioned in turn 2) is present in the rolling summary.

**Acceptance Scenarios**:

1. **Given** a thread's conversation history exceeds the conversation provider's budget, **When** context is assembled for the next message, **Then** the conversation layer includes a rolling summary of older messages plus the most recent messages that fit within budget.
2. **Given** a rolling summary is generated for a thread, **When** it is produced, **Then** it captures at minimum: primary requests and user intentions, key technical concepts discussed, facts established, errors encountered and how they were resolved, pending tasks, and current work state.
3. **Given** a rolling summary already exists for a thread, **When** a new compaction is triggered, **Then** the new summary incorporates the previous summary plus the messages since the last compaction — it does not re-process the entire conversation history.
4. **Given** the conversation provider has a budget of B tokens, **When** it has both a rolling summary (S tokens) and recent messages, **Then** it includes the rolling summary plus as many recent messages as fit within (B - S) tokens, preserving the most recent messages.

---

### User Story 5 - Session Lifecycle and Compaction Resilience (Priority: P2)

As a system operator, I want sessions to be automatically flagged when their context utilization approaches the limit, compaction to be triggered asynchronously, and interrupted compactions to be retried on next startup, so that the system self-heals without manual intervention.

**Why this priority**: Compaction without lifecycle management is fragile — if the process crashes mid-compaction, the session is left in an inconsistent state. This story adds the state machine (ACTIVE/NEEDS_COMPACTION/COMPACTING/READY) and the resilience layer that makes compaction production-grade. Depends on US4 for the compaction logic itself.

**Independent Test**: Send messages until a session's token usage crosses the compaction threshold. Verify the session is flagged `NEEDS_COMPACTION`, compaction runs and produces a rolling summary, and the session transitions to `READY`. Then kill the application mid-compaction, restart, and verify the flagged session is re-processed.

**Acceptance Scenarios**:

1. **Given** a response is delivered and the async post-response analysis determines the session's total context utilization exceeds the compaction threshold (configurable, e.g., 80% of available budget), **When** this is detected, **Then** the session's `context_status` is set to `NEEDS_COMPACTION`.
2. **Given** a session is in `NEEDS_COMPACTION` status, **When** the compaction pipeline processes it, **Then** the status transitions to `COMPACTING` during processing and to `READY` upon successful completion.
3. **Given** a session is in `COMPACTING` status and the application restarts, **When** the application starts, **Then** it discovers sessions in `COMPACTING` or `NEEDS_COMPACTION` status and re-enqueues them for compaction.
4. **Given** a session is in `COMPACTING` status, **When** a user sends a message to that thread, **Then** the system returns an appropriate response indicating the session is temporarily unavailable for interaction until compaction completes.
5. **Given** compaction completes successfully, **When** the session transitions to `READY`, **Then** the session metrics (rolling_summary_tokens, message_tokens, total_context_tokens) are updated to reflect the post-compaction state.

---

### User Story 6 - Context Usage Metrics for Frontend (Priority: P3)

As a frontend developer, I want the API to return context window utilization metrics (tokens used per layer, total, remaining capacity) with each message response, so that I can show the user how much of their session's context window is consumed and when compaction is approaching.

**Why this priority**: This is a visibility/UX enhancement layered on top of US1-US5. The system works correctly without it, but the user explicitly requested frontend feedback on context window state. Depends on US3 for token accounting and US5 for session metrics.

**Independent Test**: Send a message and inspect the API response JSON. Verify it includes a `context_metrics` object with fields for each layer's token usage, total usage, available budget, and utilization percentage.

**Acceptance Scenarios**:

1. **Given** a user sends a message and receives a response, **When** the response JSON is returned, **Then** it includes a `context_metrics` object containing: `total_tokens`, `available_budget`, `utilization_percentage`, and per-layer breakdowns (`system_tokens`, `memory_tokens`, `conversation_tokens`, `question_tokens`).
2. **Given** the session is approaching the compaction threshold, **When** metrics are returned, **Then** the `utilization_percentage` reflects this proximity, allowing the frontend to display a warning indicator.
3. **Given** compaction has recently completed for the session, **When** the next message's metrics are returned, **Then** the `utilization_percentage` reflects the reduced token usage after compaction.

---

### Edge Cases

- What happens when the system prompt alone exceeds the context window budget? The system must fail with a configuration error at startup, not at request time.
- What happens when a single user message exceeds the remaining budget after all fixed allocations? The message must be truncated with a warning, not rejected — the user should still get a response.
- What happens when the token counter library is unavailable or returns an error? Fall back to a character-based approximation (chars / 4) rather than blocking the request.
- What happens when a provider has zero budget allocated? It must return empty content without error.
- What happens when compaction is triggered but the LLM used for summarization is unavailable? The session remains in `NEEDS_COMPACTION` and retries on the next cycle — it does not transition to `COMPACTING` if the LLM cannot be reached.
- What happens when multiple messages arrive for a thread in `NEEDS_COMPACTION` before compaction starts? Messages are still processed normally (using current uncompacted context within budget) — compaction runs when the pipeline processes it.
- What happens when the rolling summary itself grows very large over many compaction cycles? The summary is bounded to a configurable maximum token count; when it exceeds this, it is itself re-summarized.
- What happens when budget redistribution from underutilized providers creates a cycle (provider A returns less, provider B gets more, assembly re-runs)? Budget distribution runs exactly once — unused budget from fixed-cost layers is redistributed to variable-cost layers in a single pass, no iteration.

---

## Requirements *(mandatory)*

### Functional Requirements

#### Token Counting

- **FR-001**: System MUST compute and store a `token_count` for every message persisted to the `messages` table, calculated at persistence time (not at context assembly time).
- **FR-002**: System MUST compute and store a `token_count` for every persistent memory entry persisted to the `persistent_memories` table, recalculated when content is updated.
- **FR-003**: System MUST provide a `TokenCounter` module capable of counting tokens for a given text string, returning an integer token count. The module MUST support the tokenizer appropriate for the configured LLM model (cl100k_base for GPT-4o-mini).
- **FR-004**: If the tokenizer library is unavailable or fails, the `TokenCounter` MUST fall back to a character-based approximation (characters / 4, rounded up) and log a warning — it MUST NOT block the request or raise an error.

#### Budget Management

- **FR-005**: System MUST implement a `BudgetManager` module responsible for calculating the available context budget (model context window minus output reserve) and distributing it across providers.
- **FR-006**: The Budget Manager MUST allocate budget in two tiers: (1) fixed-cost layers with guaranteed allocation (system prompt, current user question) are reserved first; (2) the remaining budget is distributed proportionally among variable-cost layers (memories, conversation history).
- **FR-007**: The proportional distribution among variable-cost layers MUST be configurable via application config (e.g., `persistent_memory: 0.15, session_memory: 0.10, conversation: 0.65, domain: 0.10`).
- **FR-008**: When a fixed-cost or variable-cost provider uses fewer tokens than allocated, the unused portion MUST be redistributed to other variable-cost providers in a single redistribution pass — not iteratively.
- **FR-009**: The Budget Manager MUST expose its configuration as a model profile (context window size, output reserve, provider budget proportions) that can be overridden per model — enabling future model switching without code changes.

#### Context Runtime (Provider Architecture)

- **FR-010**: System MUST refactor the current `ContextBuilder` into a `ContextRuntime` module that orchestrates context assembly through a set of Providers, each conforming to a `ContextProvider` behaviour.
- **FR-011**: The `ContextProvider` behaviour MUST define callbacks: `plan(opts)` returning the provider's available content size and cost estimates at each detail level, and `provide(budget, opts)` returning content that fits within the given budget.
- **FR-012**: System MUST implement the following providers, each wrapping an existing information source: `SystemPromptProvider`, `DomainMemoryProvider`, `SessionMemoryProvider`, `PersistentMemoryProvider`, `ConversationProvider`, `UserQuestionProvider`.
- **FR-013**: Providers MUST NOT know the total context window size, the output reserve, or the global budget. They receive only their allocated budget (an integer token count) and return content within it.
- **FR-014**: The `ContextRuntime` MUST assemble the prompt by: (1) asking the Budget Manager for allocations; (2) calling each provider's `provide/2` with its allocation; (3) assembling the final prompt from provider outputs; (4) validating the total does not exceed the available budget before sending to the LLM.

#### Detail Levels

- **FR-015**: Each variable-cost provider MUST support at least two detail levels: `full` (all available content within budget) and `essential` (a minimal representation that fits a significantly smaller budget).
- **FR-016**: The `ConversationProvider` MUST support three detail levels: `full` (rolling summary + recent messages), `summary` (rolling summary only), and `essential` (last 2 messages only).
- **FR-017**: When the Budget Manager determines that a provider's allocated budget is insufficient for its `full` detail level, it MUST request the `essential` level instead — the provider MUST NOT silently truncate critical content.

#### Rolling Summary and Compaction

- **FR-018**: System MUST implement a rolling summary mechanism for conversation history. When the token count of all messages in a thread exceeds the conversation provider's budget, older messages MUST be summarized into a `rolling_summary` stored on the thread's session (or a dedicated table).
- **FR-019**: The rolling summary MUST be generated by the LLM and MUST capture at minimum: primary user requests and intentions, key concepts discussed, facts established, errors and corrections, pending tasks, and current work state.
- **FR-020**: The rolling summary MUST be bounded to a configurable maximum token count. When the summary itself grows beyond this limit across multiple compaction cycles, it MUST be re-summarized.
- **FR-021**: Compaction MUST run asynchronously after the response is delivered, following the same pattern as the existing memory pipelines. It MUST NOT block or delay the user-facing response.

#### Session Lifecycle

- **FR-022**: System MUST track per-session context metrics: `total_context_tokens` (last known total), `rolling_summary_tokens`, `message_tokens`, `memory_tokens`, `compaction_count`, `last_compaction_at`.
- **FR-023**: System MUST maintain a `context_status` on each chat/session with states: `active` (normal operation), `needs_compaction` (flagged by post-response analysis), `compacting` (compaction in progress), `ready` (post-compaction, normal operation resumes).
- **FR-024**: After each response is delivered, the system MUST perform an async analysis of the session's total context token utilization. If it exceeds a configurable threshold (default: 80% of the available budget), the session MUST be flagged as `needs_compaction`.
- **FR-025**: When a user sends a message to a thread in `compacting` status, the system MUST return an HTTP response indicating the session is temporarily unavailable (HTTP 409 or 503 with a structured JSON body explaining that compaction is in progress).
- **FR-026**: On application startup, the system MUST query for sessions in `needs_compaction` or `compacting` status and re-enqueue them for compaction processing.

#### API Metrics Exposure

- **FR-027**: The message endpoint response MUST include a `context_metrics` object containing: `total_tokens` (tokens used in the prompt for this interaction), `available_budget` (maximum usable tokens), `utilization_percentage` (total / available as a float 0.0–1.0), and `context_status` (current session lifecycle state).
- **FR-028**: The `context_metrics` object MAY optionally include per-layer breakdowns (`system_tokens`, `domain_memory_tokens`, `session_memory_tokens`, `persistent_memory_tokens`, `conversation_tokens`, `question_tokens`) for debugging and frontend display.

### Key Entities

- **Token Counter**: Utility module that maps text to an integer token count. Stateless, used at persistence time and optionally during budget planning. Encapsulates the tokenizer library dependency.
- **Budget Manager**: Stateless module that receives model profile parameters (window size, output reserve, provider proportions) and returns a budget allocation map distributing tokens across named providers. The single authority on how the context window is divided.
- **Context Runtime**: Orchestrator that replaces `ContextBuilder`. Coordinates Budget Manager and Providers to assemble the prompt. The only module that calls providers and assembles the final message list.
- **Context Provider (behaviour)**: Interface for information sources. Each provider receives a budget, returns content within budget. Knows nothing about the global window. Replaces the inline queries in today's `ContextBuilder`.
- **Rolling Summary**: Per-thread compressed representation of older conversation messages. Stored alongside session memory. Generated by the LLM during compaction. Included by the `ConversationProvider` as a prefix to recent messages.
- **Session Context Metrics**: Per-session tracking of token usage across layers. Updated after each interaction. Used to trigger compaction and to populate the API response's `context_metrics` field.
- **Compaction Pipeline**: Async process that generates rolling summaries, updates session metrics, and transitions session lifecycle state. Follows the existing pipeline patterns (retry with backoff, log-and-discard on exhaustion).

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The total token count of every prompt sent to the LLM is at most `context_window - output_reserve` for the configured model, regardless of the volume of memories or conversation history.
- **SC-002**: Each provider in the context assembly receives and respects a token budget — no single provider can consume tokens allocated to another.
- **SC-003**: Messages and persistent memory entries have pre-computed `token_count` values that match the tokenizer's output for their content (within a tolerance of 0 for exact tokenizers, or within 20% for the fallback approximation).
- **SC-004**: A conversation that exceeds the conversation provider's budget produces a rolling summary of older messages rather than silently dropping them.
- **SC-005**: Information from early turns of a long conversation (e.g., turn 2 of a 40-turn thread) is present in the rolling summary included in the prompt, even though the raw messages were compacted.
- **SC-006**: Sessions approaching the compaction threshold are automatically flagged and compacted without manual intervention.
- **SC-007**: An application restart discovers and re-processes sessions that were interrupted during compaction.
- **SC-008**: The message API response includes `context_metrics` with token usage and utilization percentage, enabling the frontend to display context window state.
- **SC-009**: AI response latency is not measurably increased by the budget management overhead — budget calculation and provider coordination add negligible time compared to the LLM call itself.

---

## Clarifications

### Session 2026-07-20

- Q: Should the system use an exact tokenizer (e.g., tiktoken/cl100k_base) or a character-based approximation for token counting? -> A: Prefer an exact tokenizer if a suitable Elixir library exists (e.g., `tiktoken_ex`, `tokenizers`). Fall back to character-based approximation (chars/4) if the library is unavailable at runtime. The choice is encapsulated in the `TokenCounter` module and can be swapped without affecting consumers.
- Q: Should compaction block user interaction? -> A: Yes. When a session is in `compacting` status, messages to that thread must return a structured error response indicating compaction is in progress. The user must wait for compaction to finish before sending new messages. This prevents race conditions between compaction (which rewrites session state) and new messages (which generate new context).
- Q: Should the Context Planner (dynamic, per-interaction budget strategy) be included? -> A: Deferred. The initial implementation uses static proportional allocation configured via application config. The provider/budget interface is designed to be compatible with a future Context Planner that dynamically adjusts proportions per interaction.
- Q: How should the rolling summary be stored? -> A: As a new `rolling_summary` text column on the `chats` table (or `session_memories` table), alongside a `rolling_summary_token_count` integer column. This avoids creating a new table and keeps the summary co-located with the thread it describes.
- Q: Should existing messages be backfilled with `token_count` values? -> A: Yes. A migration should add the `token_count` column with a default of 0, and a one-time mix task should backfill existing records. New messages are counted at persistence time going forward.

---

## Assumptions

- **Model parameters**: The primary model is `gpt-4o-mini` with a 128,000-token context window and 16,384-token maximum output. These values are configurable via the model profile in application config, not hardcoded.
- **Tokenizer availability**: An Elixir-compatible tokenizer library for cl100k_base exists or can be integrated. If not, the character-based fallback (chars/4) provides a reasonable approximation for budget management purposes — precision is less critical than the guarantee of staying within bounds.
- **Budget proportions are initial defaults**: The configured proportions (e.g., persistent_memory: 15%, session_memory: 10%, conversation: 65%, domain: 10%) are starting points. They will be tuned based on real-world usage and may be replaced by a dynamic Context Planner in a future feature.
- **Compaction uses the same LLM**: Rolling summary generation uses the same `ApiHarness.LLM.Provider` (and the same model) as regular chat completions. No separate model or provider is introduced for compaction.
- **Single compaction threshold**: A single configurable threshold (default 80% utilization) triggers compaction. More sophisticated strategies (graduated compression, priority-based pruning) are deferred.
- **No importance scoring on individual entities**: This feature does not add a `0.0–1.0` importance score to messages or memories. Priority-based pruning uses the layer hierarchy (system > memories > conversation) rather than per-element scores. Importance scoring is a candidate for a future feature.
- **Backward compatibility**: Existing messages without a `token_count` value (pre-migration) are treated as having a count of 0 until backfilled. The `ContextRuntime` falls back to live tokenization for any content without a pre-computed count.
- **Session memory token tracking**: Session memory's token cost is estimated from the serialized `state` jsonb size, not from individual entry token counts. This is an approximation that avoids modifying the session memory entry shape established in spec 002.
- **This feature does not change the external API contract** beyond adding the optional `context_metrics` field to the message response. All existing request/response fields remain unchanged.
