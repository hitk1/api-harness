# Feature Specification: Legal AI Agent Harness

**Feature Branch**: `001-legal-ai-agent-harness`

**Created**: 2026-06-16

**Status**: Draft

**Input**: Product requirements document — Phoenix 1.8 JSON API backend implementing an intelligent legal-domain chat agent with user management, session/thread management, AI-powered message processing through a structured agent runtime (planner, executor, coordinator, tool registry, memory system), and an asynchronous memory update pipeline.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - User Registration and Management (Priority: P1)

As a system operator, I want to create and manage users via the Elixir REPL so that I can onboard users without requiring a separate admin interface or HTTP client.

**Why this priority**: All other features require a user to exist. User management is the foundational prerequisite and must be available before any chat or AI interaction can be tested.

**Independent Test**: Can be fully tested by opening an IEx session and calling context module functions directly — create, read, update, and delete a user — then verifying persistence in the database. No HTTP endpoint required.

**Acceptance Scenarios**:

1. **Given** the Elixir REPL is open, **When** I call the user creation function with valid attributes, **Then** a new user record is persisted in the database and the created user struct is returned.
2. **Given** one or more users exist in the database, **When** I call the user listing function, **Then** all users are returned.
3. **Given** a user exists in the database, **When** I call the update function with new attributes, **Then** the record is updated and the updated struct is returned.
4. **Given** a user exists in the database, **When** I call the deletion function, **Then** the user is removed from the database.
5. **Given** a duplicate email is provided, **When** I call the creation function, **Then** an error is returned and no duplicate record is created.

---

### User Story 2 - Chat Thread Management (Priority: P2)

As a user, I want to create and switch between chat threads so that I can maintain separate conversations for different legal topics or cases.

**Why this priority**: Threads are a prerequisite for the message-processing flow. A user must be able to select or create a thread before sending messages. Without threads there is no context boundary between conversations.

**Independent Test**: Can be fully tested by creating a thread via the API and verifying it persists in the database with the correct user association. The thread lifecycle (create, list, select) works independently of any AI response.

**Acceptance Scenarios**:

