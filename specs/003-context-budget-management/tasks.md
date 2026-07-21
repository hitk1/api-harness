# Tasks: Context Budget Management

**Input**: Design documents from `specs/003-context-budget-management/`

**Prerequisites**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅ | contracts/ ✅ | quickstart.md ✅

**Tests**: Not included — spec does not request TDD approach.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in current phase)
- **[Story]**: Which user story this task belongs to (`US1`–`US6`)
- Exact file paths in every task description

---

## Phase 1: Setup (Dependency + Migrations)

**Purpose**: Add new dependency and create all three database migrations. Must complete before any schema or module work begins.

- [ ] T001 Add `{:tiktoken, "~> 0.4"}` to the `deps` list in `mix.exs` and run `mix deps.get` — verify Rust toolchain is available for NIF compilation
- [ ] T002 Generate and implement migration for `messages.token_count`: run `mix ecto.gen.migration add_token_count_to_messages` then add `alter table(:messages) do; add :token_count, :integer, default: 0, null: false; end` in `priv/repo/migrations/..._add_token_count_to_messages.exs`
- [ ] T003 [P] Generate and implement migration for `persistent_memories.token_count`: run `mix ecto.gen.migration add_token_count_to_persistent_memories` then add `alter table(:persistent_memories) do; add :token_count, :integer, default: 0, null: false; end` in `priv/repo/migrations/..._add_token_count_to_persistent_memories.exs`
- [ ] T004 [P] Generate and implement migration for context management columns on `chats`: run `mix ecto.gen.migration add_context_management_to_chats` then add `context_status :string default "active" not null`, `rolling_summary :text nullable`, `rolling_summary_token_count :integer default 0 not null`, `total_context_tokens :integer default 0 not null`, `compaction_count :integer default 0 not null`, `last_compaction_at :utc_datetime nullable` in `priv/repo/migrations/..._add_context_management_to_chats.exs`; also create partial index: `create index(:chats, [:context_status], where: "context_status IN ('needs_compaction', 'compacting')", name: :chats_pending_compaction_index)` in the same migration
- [ ] T005 Run `mix ecto.migrate` to apply all three migrations; verify with `mix ecto.migrations` that all show as up

**Checkpoint**: Three migrations applied. Database schema updated. Ready for module work.

---

## Phase 2: Foundational (Schema Modules + TokenCounter)

**Purpose**: Token counting utility and updated Ecto schemas. These block ALL user story phases — every provider and the runtime depend on `TokenCounter.count/1` and the updated schemas.

⚠️ **CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T006 Create `lib/api_harness/llm/token_counter.ex` — single public function `count(text :: String.t()) :: non_neg_integer()`. Primary: call `Tiktoken.count_tokens("gpt-4o-mini", text, :no_special_tokens)` returning the integer count. Fallback (when NIF unavailable): `max(1, div(byte_size(text), 4))` with `Logger.warning/1`. The module must not raise — always return an integer.
- [ ] T007 Add `token_count` field to `lib/api_harness/chats/message.ex` — field `:token_count, :integer, default: 0` in the schema. Do NOT add `token_count` to the `cast/3` call in the changeset — it is system-set only.
- [ ] T008 [P] Add `token_count` field to `lib/api_harness/memory/persistent_memory.ex` — field `:token_count, :integer, default: 0` in the schema. Do NOT add to `cast/3`.
- [ ] T009 [P] Add six context management fields to `lib/api_harness/chats/chat.ex`: `field :context_status, :string, default: "active"`, `field :rolling_summary, :string`, `field :rolling_summary_token_count, :integer, default: 0`, `field :total_context_tokens, :integer, default: 0`, `field :compaction_count, :integer, default: 0`, `field :last_compaction_at, :utc_datetime`. None of these appear in `cast/3` — all are system-set.
- [ ] T010 Add two context functions to `lib/api_harness/chats/chats.ex`: `update_context_status(chat_id :: integer(), status :: String.t()) :: {:ok, Chat.t()} | {:error, Ecto.Changeset.t()}` (sets `context_status` directly on struct, calls `Repo.update/1`) and `update_context_metrics(chat_id :: integer(), attrs :: map()) :: {:ok, Chat.t()} | {:error, Ecto.Changeset.t()}` (sets `total_context_tokens`, `rolling_summary`, `rolling_summary_token_count`, `compaction_count`, `last_compaction_at` directly on struct). Both must use `Ecto.Changeset.change/2` not `cast/3` for system-set fields.

