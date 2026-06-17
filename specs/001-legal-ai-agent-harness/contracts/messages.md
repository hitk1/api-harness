# API Contract: Messages (AI Chat)

JSON under `/api`. Requires `Authorization: Bearer <jwt>`. This is the core endpoint that drives the Agent Runtime (FR-008–FR-013). **Synchronous**: the response returns only after `gpt-4o-mini` finishes generating (clarification: synchronous, single JSON payload). The async memory pipeline starts *after* the response is sent and never blocks it (FR-023).

---

## POST /api/chats/:chat_id/messages

Send a user message to a thread and receive the AI response.

**Request**

```json
{ "content": "Faça uma análise de todos os documentos enviados deste contrato." }
```

**Processing (server-side, synchronous portion)**

1. Persist the user message (role `"user"`) under `:chat_id`.
2. `ContextBuilder` assembles the 6-layer prompt: system instruction → domain context → session memory → relevant persistent memory (pgvector top-K) → recent messages (windowed) → current question (FR-022).
3. `Planner` produces a structured plan — single-step (direct answer) or multi-step (FR-010-A).
4. `Executor` runs the plan; parallelizable steps go through the `Coordinator` (`Task.async_stream`, fail-total on any worker error — FR-011).
5. Tools are invoked only via the Tool Registry (FR-012).
6. Persist the AI message (role `"assistant"`).
7. Return the response. **Then** dispatch the async memory pipeline (fire-and-forget).

**Response 200**

```json
{
  "message": {
    "id": 101,
    "role": "assistant",
    "content": "Identifiquei 3 documentos. Resumo: ...",
    "chat_id": 42,
    "inserted_at": "2026-06-16T12:01:30Z"
  }
}
```

**Errors**

| Status | When | Body |
|--------|------|------|
| 400 | empty/blank/malformed `content` | `{"errors": {"detail": "content is required"}}` |
| 401 | not authenticated | `{"errors": {"detail": "unauthenticated"}}` |
| 404 | `chat_id` not found or not owned by the user | `{"errors": {"detail": "not found"}}` |
| 422 | Planner cannot produce a valid plan from the message | `{"errors": {"detail": "could not interpret request"}}` |
| 502 / 503 | OpenAI unavailable or returns an error — **fail fast**, no retry, no fallback (FR-013-A) | `{"errors": {"detail": "ai provider unavailable"}}` |

---

## Asynchronous memory pipeline (post-response, not part of the HTTP contract)

After the 200 is returned, the runtime casts the interaction to a supervised `Pipeline.Worker` (one per interaction, under a named DynamicSupervisor). Stages (FR-023, FR-024):

```
knowledge extraction → memory classification → reconciliation → persistence
```

- Runs off the request path; the client never waits (SC-002).
- N concurrent users → N independent workers, no cross-blocking, no message loss (FR-024, SC-003).
- On stage failure: retry 2–3 times, then log & discard; no dead-letter; failure never surfaces to the user (FR-024-A).
- Session memory (this thread) and persistent memory (this user, reconciled — create/update/merge/discard) are updated; each change writes a `memory_context_update` audit row.

This behavior is observable only via database state (eventual consistency) and logs — it has no synchronous HTTP surface.
