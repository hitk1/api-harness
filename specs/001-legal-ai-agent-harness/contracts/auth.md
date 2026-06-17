# API Contract: Authentication

All endpoints are JSON (`Content-Type: application/json`) under `/api`. Auth uses JWT Bearer tokens (FR-000, FR-001-A). Tokens do not expire and are revoked by bumping the user's `token_version` (research §1).

---

## POST /api/login

Authenticate with email + password and receive a JWT. This is the **only** unauthenticated endpoint.

**Request**

```json
{
  "email": "advogado@example.com",
  "password": "s3cr3t"
}
```

**Response 200**

```json
{
  "token": "<jwt>",
  "user": { "id": 1, "name": "Eduardo", "email": "advogado@example.com" }
}
```

**Errors**

| Status | When | Body |
|--------|------|------|
| 400 | missing/blank email or password | `{"errors": {"detail": "email and password are required"}}` |
| 401 | unknown email or wrong password (constant-time, no enumeration) | `{"errors": {"detail": "invalid credentials"}}` |

---

## Authentication for protected endpoints

Every endpoint except `POST /api/login` requires:

```
Authorization: Bearer <jwt>
```

The `:authenticate` plug verifies the signature, checks the `token_version` claim against the user's current value, and assigns `conn.assigns.current_user`. User identity is taken **from the token**, never from the request body (FR-001-B).

**Auth failure responses**

| Status | When | Body |
|--------|------|------|
| 401 | missing/malformed Authorization header | `{"errors": {"detail": "unauthenticated"}}` |
| 401 | invalid signature, or `token_version` mismatch (revoked) | `{"errors": {"detail": "unauthenticated"}}` |

---

## Note on user CRUD

User creation/management is performed via the Elixir REPL (FR-001), not via HTTP. There is intentionally **no** `POST /api/users` registration endpoint in scope. Login authenticates users that already exist in the database.
