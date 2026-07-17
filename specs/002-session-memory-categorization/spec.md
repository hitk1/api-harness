# Feature Specification: Categorized Session Memory

**Feature Branch**: `002-session-memory-categorization`

**Created**: 2026-07-14

**Status**: Draft

**Input**: User description (pt-BR): a refactor of the existing post-response session-memory update flow. Today, every user/AI turn only overwrites two fixed fields ("last_question", "last_answer") in the thread's session memory — nothing older is retained. Session memory should instead work similarly to persistent memory: it should be organized into meaningful categories that help the AI model understand the current thread's actual objective, not just store the most recent exchanged message.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Thread-Aware Context Continuity (Priority: P1)

As a user having an extended conversation within a chat thread, I want the AI to remember and use everything relevant we've discussed in this thread so far — not just my most recent message — so that its responses stay coherent with the full context of my current legal matter, even many turns into the conversation.

**Why this priority**: This is the core problem being fixed. Today, only the immediately preceding question/answer pair is retained; everything discussed earlier in the thread is effectively lost from session memory. This is the direct value the refactor must deliver.

**Independent Test**: Send a sequence of 4+ messages within a single thread where facts introduced in early turns (e.g., client name, case type) are needed to correctly answer a later turn that does not repeat them. Verify the AI response correctly reflects those earlier facts.

**Acceptance Scenarios**:

1. **Given** a user has exchanged several messages in a thread establishing case facts (e.g., client name, contract type), **When** the user asks a follow-up question later in the same thread without repeating those facts, **Then** the AI response reflects awareness of those earlier facts.
2. **Given** a user sends a new message, **When** the AI response is generated and returned, **Then** session memory is updated to reflect the new turn's relevant information in addition to — not instead of — previously retained context.
3. **Given** the current behavior only retains the immediately preceding question and answer, **When** this feature is delivered, **Then** information from turns older than the immediately preceding one continues to be reflected in session memory as long as it remains relevant to the thread.

---

### User Story 2 - Categorized Session Memory (Priority: P2)

As a user working through a legal matter within a thread, I want the information the AI retains about the current thread to be organized into distinct categories (goal, fact, constraint, preference) — mirroring the way persistent memory is already organized — so the AI can reason about what the thread's current objective is versus what is just background fact or a stated constraint.

**Why this priority**: Categorization is what makes retained context usable and interpretable, both for the AI (reasoning about "what is this thread trying to accomplish") and for consistency with the existing persistent-memory design. Depends on the retention fix in User Story 1 already being in place.

**Independent Test**: Inspect the stored session memory after a multi-turn conversation and verify it is structured into the defined categories, with each item classified consistently with the conversation content.

**Acceptance Scenarios**:

1. **Given** a user's message reveals a new goal for the thread (e.g., "I need to know the statute of limitations for this case"), **When** that turn is processed, **Then** the extracted goal is stored under the goal category of session memory.
2. **Given** a user's message reveals a fact about the case (e.g., client name, contract value), **When** that turn is processed, **Then** the fact is stored under the fact category of session memory, separate from goals or constraints.
3. **Given** a user's message reveals a constraint or preference for how they want to be helped in this thread, **When** that turn is processed, **Then** it is stored under the corresponding constraint or preference category rather than mixed in with facts.

---

### User Story 3 - Reconciled Updates Without Duplication (Priority: P2)

As a user continuing a conversation over many turns, I want updates to information already captured in session memory (e.g., a case detail that changes or is refined) to update or merge with the existing entry rather than piling up as duplicate or contradictory entries, so the AI is not confused by stale or conflicting information later in the thread.

**Why this priority**: Without reconciliation, categorized session memory would simply accumulate noise over a long thread, defeating the purpose of organizing it. Builds directly on User Story 2.

**Independent Test**: Send a message establishing a fact, then a later message in the same thread that revises or contradicts that fact. Verify session memory reflects the updated fact rather than both the old and new versions as separate duplicate entries.

**Acceptance Scenarios**:

1. **Given** session memory already holds an entry for the current thread, **When** a later turn produces new information that refines or updates that same entry, **Then** the existing entry is updated or merged, not duplicated.
2. **Given** a later turn produces information clearly unrelated to any existing categorized entry, **When** it is processed, **Then** a new entry is created for it.
3. **Given** a later turn produces information judged not meaningfully useful to retain (e.g., small talk, redundant restatement), **When** it is processed, **Then** no new session memory entry is created for it.

---

### User Story 4 - Non-Blocking Updates (Priority: P3)

As a user sending a message in a chat thread, I want to receive the AI's response without waiting for the session-memory categorization and reconciliation work to finish, so richer memory tracking never adds latency to the conversation.

**Why this priority**: A quality/performance requirement layered on top of User Stories 1-3; categorization must not degrade response time relative to today's simpler approach.

**Independent Test**: Send a message and verify the AI response is returned before the categorized session-memory update for that turn is guaranteed to have completed; then confirm the updated session memory appears shortly after (eventual consistency).

**Acceptance Scenarios**:

1. **Given** a user sends a message, **When** the AI generates and returns its response, **Then** the categorized session-memory update is not on the critical path of the response and does not delay it.
2. **Given** the categorized session-memory update is running for a thread, **When** another message arrives in a different thread, **Then** its own update proceeds independently without being blocked by the first.
3. **Given** the categorized session-memory update encounters a failure, **When** this occurs, **Then** it does not surface as an error to the user and the prior session memory state remains available for the next turn.