**Checkpoint**: `TokenCounter.count("test")` returns a positive integer in IEx. `Chat`, `Message`, and `PersistentMemory` structs expose the new fields. `Chats.update_context_status/2` compiles and updates the DB.

---

## Phase 3: US1 + US2 — Predictable Context Window + Budget Distribution (Priority: P1)

**Goal**: Assembled prompts never exceed the model context window. Available tokens are distributed across providers using a BudgetManager. `ContextBuilder` is replaced by `ContextRuntime`.

**Independent Test** (quickstart.md Scenario 3): In IEx, `BudgetManager.allocate(BudgetManager.default_profile())` returns a map where all values sum to ≤ `available_budget`. Messages sent to the API never produce OpenAI token-limit errors.

### Implementation for US1 + US2

- [ ] T011 [US1] [US2] Create `lib/api_harness/agent/context/providers/behaviour.ex` — define `@callback plan(opts :: keyword()) :: %{full: non_neg_integer(), essential: non_neg_integer()}` and `@callback provide(budget :: non_neg_integer(), opts :: keyword()) :: {content :: String.t(), tokens_used :: non_neg_integer()}`. Module body is just `@callback` declarations and a `@moduledoc`.
- [ ] T012 [US1] [US2] Create `lib/api_harness/agent/context/budget_manager.ex` — two public functions: `default_profile() :: map()` returning `%{context_window: 128_000, output_reserve: 16_384, safety_headroom: 0.02, proportions: %{domain: 0.10, session: 0.05, memory: 0.15, conversation: 0.70}}` (all configurable via `Application.get_env(:api_harness, :context_budget)` with these as defaults); `allocate(profile :: map(), opts :: keyword()) :: map()` computing `available_budget = context_window - output_reserve - ceil(context_window * safety_headroom)`, reserving `system` (measured from `SystemPromptProvider.plan/1`) and `question` (measured from `opts[:question_tokens]`), then distributing the remainder proportionally via `profile.proportions`. Unused budget from providers that underrun is added to `conversation`. Returns `%{system: N, domain: N, session: N, memory: N, conversation: N, question: N, total: N, available_budget: N}`.
- [ ] T013 [P] [US2] Create `lib/api_harness/agent/context/providers/system_prompt.ex` — `@behaviour ApiHarness.Agent.Context.Providers.Behaviour`. `plan/1` returns `%{full: TokenCounter.count(@system_instruction), essential: TokenCounter.count(@system_instruction)}` (fixed cost). `provide/2` always returns `{@system_instruction, TokenCounter.count(@system_instruction)}` regardless of budget (system prompt is non-negotiable). `@system_instruction` is the same string currently hardcoded in `ContextBuilder` — move it here.
- [ ] T014 [P] [US2] Create `lib/api_harness/agent/context/providers/user_question.ex` — `provide(budget, opts)` always returns `{opts[:question], TokenCounter.count(opts[:question])}`. Budget parameter is accepted but not enforced — the current user question is always included in full per FR-006.
- [ ] T015 [P] [US2] Create `lib/api_harness/agent/context/providers/domain_memory.ex` — `provide(budget, opts)`: call `Memory.list_persistent_memories_by_category(opts[:user_id], "domain")`. Accumulate memories by `content` until `token_count` sum would exceed `budget` (use stored `memory.token_count` if > 0, else `TokenCounter.count(memory.content)`). Return joined content and actual tokens used.
- [ ] T016 [P] [US2] Create `lib/api_harness/agent/context/providers/session_memory.ex` — `provide(budget, opts)`: call `Memory.get_session_memory(opts[:chat_id])`, render as the existing labeled-section format from `ContextBuilder.render_session_memory/1`. Count tokens with `TokenCounter.count/1`. If rendered content exceeds `budget`, emit only the `essential` version (goal + fact categories only, truncated). Return `{content, tokens_used}` or `{"", 0}` if nil.
- [ ] T017 [P] [US2] Create `lib/api_harness/agent/context/providers/persistent_memory.ex` — `provide(budget, opts)`: call `Memory.Retriever.retrieve(opts[:user_id], opts[:question], k: 5, category: nil)`, filter to `user` and `task` categories, accumulate entries within `budget`, return joined content and actual tokens used. On retriever error fall back to `Memory.list_persistent_memories_by_category` for `user` and `task` with same budget enforcement.
- [ ] T018 [US2] Create `lib/api_harness/agent/context/providers/conversation.ex` — `provide(budget, opts)`: fetch `chat = opts[:chat]`. If `chat.rolling_summary` is non-nil, include it first (cost = `chat.rolling_summary_token_count` tokens). With remaining budget, add recent messages from `Chats.list_recent_messages(chat, window)` newest-first until budget exhausted (use stored `msg.token_count` if > 0, else `TokenCounter.count(msg.content)`). Reverse to chronological order. Return formatted message list as a string and total tokens used. This provider is updated in Phase 5 (US4) when compaction introduces rolling summaries — for now, `rolling_summary` will be nil for all threads.
- [ ] T019 [US1] [US2] Create `lib/api_harness/agent/context/runtime.ex` — public function `build(user, chat, question) :: {messages :: [map()], context_metrics :: map()}`. Steps: (1) count question tokens with `TokenCounter.count(question)`; (2) call `BudgetManager.allocate(profile, question_tokens: qt)` → allocation map; (3) call each provider's `provide(budget, opts)` with its allocated budget (opts contains user, chat, question, user_id, chat_id); (4) assemble messages list: `[%{role: "system", content: system_content}] ++ prior_turns ++ [%{role: "user", content: question}]` where `system_content = Enum.join([system, domain, session, memory], "\n")`; (5) sum actual tokens from all providers; (6) assert total ≤ allocation.available_budget (log warning if violated, never raise); (7) return `{messages, %{total_tokens: total, available_budget: N, utilization_percentage: total/N, context_status: chat.context_status, layers: %{...per provider...}}}`.
- [ ] T020 [US1] Modify `lib/api_harness/agent/runtime.ex` — replace `ContextBuilder.build(user, chat, question)` call with `Context.Runtime.build(user, chat, question)` which returns `{messages, context_metrics}`. Update the `with` chain to carry `context_metrics` through: change return value from `{:ok, assistant_msg}` to `{:ok, assistant_msg, context_metrics}`. Update the `@spec` accordingly.

