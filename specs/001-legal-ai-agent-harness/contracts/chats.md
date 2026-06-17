# API Contract: Chat Threads

JSON under `/api`. All endpoints require `Authorization: Bearer <jwt>`. The owning user is always derived from the token (FR-001-B); threads are scoped to `current_user` — a user can only see/operate on their own threads.

---

## POST /api/chats

Create a new chat thread (FR-004). A fresh, empty session memory is initialized for it (FR-015).

**Request**

```json
{ "title": "Ação trabalhista — cliente X" }
```
`title` is optional; if omitted the server may leave it null or derive it later.

**Response 201**

```json
{ "chat": { "id": 42, "title": "Ação trabalhista — cliente X", "inserted_at": "2026-06-16T12:00:00Z" } }
```

---

## GET /api/chats

List the authenticated user's threads (FR-005).

**Response 200**

```json
{
  "chats": [
    { "id": 42, "title": "Ação trabalhista — cliente X", "inserted_at": "2026-06-16T12:00:00Z" },
    { "id": 39, "title": "Divórcio — cliente Y", "inserted_at": "2026-06-15T09:30:00Z" }
  ]
}
```

---

## GET /api/chats/:id

Fetch one thread with its messages (preloaded, ordered chronologically).

**Response 200**

```json
{
  "chat": {
    "id": 42,
    "title": "Ação trabalhista — cliente X",
    "messages": [
      { "id": 100, "role": "user", "content": "Qual o prazo prescricional?", "inserted_at": "..." },
      { "id": 101, "role": "assistant", "content": "O prazo é ...", "inserted_at": "..." }
    ]
  }
}
```

**Errors (all chat endpoints)**

| Status | When | Body |
|--------|------|------|
| 401 | not authenticated | `{"errors": {"detail": "unauthenticated"}}` |
| 404 | thread does not exist **or** belongs to another user | `{"errors": {"detail": "not found"}}` |
