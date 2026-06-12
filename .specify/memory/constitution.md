<!--
SYNC IMPACT REPORT
==================
Version change: template (unpopulated) → 1.0.0
Bump rationale: Initial ratification — all placeholder tokens replaced for the first time.

Modified principles: none (first population)
Added sections:
  - Core Principles (5 principles)
  - Phoenix v1.8 Constraints
  - Development Workflow
  - Governance

Removed sections: none

Templates requiring updates:
  ✅ .specify/templates/plan-template.md
     Constitution Check gate already present; gates now derivable from this document.
  ✅ .specify/templates/spec-template.md — no constitution-specific changes required; valid as-is.
  ✅ .specify/templates/tasks-template.md — task categories align with principles; valid as-is.
  ✅ No .specify/templates/commands/ subdirectory exists — nothing to audit.
  ✅ README.md — generic Phoenix scaffold; no references to principles.

Deferred TODOs: none — all fields resolved from repo context.
==================
-->

# ApiHarness Constitution

## Core Principles

### I. API-First Design

All application endpoints MUST live under the `/api` scope and be served through the `:api`
pipeline (`plug :accepts, ["json"]`). There MUST be no browser pipeline, no HTML views
(except `ErrorJSON`), no LiveView, and no frontend asset pipeline in this project.
JSON is the only accepted response format.

### II. Prescribed Tooling

Dependencies for common tasks are fixed and MUST NOT be swapped for alternatives:

- **HTTP client**: `Req` only. `:httpoison`, `:tesla`, and `:httpc` are FORBIDDEN.
- **HTTP server**: `Bandit` (not Cowboy).
- **JSON**: `Jason`.
- **Email**: `Swoosh`.
- **Persistence**: `Ecto` + `postgrex` (PostgreSQL).
- **Date/time**: Elixir standard library (`Date`, `Time`, `DateTime`, `Calendar`).
  `date_time_parser` is permitted only for parsing external date strings.
  No other date/time dependency MUST be added.

### III. Elixir Idioms (NON-NEGOTIABLE)

The following rules MUST be enforced on every code review:

- List index access via `[]` is FORBIDDEN — use `Enum.at/2`, pattern matching, or `List`.
- Results of block expressions (`if`, `case`, `cond`) MUST be bound to a variable at the
  call site; rebinding inside the block has no effect outside it.
- Multiple modules in the same file are FORBIDDEN (cyclic dependency risk).
- Struct fields MUST be accessed via dot notation or `Ecto.Changeset.get_field/2`;
  map-access syntax (`struct[:field]`) on structs is FORBIDDEN.
- `String.to_atom/1` MUST NOT be called on user-supplied input (memory leak).
- Predicate function names MUST end with `?`; the `is_` prefix is reserved for guards.
- OTP primitives (`DynamicSupervisor`, `Registry`) MUST declare a `:name` in their child spec.
- Concurrent enumeration MUST use `Task.async_stream/3` with `timeout: :infinity`.

### IV. Data Integrity

- Programmatically-set fields (e.g. `user_id`) MUST NOT appear in `cast/3` calls;
  they MUST be set explicitly on the struct.
- Ecto associations MUST be preloaded in queries whenever they are accessed downstream
  (serializers, business logic).
- Changeset field values MUST be read via `Ecto.Changeset.get_field/2`, never `changeset[:field]`.
- Migrations MUST be generated with `mix ecto.gen.migration <name_with_underscores>`
  to guarantee correct timestamps and naming conventions.
- Schema fields MUST use the `:string` type even for `:text` database columns.
- `Ecto.Changeset.validate_number/2` does NOT support `:allow_nil`; that option MUST NOT be used.

### V. Test Discipline

- Processes started in tests MUST use `start_supervised!/1` to guarantee cleanup.
- `Process.sleep/1` and `Process.alive?/1` are FORBIDDEN in tests.
- Waiting for a process to terminate MUST use `Process.monitor/1` + `assert_receive`:
  `ref = Process.monitor(pid); assert_receive {:DOWN, ^ref, :process, ^pid, :normal}`
- Synchronizing before the next call MUST use `_ = :sys.get_state(pid)`.

## Phoenix v1.8 Constraints

- LiveView templates MUST begin with `<Layouts.app flash={@flash} ...>` wrapping all inner
  content. `ApiHarnessWeb.Layouts` is aliased in `api_harness_web.ex` — no extra alias needed.
- `<.flash_group>` MUST only be called inside `layouts.ex`; calling it elsewhere is FORBIDDEN.
- Icons MUST use the `<.icon name="hero-..." />` component from `core_components.ex`.
  Direct use of `Heroicons` modules is FORBIDDEN.
- Form inputs MUST use the `<.input>` component from `core_components.ex`.
  When overriding `class=`, no defaults are inherited — custom classes must fully style the input.
- A missing `current_scope` assign MUST be fixed by moving routes to the correct `live_session`
  and passing `current_scope` appropriately. Workarounds are FORBIDDEN.
- Router `scope` blocks provide an implicit alias for all nested route modules.
  Manual `alias` declarations for those modules inside a scope are FORBIDDEN.
- `Phoenix.View` does not exist in Phoenix 1.8 and MUST NOT be used.

## Development Workflow

- `mix precommit` MUST run and pass (zero compiler warnings, no unused deps, formatted code,
  all tests green) before any commit is pushed for review.
- `mix deps.clean --all` MUST NOT be used unless there is a documented, specific reason.
- `mix help <task>` MUST be consulted before using an unfamiliar Mix task.
- The dev server exposes `/dev/dashboard` (LiveDashboard) and `/dev/mailbox` (Swoosh preview)
  in development only.

## Governance

This constitution supersedes all other coding guidance in this repository.
`CLAUDE.md` serves as the runtime agent context and MUST remain consistent with this document;
any amendment here MUST be reflected in `CLAUDE.md`.

Amendment procedure:
1. Open a PR with changes to `.specify/memory/constitution.md`.
2. Bump `CONSTITUTION_VERSION` per the versioning policy below.
3. Update `CLAUDE.md` to mirror any changed or added rules.
4. Update the Sync Impact Report (HTML comment at the top of this file).

Versioning policy:
- **MAJOR**: Removal or incompatible redefinition of an existing principle.
- **MINOR**: New principle or section added, or material guidance expansion.
- **PATCH**: Clarifications, wording, or typo fixes.

All features MUST pass the Constitution Check in `plan-template.md` before Phase 0 research
begins, and again after Phase 1 design.

**Version**: 1.0.0 | **Ratified**: 2026-06-11 | **Last Amended**: 2026-06-11