**Checkpoint**: `mix test` passes. In IEx, `Context.Runtime.build(user, chat, "test")` returns a tuple `{messages, metrics}` where `metrics.total_tokens <= metrics.available_budget`. No OpenAI 400 errors from token overflow.

---

## Phase 4: US3 — Pre-Computed Token Accounting (Priority: P2)

**Goal**: `token_count` is populated at persistence time so context assembly uses stored counts, not live tokenization.

**Independent Test** (quickstart.md Scenario 1): Send a message. In IEx, inspect `Repo.get_by(Message, chat_id: chat_id)` — `token_count` is > 0. Same for new persistent memory entries after an interaction.

### Implementation for US3

- [ ] T021 [US3] Modify `lib/api_harness/chats/chats.ex` — in `add_message/3`, compute `tc = ApiHarness.LLM.TokenCounter.count(content)` and set `struct.token_count = tc` on the `%Message{}` struct before `Ecto.Changeset.change/2` or `changeset/2`. `token_count` must NOT appear in `cast/3` — set it directly on the struct. Both `"user"` and `"assistant"` messages get their count set here.
- [ ] T022 [US3] Modify `lib/api_harness/memory/memory.ex` — in `create_persistent_memory/2` and `update_persistent_memory/1` and `merge_persistent_memory/1`, compute `tc = TokenCounter.count(candidate["content"] || pm.content)` and set `struct.token_count = tc` on the `%PersistentMemory{}` struct before building the changeset. `token_count` must NOT appear in `cast/3`.
- [ ] T023 [US3] Create `lib/mix/tasks/api_harness.backfill_token_counts.ex` — Mix task `mix api_harness.backfill_token_counts`; uses `Repo.all(from m in Message, where: m.token_count == 0)` and `Repo.all(from pm in PersistentMemory, where: pm.token_count == 0)` in batches of 100; for each row, calls `TokenCounter.count(row.content)` and issues `Repo.update_all(from x in Schema, where: x.id == ^row.id, update: [set: [token_count: ^tc]])`. Prints progress and final count to stdout.