---

### Edge Cases

- What happens when a large number of distinct categorized entries accumulate in a single very long-running thread — is there a limit or pruning strategy?
- What happens when new information directly contradicts a previously stored session memory entry (e.g., a corrected client name or case value)?
- What happens when a turn produces no extractable information relevant to any category (e.g., a purely conversational turn)?
- What happens when a user switches to a different thread — per-thread categorization must remain fully isolated (existing thread-isolation guarantee must be preserved).
- What happens when the categorization/reconciliation step itself fails or times out for a given turn — the prior session memory must remain intact and usable for the next turn.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST update session memory after each AI response using the extracted, categorized content of that turn — not merely the raw last question and answer text.
- **FR-002**: Session memory MUST organize retained thread information into distinct categories — goal, fact, constraint, preference — mirroring the categorization already used for persistent memory, scoped strictly to the current thread.
- **FR-003**: When a turn produces new information for a category, the system MUST reconcile it against existing session-memory entries in that category — deciding to create a new entry, update an existing one, merge with an existing one, or discard it — rather than blindly overwriting the entire session memory state each turn.
- **FR-004**: Session memory categorization MUST remain scoped strictly to its originating chat thread; it MUST NOT be shared, merged, or carried over when a user switches to or creates a different thread.
- **FR-005**: The categorized session memory MUST continue to be included in LLM context construction for subsequent turns in the same thread, so responses are grounded in the accumulated, categorized thread context rather than only the immediately preceding turn.
- **FR-006**: The session-memory categorization and reconciliation process MUST run without blocking or delaying the AI response returned to the user for the current turn.
- **FR-007**: If the session-memory categorization/reconciliation process fails for a given turn, the failure MUST NOT surface to the user, and the session memory state from before that turn MUST remain available and unaffected for subsequent turns.
- **FR-008**: The system MUST discard turn-extracted information that is judged not meaningfully useful to retain for the thread's context (e.g., small talk) rather than storing it as a session memory entry.

### Key Entities

- **Session Memory (revised)**: Per-thread structured state, organized into named categories (goal, fact, constraint, preference) rather than a single last-question/last-answer pair. Each category holds one or more entries relevant to the active thread. Reconciled turn-by-turn rather than overwritten wholesale.
- **Turn Extraction**: The categorized information produced from a single conversational turn (a user message plus its AI response), destined for reconciliation into session memory.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a multi-turn conversation, a follow-up question that depends on facts established earlier in the same thread (not just the prior turn) receives a correct, context-aware response.
- **SC-002**: Inspecting session memory for an active thread shows information organized into distinct categories rather than a single undifferentiated last-question/last-answer field.
- **SC-003**: When a thread revisits or refines previously captured information, the number of stored entries for that category does not grow with duplicates — existing entries are updated or merged.
- **SC-004**: AI response time for a message is not measurably increased by the categorized session-memory update process.
- **SC-005**: Each chat thread's categorized session memory remains fully isolated from every other thread — switching threads never exposes another thread's session memory.
- **SC-006**: When the categorization/reconciliation process fails for a turn, the user still receives a normal AI response and no error is surfaced related to memory processing.

## Clarifications

### Session 2026-07-14

- Q: How should categorized session memory organize information extracted from each turn? → A: Reuse persistent memory's kind taxonomy — goal / fact / constraint / preference — applied at thread scope instead of user scope.
- Q: How should new turn-extracted information be reconciled against existing categorized session memory? → A: LLM-based reconciliation, following the same create/update/merge/discard decision model already used by the persistent-memory Reconciler.
- Q: Should the categorized session-memory update run synchronously or move to an async post-response pipeline? → A: Asynchronous, consistent with the existing persistent-memory pipeline's timing (non-blocking). The user additionally directed that, unlike persistent memory's dynamic-supervisor-spawned worker, this flow should use a dedicated long-lived process per thread — noted below as planning-phase context rather than a spec-level requirement, since it is an implementation approach, not a business requirement.

## Assumptions

- This is a refactor of the existing session-memory update flow (session memory state maintained per chat thread, per FR-014/FR-015 of the legal AI agent harness feature) — it replaces the "last_question/last_answer" state shape with categorized content; it does not introduce a new memory concept alongside session memory.
- Session memory's four categories (goal, fact, constraint, preference) reuse the same taxonomy already defined for persistent memory, applied at thread scope rather than user scope, per explicit user direction to mirror persistent memory's design.
- Reconciliation of session-memory entries follows the same create/update/merge/discard decision model as the existing persistent-memory reconciliation logic, rather than a simpler last-write-wins merge, per explicit user choice.
- The categorization/reconciliation update runs asynchronously after the response is delivered, consistent with the existing persistent-memory pipeline's non-blocking timing.
- Per user direction, the async execution mechanism for this flow is expected to use a dedicated long-lived process per thread rather than a dynamic-supervisor-spawned worker (the user intends to migrate persistent memory's pipeline to this same pattern in the future). This is context for the planning phase, not a spec-level functional requirement.
- Persistent memory's own reconciliation, audit trail, and cross-session retrieval mechanisms are unaffected by this refactor — this feature only changes how session memory (per-thread state) is populated and organized.
- No new user-facing API or endpoint changes are required; this refactor changes internal memory update/reconciliation behavior only, without altering the request/response contract of the message-processing endpoint.
