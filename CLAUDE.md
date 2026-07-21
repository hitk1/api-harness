# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Phoenix 1.8 JSON API application backed by PostgreSQL. No browser pipeline, no LiveView, no frontend assets — all routes live under `/api`. Uses Bandit as the HTTP server instead of Cowboy.

## Commands

```bash
mix setup                  # install deps + create/migrate/seed DB (first-time)
mix phx.server             # start dev server at localhost:4000
iex -S mix phx.server      # start inside IEx
mix test                   # run all tests (auto-creates and migrates test DB)
mix test test/path/file.exs                # run a single test file
mix test --failed          # re-run only previously failing tests
mix precommit              # compile (warnings-as-errors) + unused deps + format + test — run before committing
mix ecto.reset             # drop and recreate the dev database
mix ecto.gen.migration name_with_underscores  # generate a migration with correct timestamp
```

Dev tools available at runtime (development only):
- `localhost:4000/dev/dashboard` — LiveDashboard
- `localhost:4000/dev/mailbox` — Swoosh local mailbox preview

## Architecture

### OTP supervision tree
`ApiHarness.Application` starts: `Telemetry → Repo → DNSCluster → PubSub → Endpoint` (one_for_one).

### Module layout
- `lib/api_harness/` — domain contexts and business logic (Ecto schemas, changesets, context modules)
- `lib/api_harness_web/` — web layer (router, controllers, endpoint, telemetry)
- `ApiHarnessWeb` (`lib/api_harness_web.ex`) — injects shared imports/aliases into controllers, channels, etc. via `use ApiHarnessWeb, :controller` etc.
- All API routes are scoped under `/api` through the `:api` pipeline (`accepts: ["json"]`)

### Key dependencies
| Dep | Purpose |
|-----|---------|
| `req` | HTTP client — **always use this**, never `:httpoison`, `:tesla`, or `:httpc` |
| `ecto_sql` + `postgrex` | PostgreSQL persistence |
| `swoosh` | Transactional email |
| `bandit` | HTTP server (replaces Cowboy) |
| `jason` | JSON encoding/decoding |

## Phoenix v1.8 guidelines

- Always begin LiveView templates with `<Layouts.app flash={@flash} ...>` wrapping all inner content. `MyAppWeb.Layouts` is aliased in `api_harness_web.ex` — no need to alias it again.
- `<.flash_group>` was moved into the `Layouts` module in v1.8 — **never** call it outside `layouts.ex`.
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>` for icons — **never** use `Heroicons` modules directly.
- Always use the `<.input>` component from `core_components.ex` for form inputs. If you override the default classes with `class="..."`, no defaults are inherited — your classes must fully style the input.
- When a `current_scope` assign is missing: you either have routes outside the proper `live_session`, or forgot to pass `current_scope` to `<Layouts.app>`. Fix by moving routes, not by adding fallbacks.
- Router `scope` blocks include an optional alias prefixed to all routes inside — never add a manual `alias` for route definitions. Example: `scope "/admin", AppWeb.Admin` makes `live "/users", UserLive` resolve to `AppWeb.Admin.UserLive`.
- `Phoenix.View` no longer exists in Phoenix 1.8 — do not use it.

## Elixir guidelines

- Lists don't support index access via `[]`; use `Enum.at/2`, pattern matching, or `List` functions.
- Block expressions (`if`, `case`, `cond`) must be bound to a variable — rebinding inside the block has no effect outside it.
- Never nest multiple modules in the same file.
- Access struct fields with dot notation (`struct.field`) or `Ecto.Changeset.get_field/2`, never with map-access syntax (`changeset[:field]`).
- The standard library covers all date/time needs (`Date`, `Time`, `DateTime`, `Calendar`). Only add `date_time_parser` for parsing external date strings.
- Don't use `String.to_atom/1` on user input (memory leak).
- Predicate function names must end with `?`, not start with `is_` (`is_*` names are reserved for guards).
- OTP primitives (`DynamicSupervisor`, `Registry`) require a `:name` in the child spec, e.g. `{DynamicSupervisor, name: MyApp.MyDynamicSup}`.
- For concurrent enumeration use `Task.async_stream(collection, callback, timeout: :infinity)`.

## Mix guidelines

- Read `mix help <task>` before using unfamiliar tasks.
- `mix deps.clean --all` is almost never needed — avoid it.

## Ecto guidelines

- Always preload associations in queries when they'll be accessed in templates (prevents N+1).
- Remember to `import Ecto.Query` (and other supporting modules) in `seeds.exs`.
- Schema fields always use `:string` type, even for `:text` DB columns.
- `Ecto.Changeset.validate_number/2` does **not** support `:allow_nil` — it's unnecessary (validations only run when a non-nil change exists).
- Use `Ecto.Changeset.get_field(changeset, :field)` to read changeset values — never `changeset[:field]`.
- Programmatically-set fields (e.g. `user_id`) must **not** appear in `cast/3` calls — set them explicitly on the struct.
- Always use `mix ecto.gen.migration migration_name_using_underscores` to generate migrations (correct timestamp and conventions).

## Testing

- Always use `start_supervised!/1` to start processes so they're cleaned up between tests.
- Never use `Process.sleep/1` or `Process.alive?/1` in tests.
  - To wait for a process to finish: `ref = Process.monitor(pid); assert_receive {:DOWN, ^ref, :process, ^pid, :normal}`
  - To synchronize before the next call: `_ = :sys.get_state(pid)`
- Test helpers: `test/support/conn_case.ex` (controller tests), `test/support/data_case.ex` (Ecto tests).

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
`specs/003-context-budget-management/plan.md` (see also `research.md`,
`data-model.md`, and `quickstart.md` in the same directory). For the original
foundational feature, see `specs/001-legal-ai-agent-harness/plan.md`.
<!-- SPECKIT END -->