**Checkpoint**: After running `mix api_harness.backfill_token_counts`, all existing `messages` and `persistent_memories` rows have `token_count > 0`. New messages added via API have `token_count` set immediately.

---

## Phase 5: US4 — Conversation Compaction via Rolling Summary (Priority: P2)

**Goal**: When conversation history exceeds the conversation provider's budget, older messages are summarized into a structured `rolling_summary` stored on the `chats` table. The `ConversationProvider` uses it.

**Independent Test** (quickstart.md Scenarios 5, 8): After compaction, `chat.rolling_summary` is non-nil and contains facts from early turns. The next message sent uses the summary as context prefix.

### Implementation for US4

- [ ] T024 [US4] Create `lib/api_harness/context/compaction/prompt.ex` — single public function `build(messages :: [Message.t()], existing_summary :: String.t() | nil) :: String.t()`. Generates the LLM prompt instructing the model to produce a structured summary in nine sections (Pedido e Intenção Primária, Conceitos Técnicos-Chave, Arquivos e Trechos de Código, Erros e Correções, Resolução de Problemas, Mensagens do Usuário, Tarefas Pendentes, Trabalho Atual, Próximo Passo). When `existing_summary` is non-nil, include it as a "Previous Summary" prefix before the message list. The prompt must instruct the model to preserve all user messages verbatim and to stay within `rolling_summary_max_tokens` (from config, default 8_000).
- [ ] T025 [US4] Create `lib/api_harness/context/compaction/worker.ex` — `GenServer` with `start_link({chat_id, user_id})`. On init: set `chat.context_status = "compacting"` via `Chats.update_context_status/2`. In `handle_continue(:run)`: (1) load all messages for chat via `Chats.list_all_messages(chat_id)` (add this function to `chats.ex`); (2) call `Compaction.Prompt.build(messages, chat.rolling_summary)` to get prompt text; (3) call `ApiHarness.LLM.chat_completion([%{role: "user", content: prompt}], [])` for the summary; (4) on `{:ok, summary}`: count tokens via `TokenCounter.count(summary)`, call `Chats.update_context_metrics(chat_id, %{rolling_summary: summary, rolling_summary_token_count: stc, total_context_tokens: 0, compaction_count: chat.compaction_count + 1, last_compaction_at: DateTime.utc_now()})`, then `Chats.update_context_status(chat_id, "ready")`; (5) on `{:error, _}`: retry up to 3 times with linear backoff (200ms × attempt); after exhaustion log error and revert `context_status` to `"needs_compaction"` (not `"active"`) then stop. Register in `Compaction.Registry` under `{:compaction, chat_id}` to prevent duplicate workers.
- [ ] T026 [US4] Update `lib/api_harness/agent/context/providers/conversation.ex` — no logic change needed if `chat.rolling_summary` is already nil for all current threads (Phase 3 task T018 already reads `chat.rolling_summary`). This task: verify T018's implementation correctly handles a non-nil `chat.rolling_summary` by counting its tokens via `chat.rolling_summary_token_count` (not a live count) and prepending it before recent messages. Write the integration scenario manually in IEx using quickstart.md Scenario 5.

