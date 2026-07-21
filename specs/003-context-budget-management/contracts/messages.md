# Contract Delta: Messages Endpoint

This document describes **only the changes** to the existing message endpoint contract established in `specs/001-legal-ai-agent-harness/contracts/messages.md`. All existing request/response fields remain unchanged.

---

## Modified Endpoint: POST /api/chats/:chat_id/messages

### Response — Added Field: `context_metrics`

The response JSON gains a top-level `context_metrics` object alongside the existing `message` field. All fields in `message` are unchanged.

**New response shape**:

```json
{
  "message": {
    "id": 42,
    "role": "assistant",
    "content": "Nos termos do art. 7º, XIV da CLT...",
    "inserted_at": "2026-07-20T14:32:11Z"
  },
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

### `context_metrics` Field Reference

| Field | Type | Always Present | Description |
|-------|------|---------------|-------------|
| `total_tokens` | integer | yes | Total tokens used in the assembled prompt for this interaction |
| `available_budget` | integer | yes | Maximum usable input tokens for this model (window - output_reserve) |
| `utilization_percentage` | float | yes | `total_tokens / available_budget` as a decimal (0.0–1.0). E.g., `0.406` = 40.6% |
| `context_status` | string | yes | Current session lifecycle state: `"active"` \| `"needs_compaction"` \| `"compacting"` \| `"ready"` |
| `layers` | object | yes | Per-provider token count breakdown (see below) |

### `context_metrics.layers` Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `system` | integer | Tokens used by the system instruction |
| `domain_memory` | integer | Tokens used by domain-category persistent memories |
| `session_memory` | integer | Tokens used by the current thread's session memory |
| `persistent_memory` | integer | Tokens used by user + task category persistent memories |
| `conversation` | integer | Tokens used by conversation history (rolling summary + recent messages) |
| `question` | integer | Tokens used by the current user question |

### New Error Response: Session Compacting (409)

When a message is sent to a thread in `compacting` status, the endpoint returns:

```json
HTTP 409 Conflict

{
  "errors": {
    "detail": "Session compaction is in progress. Please wait a moment and try again."
  }
}
```

This response has no `message` or `context_metrics` fields — no AI response is generated when the session is compacting.

---

## Unchanged Endpoints

All other endpoints (`POST /api/sessions`, `GET /api/chats`, `POST /api/chats`, `GET /api/chats/:id`) are unchanged by this feature.