1. **Given** a user exists, **When** they request to create a new chat thread, **Then** a new thread is created, persisted, and its identifier is returned.
2. **Given** a user has multiple chat threads, **When** they request the list of their threads, **Then** all their threads are returned with identifying metadata.
3. **Given** a user selects an existing thread and sends a message, **Then** the message is associated with that specific thread in the database.
4. **Given** a user switches to a different thread, **Then** a fresh session memory context is initialized for that thread (the previous thread's session memory is not carried over).

---

### User Story 3 - AI-Powered Legal Chat (Priority: P1)

As a user, I want to send a message in a chat thread and receive an AI-generated response grounded in the legal domain so that I can get help with my legal documents and questions.

**Why this priority**: This is the core value proposition of the entire application. All other stories either enable this one (US1, US2) or enhance it (US4, US5).

**Independent Test**: Can be tested by sending a POST request to the message endpoint with a valid thread ID and message text, and verifying the API returns a structured AI response. Initial validation can use a simplified context (no memory retrieval) to confirm the end-to-end request/response pipeline.

**Acceptance Scenarios**:

1. **Given** a user has an active chat thread, **When** they send a message via the API, **Then** the agent runtime processes the request and returns an AI-generated response.
2. **Given** a user sends a message, **When** the agent planner analyzes it, **Then** the planner produces a structured action plan before the executor begins any action (planning and execution are sequential and separated).
3. **Given** a complex request requiring multiple data sources (e.g., "analyze all documents in this contract"), **When** the coordinator distributes the work, **Then** multiple workers process inputs in parallel and their results are combined before the response is assembled.
4. **Given** an AI response is generated, **When** it is returned to the user, **Then** the message and the AI response are both persisted in the database under the correct thread.
5. **Given** a message is sent, **When** the LLM context is constructed, **Then** it contains exactly: system instruction → domain context → session memory → relevant persistent memory (retrieved by relevance, not a full dump) → recent messages → current user question.

---

### User Story 4 - Intelligent Memory System (Priority: P2)

As a user, I want the system to remember relevant facts and knowledge extracted from my interactions so that future responses are more informed and personalized to my legal work context.

**Why this priority**: Memory transforms a stateless chatbot into an intelligent agent. Session memory provides coherence within a thread; persistent memory improves response quality across sessions by retaining durable knowledge.

**Independent Test**: Can be tested by sending a sequence of messages within a thread and verifying that session memory reflects extracted facts (e.g., case details, client names). Persistent memory can be verified by starting a new thread and confirming that relevant prior knowledge is available for context retrieval.

**Acceptance Scenarios**:

1. **Given** a user is interacting within a chat thread, **When** the AI extracts relevant facts (e.g., contract value, client name, case type), **Then** those facts are stored as session memory in structured JSON format scoped to that thread.
2. **Given** a user switches to a new thread, **When** the new session begins, **Then** a fresh session memory is initialized — the previous thread's session memory is not accessible in the new thread.
3. **Given** persistent knowledge exists for a user, **When** a new interaction begins, **Then** only knowledge relevant to the current task is retrieved (irrelevant memory categories are excluded).
4. **Given** new interactions produce knowledge that overlaps with existing persistent memory, **When** the reconciler evaluates it, **Then** the existing memory record is updated or merged — a duplicate record is NOT created.
5. **Given** the reconciler evaluates extracted knowledge, **When** the knowledge is assessed as not durable (unlikely to be useful in 30 or more days), **Then** it is discarded rather than persisted.
6. **Given** the knowledge extraction runs after an interaction, **When** structured knowledge is produced (JSON with preferences, goals, constraints, and facts), **Then** it is passed to the reconciler before any persistence decision is made.

---

### User Story 5 - Asynchronous Memory Update Pipeline (Priority: P3)

As a system operator, I want the memory extraction and persistence process to run in the background after every AI response so that user experience is never blocked by memory operations, even under high concurrency.

**Why this priority**: This is a non-functional quality requirement over the memory system. It requires the memory system (US4) to be in place first. Its absence would not prevent the system from working, but its presence is required for production-readiness.

**Independent Test**: Can be tested by sending a message and verifying the API responds before memory update operations complete, then confirming that updated memory records appear in the database shortly after (eventual consistency). Under concurrent load, multiple users' pipelines must operate independently without one blocking another.

**Acceptance Scenarios**:

1. **Given** an AI response is generated, **When** it is returned to the user, **Then** the memory extraction and persistence pipeline starts after the response is sent — the user never waits for memory operations.
2. **Given** N users are simultaneously sending messages, **When** memory pipelines are triggered for all N, **Then** each pipeline operates independently with no message loss and no pipeline blocks another.
3. **Given** the memory pipeline processes a response, **When** knowledge is extracted, **Then** it passes through the following stages in order: knowledge extraction → memory classification → reconciliation → persistence.
4. **Given** the memory pipeline encounters a failure after the response was already delivered, **When** the failure occurs, **Then** it does not surface as an error to the user (failure handling is internal to the pipeline).

---

### Edge Cases

- When the OpenAI API is unavailable or returns an error, the system MUST fail fast: return an HTTP 502/503 with a structured JSON error body. No retries and no fallback response are performed.
- When the Planner cannot determine a valid action plan from the user's message, the endpoint MUST return HTTP 422 with a structured JSON error asking the user to rephrase. No assistant response is persisted for that attempt.
- When a Coordinator worker fails during parallel execution, the entire request MUST fail with a structured error response. Partial results MUST NOT be returned to the user.
- What happens when memory reconciliation must choose between two equally plausible updates to the same knowledge record?
- When the async memory pipeline fails after the response is already delivered, it MUST retry a limited number of times (2–3 attempts). If all attempts fail, the failure MUST be logged and the extracted knowledge discarded — there is no persistent dead-letter queue. The failure MUST NOT surface to the user.
- What happens when session memory grows excessively large within a single long-running thread?
- What happens when a user sends an empty or malformed message?
- What happens when a user provides an invalid or non-existent thread ID in a message request?
- What happens when persistent memory extraction repeatedly classifies the same knowledge as "non-durable" — should there be a signal that knowledge is never retained?

---

## Requirements *(mandatory)*

### Functional Requirements

#### Authentication

- **FR-000**: System MUST issue a JWT Bearer Token upon successful login (credentials: email + password).
- **FR-000-A**: Issued JWT tokens MUST have no expiration date — they remain valid until explicitly revoked. No refresh token mechanism is required.
- **FR-001-A**: All API endpoints — except the login endpoint — MUST require a valid JWT Bearer Token in the `Authorization` header.
- **FR-001-B**: User identity on protected endpoints MUST be derived from the validated token, not from fields in the request payload.

#### User Management

- **FR-001**: System MUST expose a user management context module with CRUD operations (create, read, update, delete) that are fully callable from the Elixir REPL without an HTTP client.
- **FR-002**: System MUST persist user records to the PostgreSQL users table.
- **FR-003**: System MUST prevent creation of users with duplicate email addresses.

#### Chat Thread Management

- **FR-004**: System MUST allow users to create new chat threads.
- **FR-005**: System MUST expose a way to list a user's existing chat threads.
- **FR-006**: System MUST associate every message with a specific chat thread.
- **FR-007**: System MUST expose a chat/thread management module (analogous in structure to the user management module — operable programmatically). Canonical terminology: "Chat"/"Thread" refers to a conversation; "Session Memory" refers only to the per-thread JSON state defined in FR-014 (the two are distinct concepts).

#### AI Message Processing

- **FR-008**: System MUST expose a synchronous API endpoint that receives a user message and returns the complete AI-generated response as a single JSON payload after the model finishes generating. Streaming and async polling are out of scope.
- **FR-009**: System MUST implement an Agent Runtime as the central orchestration layer, responsible for: reasoning loops, tool coordination, memory updates, context construction, and multi-agent orchestration when required.
- **FR-010**: Planning MUST be separated from execution: a Planner module MUST analyze the user's request and produce a structured action plan; only after the plan is produced does the Executor module begin acting on it.
- **FR-010-A**: The Planner MUST run on every message. It MAY emit a single-step plan (a direct answer for simple questions) or a multi-step plan (for complex tasks). The runtime path MUST be uniform — there is no separate code branch that bypasses the Planner.
- **FR-010-B**: If the Planner cannot produce a valid action plan from the user's message, the endpoint MUST return HTTP 422 with a structured JSON error asking the user to rephrase. No assistant response is persisted for that attempt.
- **FR-011**: System MUST implement a Coordinator capable of distributing work across multiple Workers executing in parallel. If any Worker fails, the Coordinator MUST abort all remaining Workers and propagate a structured error — partial results MUST NOT be returned.
- **FR-012**: System MUST implement a Tool Registry through which all agent actions are performed (e.g., read document, write document, search entities, generate report, execute workflow). No agent action may occur outside a registered tool.
- **FR-013**: System MUST persist all messages — both user messages and AI responses — to the PostgreSQL messages table, associated with the correct thread.
- **FR-013-A**: When the OpenAI API is unavailable or returns an error, the endpoint MUST respond with HTTP 502 or 503 and a structured JSON error body. The system MUST NOT retry automatically and MUST NOT return a fallback AI response.

#### Memory System

- **FR-014**: System MUST maintain session memory per chat thread, stored as structured JSON, representing the current task state (insights, facts, notes about the active case or document).
- **FR-015**: A new session memory context MUST be initialized each time a user starts or switches to a different chat thread; session memory from one thread MUST NOT carry over to another.
- **FR-016**: System MUST maintain persistent memory per user, organized into three categories: (1) user preferences and perceived behaviors, (2) task/project knowledge (context-specific knowledge about an ongoing case or project), (3) domain knowledge (legal area specializations and working style observed across interactions).
- **FR-017**: Persistent memory MUST NOT use an append-only approach. When new interactions produce knowledge that overlaps with existing records, the system MUST update or merge existing records — not append duplicates.
- **FR-018**: System MUST implement a Knowledge Extraction process that runs after each interaction, producing structured JSON knowledge containing extracted preferences, goals, constraints, and facts.
- **FR-019**: System MUST implement a Memory Reconciler that receives extracted knowledge and decides for each item whether to: create a new memory record, update an existing one, merge with an existing one, or discard it.
- **FR-020**: Memory retrieval for LLM context construction MUST be relevance-based: the system MUST understand the current task context and retrieve only memories relevant to it, not all stored memories for the user.
- **FR-021**: System MUST persist memory state changes to a memory context update table in PostgreSQL.

#### Context Builder

- **FR-022**: System MUST construct each LLM prompt using the following ordered structure: (1) system instruction, (2) domain context, (3) session memory, (4) relevant persistent memory, (5) recent conversation messages, (6) current user question.
- **FR-022-A**: Layers 2 and 4 MUST be partitioned by persistent-memory category to avoid duplication: layer 2 (domain context) draws **only** from the user's `domain`-category persistent memories (retrieved by relevance); layer 4 (relevant persistent memory) draws **only** from the `user` and `task` categories. No memory category may appear in both layers.

#### Asynchronous Memory Pipeline

- **FR-023**: The memory extraction and persistence pipeline MUST execute asynchronously — it MUST start after the AI response is delivered and MUST NOT block or delay the user-facing response.
- **FR-024**: The async pipeline MUST support N concurrent users, each with their own independent pipeline process, with no message loss between pipeline stages.
- **FR-024-A**: If a stage of the async memory pipeline fails, the system MUST retry a limited number of times (2–3 attempts). After exhausting retries, it MUST log the failure and discard the extracted knowledge for that interaction. No persistent dead-letter queue is required, and the failure MUST NOT surface to the user.

#### Configuration

- **FR-025**: System MUST load all configuration (database connection strings, LLM API keys, and any other secrets) from a `.env` file.
- **FR-026**: System MUST integrate with the OpenAI API. The model to use is GPT-4o mini.

#### Data Persistence

- **FR-027**: System MUST include a file metadata table in PostgreSQL as a structural placeholder representing user-uploaded documents. Document upload and ingestion are explicitly out of scope for this study project.

### Key Entities

- **User**: Represents a system operator or end user. Has identity attributes (e.g., name, email). Linked to chat threads and persistent memory records.
- **Chat (Thread)**: A conversation thread belonging to a user. Contains an ordered set of messages and one associated session memory record. A user may have many threads.
- **Message**: A single conversational turn — either a user message or an AI response. Belongs to exactly one chat thread. Has content and a timestamp.
- **Session Memory**: Structured JSON capturing the current task state within a single chat thread. Scoped to one thread's lifetime. Holds extracted insights, facts, and notes (e.g., active contract value, client name, current case phase).
- **Persistent Memory**: Durable knowledge records linked to a user. Organized into three categories (user memory, task/project knowledge, domain knowledge). Managed through the reconciliation pipeline — not an append-only log.
- **Memory Context Update**: A record of memory state changes produced by the reconciliation pipeline. Supports auditing and reconstruction of memory evolution.
- **File Metadata** *(placeholder)*: A structural table representing metadata about user-uploaded documents. Upload and ingestion logic is out of scope.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can send a message and receive an AI-generated legal domain response within a complete request-response cycle.
- **SC-002**: The AI response is delivered to the user before any memory extraction or persistence operations begin (memory pipeline is provably non-blocking).
- **SC-003**: Multiple concurrent users can send messages simultaneously and each user's memory pipeline operates independently — no user's pipeline blocks or interferes with another's.
- **SC-004**: Session memory for a thread correctly reflects facts extracted from that thread's conversation (e.g., case type, client name, relevant dates).
- **SC-005**: When new interactions produce knowledge overlapping with existing persistent memory, the memory record count does not grow — existing records are updated or merged.
- **SC-006**: Memory retrieval for LLM context assembly returns only knowledge relevant to the current user question, excluding unrelated memory categories.
- **SC-007**: All user CRUD operations are fully executable from the Elixir REPL with no HTTP client required.
- **SC-008**: A user with multiple chat threads can switch between them, and each thread maintains its own independent session memory without cross-contamination.
- **SC-009**: LLM prompts are consistently constructed with all six ordered layers (system instruction, domain context, session memory, relevant persistent memory, recent messages, current question).

---

## Clarifications

### Session 2026-06-16

- Q: How should the API deliver the AI-generated response to the client — synchronously, streaming, or async polling? → A: Synchronous — the endpoint awaits the complete model response and returns a single JSON payload.
- Q: What should the API do when the OpenAI API is unavailable or returns an error? → A: Fail fast — return a structured JSON error with HTTP 502/503; no retries, no fallback response.
- Q: What is the JWT token lifetime and refresh strategy? → A: No expiration — tokens are valid until explicitly revoked; no refresh token mechanism required.
- Q: When a Coordinator worker fails during parallel execution, should the whole request fail or should partial results be returned? → A: Fail total — if any worker fails, the entire request fails with a structured error; no partial results are returned.
- Q: Does the Planner run on every message, or only on requests that need multiple steps? → A: Planner always runs; it may emit a single-step plan (direct answer) or a multi-step plan. The runtime path is uniform.
- Q: When the async memory pipeline fails (after the response was delivered), what happens to the extracted knowledge? → A: Limited retry (2–3 attempts), then log and discard. No persistent dead-letter queue.
- Q: What should happen when the Planner cannot determine a valid action plan from the user's message? → A: Return HTTP 422 with a structured error asking the user to rephrase; nothing is persisted as an assistant response.
- Q: How is prompt layer 2 (domain context) sourced vs layer 4 (relevant persistent memory), given both could include domain knowledge? → A: Partition by category — layer 2 = the user's `domain`-category persistent memories (relevance-retrieved); layer 4 = only `user` + `task` categories. No category appears in both layers.
- Q: How should the overloaded term "session" be normalized? → A: Canonical terms are "Chat"/"Thread" for conversations and "Session Memory" only for the per-thread JSON state. FR-007 reworded to "chat/thread management module".

---

## Assumptions

- **Authentication**: API endpoints require authentication via JWT Bearer Token. The system must issue tokens upon login and validate them on protected endpoints. User identity is derived from the authenticated token — it is not passed as a raw field in the request payload.
- **Document ingestion is out of scope**: The requirements reference answering questions about "documents the user uploaded" but document upload is not listed as a feature. The file metadata table is explicitly described in the requirements as "fictional" (`tabela fictícia`). Document upload and ingestion are treated as out of scope; the table is a structural placeholder only.
- **LLM model identifier**: "GPT 4.0 mini" in the requirements document is interpreted as the `gpt-4o-mini` model identifier in the OpenAI API.
- **Tool implementations are stubs**: The tool registry architecture is required, but the specific tools (read document, search entities, generate report, etc.) are not fully specified. Concrete tool implementations will be defined during planning.
- **Recent messages window**: The number of recent messages included in the LLM context is not specified in the requirements. A reasonable default will be determined during planning.
- **Memory durable-knowledge threshold**: The requirements state that knowledge should only be persisted if it will be useful "30 days or more" from now. The exact evaluation logic for this threshold is not specified and will be designed during planning.
- **Parallelism mechanism**: The requirements mention parallel worker execution and a scalable async pipeline. The specific concurrency primitives are implementation decisions deferred to planning.