**Checkpoint**: `Context.Compaction.Worker` started via IEx for a thread with messages transitions that thread to `context_status = "ready"` with a non-empty `rolling_summary`. A subsequent `Context.Runtime.build/3` call for that thread includes the summary in the conversation layer.

---

## Phase 6: US5 — Session Lifecycle + Compaction Resilience (Priority: P2)

**Goal**: Sessions are automatically flagged when utilization crosses 70%. Compaction is triggered asynchronously. Application restart re-enqueues interrupted compactions. Messages to compacting sessions return 409.

**Independent Test** (quickstart.md Scenarios 4, 6, 7): `PostResponse.analyze(chat, 85_000)` flags the session. On restart, flagged sessions are discovered and re-enqueued. Sending a message to a `compacting` session returns HTTP 409.

### Implementation for US5

- [ ] T027 [US5] Create `lib/api_harness/context/compaction/supervisor.ex` — wrapper module with `child_spec/1` delegating to `DynamicSupervisor`. The child spec must declare `name: ApiHarness.Context.Compaction.Supervisor`. Export `start_child/1` that calls `DynamicSupervisor.start_child(ApiHarness.Context.Compaction.Supervisor, {Worker, args})`.
- [ ] T028 [P] [US5] Create `lib/api_harness/context/compaction/registry.ex` — wrapper module with `child_spec/1` delegating to `Registry`. Declares `keys: :unique, name: ApiHarness.Context.Compaction.Registry`. Export `lookup/1` and `register/1` helpers used by `Worker` to prevent duplicate compactions.
- [ ] T029 [US5] Create `lib/api_harness/context/compaction/bootstrap.ex` — `enqueue_pending/0`: queries `Repo.all(from c in Chat, where: c.context_status in ["needs_compaction", "compacting"], select: {c.id, c.user_id})`; for each result, calls `Compaction.Supervisor.start_child({chat_id, user_id})` if `Registry.lookup({:compaction, chat_id})` returns `[]` (no worker already running). Logs count of sessions re-enqueued.
- [ ] T030 [US5] Create `lib/api_harness/agent/context/post_response.ex` — `analyze(chat :: Chat.t(), total_tokens :: non_neg_integer()) :: :ok`. Updates `chat.total_context_tokens` via `Chats.update_context_metrics(chat.id, %{total_context_tokens: total_tokens})`. Computes `utilization = total_tokens / BudgetManager.default_profile().available_budget`. If `utilization >= Application.get_env(:api_harness, :context_budget, [])[:compaction_threshold] || 0.70` AND `chat.context_status == "active"`: calls `Chats.update_context_status(chat.id, "needs_compaction")` then `Compaction.Supervisor.start_child({chat.id, chat.user_id})`. Always returns `:ok`.
- [ ] T031 [US5] Modify `lib/api_harness/application.ex` — add `{Registry, keys: :unique, name: ApiHarness.Context.Compaction.Registry}` and `{ApiHarness.Context.Compaction.Supervisor, []}` to the `children` list (before `Endpoint`). After `Supervisor.start_link(children, opts)` returns `{:ok, _}`, spawn `Task.start(fn -> ApiHarness.Context.Compaction.Bootstrap.enqueue_pending() end)` to re-enqueue pending sessions without blocking startup.
- [ ] T032 [US5] Modify `lib/api_harness_web/controllers/message_controller.ex` — in the `create/2` action: (a) after fetching the chat, check `chat.context_status == "compacting"` and return `conn |> put_status(409) |> render(:error, detail: "Session compaction is in progress. Please wait a moment and try again.")` (no LLM call, no message persisted); (b) in `dispatch_pipeline/3`, add a `Task.start/1` call to `Context.PostResponse.analyze(chat, context_metrics.total_tokens)` alongside the existing pipeline dispatches (fire-and-forget).

**Checkpoint** (quickstart.md Scenarios 4, 6, 7): All three validation scenarios pass as described.

---

## Phase 7: US6 — Context Usage Metrics for Frontend (Priority: P3)

**Goal**: Every `POST /api/chats/:id/messages` response includes a `context_metrics` object with per-layer token counts, total usage, utilization percentage, and session lifecycle status.

**Independent Test** (quickstart.md Scenario 2): `curl POST /api/chats/:id/messages | jq '.context_metrics'` returns an object with all fields specified in `contracts/messages.md`. Layer counts sum to `total_tokens` within ±1 token.

### Implementation for US6

- [ ] T033 [US6] Modify `lib/api_harness_web/controllers/message_controller.ex` — update the `create/2` action: (a) `Agent.Runtime.run/3` now returns `{:ok, assistant_msg, context_metrics}` (changed in T020); unpack `context_metrics` from the tuple; (b) pass `context_metrics` to the render call: `render(conn, :show, message: assistant_msg, context_metrics: context_metrics)`.
- [ ] T034 [US6] Modify `lib/api_harness_web/controllers/message_json.ex` — update `show/1` to accept `context_metrics` assign and render it: return `%{message: data(assigns.message), context_metrics: assigns.context_metrics}`. The `context_metrics` map already has the right shape from `Context.Runtime.build/3` (T019) — pass it through directly. Add `data/1` helper if not already present for the `message` struct.

**Checkpoint** (quickstart.md Scenario 2): Full API integration test passes. Response JSON contains `context_metrics` with all fields from `contracts/messages.md`. Verify `layers` values sum to `total_tokens`.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T035 Add `:context_budget` configuration block to `config/config.exs`: `config :api_harness, :context_budget, model: "gpt-4o-mini", context_window: 128_000, output_reserve: 16_384, safety_headroom: 0.02, compaction_threshold: 0.70, rolling_summary_max_tokens: 8_000, provider_proportions: [domain: 0.10, session: 0.05, memory: 0.15, conversation: 0.70]` — these are the defaults; operators can override at runtime.
- [ ] T036 [P] Remove or deprecate `lib/api_harness/agent/context_builder.ex` — `ContextRuntime` replaces it. Add an `@deprecated` module doc if keeping for backwards-compat, or delete the file and verify no remaining references via `mix compile`.
- [ ] T037 [P] Add `Chats.list_all_messages/1` (needed by `Compaction.Worker` T025) to `lib/api_harness/chats/chats.ex` — `list_all_messages(chat_id :: integer()) :: [Message.t()]` ordered by `inserted_at asc`; needed because the compaction worker needs ALL messages, not just the recent window.
- [ ] T038 Run `mix precommit` (compile with warnings-as-errors + unused deps check + format + tests) and fix all issues before merge.
- [ ] T039 Run quickstart.md Scenarios 1–8 manually against the running dev server (`iex -S mix phx.server`) and confirm all pass.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately. T002, T003, T004 are parallel after T001.
- **Phase 2 (Foundational)**: Depends on Phase 1 completion. T007, T008, T009 are parallel after T006.
- **Phase 3 (US1+US2)**: Depends on Phase 2. T013–T017 are parallel after T011–T012. T018 depends on T015–T017 (uses the providers). T019 depends on T013–T018. T020 depends on T019.
- **Phase 4 (US3)**: Depends on Phase 2. Parallel with Phase 3 (different files). T021 and T022 are parallel; T023 depends on both.
- **Phase 5 (US4)**: Depends on Phase 3 (needs `ContextRuntime`, `ConversationProvider`) and Phase 2 (needs `Chat.rolling_summary` schema field).
- **Phase 6 (US5)**: Depends on Phase 5 (needs `Compaction.Worker`) and Phase 3 (needs `PostResponse.analyze` which uses `BudgetManager`).
- **Phase 7 (US6)**: Depends on Phase 3 (T020 returns `context_metrics` tuple) and Phase 6 (T032 dispatch pipeline change shares `message_controller.ex`).
- **Phase 8 (Polish)**: Depends on all story phases complete.

### Parallel Opportunities Within Phases

**Phase 1**: T002, T003, T004 are parallel (different migration files).

**Phase 2**: T007, T008, T009 are parallel (different schema files) after T006.

**Phase 3**: T013, T014, T015, T016, T017 are parallel (different provider files) after T011 + T012.

**Phase 4**: T021, T022 are parallel; T023 follows both.

**Phase 6**: T027, T028 are parallel (different files).

**Phase 8**: T036, T037 are parallel.

---

## Parallel Example: Phase 3 (US1+US2)

```text
# After T011 (behaviour) and T012 (BudgetManager) complete:

Parallel: T013 + T014 + T015 + T016 + T017
  T013 → lib/api_harness/agent/context/providers/system_prompt.ex
  T014 → lib/api_harness/agent/context/providers/user_question.ex
  T015 → lib/api_harness/agent/context/providers/domain_memory.ex
  T016 → lib/api_harness/agent/context/providers/session_memory.ex
  T017 → lib/api_harness/agent/context/providers/persistent_memory.ex

Then: T018 (conversation.ex) → T019 (runtime.ex) → T020 (agent/runtime.ex)
```

---

## Implementation Strategy

### MVP First (US1 + US2 — Budget Enforcement)

1. Complete Phase 1 + Phase 2 (Setup + Foundation — ~8 tasks)
2. Complete Phase 3 (US1+US2 — Budget + Providers + Runtime — ~10 tasks)
3. **STOP and VALIDATE**: No OpenAI token overflow errors. `mix test` passes. `BudgetManager.allocate/1` returns correct sums.
4. **Deploy this increment** — the system is now protected from context overflow.

### Incremental Delivery

1. Setup + Foundational → Core infrastructure ready
2. Phase 3 (US1+US2) → Budget-safe prompts (**primary deliverable**)
3. Phase 4 (US3) → Optimized token counting at persistence time
4. Phase 5 (US4) → Infinite session lifetime via rolling summaries
5. Phase 6 (US5) → Resilient compaction lifecycle
6. Phase 7 (US6) → Frontend visibility into context state
7. Phase 8 → Polish and final validation

---

## Notes

- **Token count fields are system-set**: Never pass `token_count`, `context_status`, or any new context management field through `cast/3`. Set them directly on the struct via `Ecto.Changeset.change(%Schema{}, %{field: value})` or `struct(Schema, field: value)`.
- **tiktoken uses o200k_base for GPT-4o-mini**: If `Tiktoken.count_tokens("gpt-4o-mini", ...)` fails, verify the model string matches what tiktoken recognizes. Fallback is always `ceil(byte_size(text) / 4)`.
- **ConversationProvider ordering**: Return messages in chronological order (oldest first) to match the existing format. List recent messages newest-first for budget selection, then reverse before returning.
- **Compaction worker deduplication**: Always check `Registry.lookup({:compaction, chat_id}) == []` before starting a new worker to avoid racing compactions for the same thread.
- **context_status == "ready" vs "active"**: After compaction, the session transitions to `"ready"`. Subsequent interactions should treat `"ready"` as equivalent to `"active"` for message processing — only `"compacting"` blocks new messages.
- **[P] tasks = different files, no dependency conflicts**
- **Run `mix precommit` after every completed phase** before moving to the next.
