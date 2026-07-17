# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :api_harness,
  ecto_repos: [ApiHarness.Repo],
  generators: [timestamp_type: :utc_datetime]

# Register the pgvector Postgrex extension so `vector` columns round-trip
# through Ecto (see lib/api_harness/postgrex_types.ex).
config :api_harness, ApiHarness.Repo, types: ApiHarness.PostgrexTypes

# Configure the endpoint
config :api_harness, ApiHarnessWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ApiHarnessWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ApiHarness.PubSub,
  live_view: [signing_salt: "wOnUtdVs"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :api_harness, ApiHarness.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# LLM provider configuration. The provider module is swappable so tests can
# inject a stub (see config/test.exs). Secrets (`api_key`) are filled from the
# environment in config/runtime.exs.
config :api_harness, ApiHarness.LLM,
  provider: ApiHarness.LLM.OpenAI,
  chat_model: "gpt-4o-mini",
  embedding_model: "text-embedding-3-small",
  base_url: "https://api.openai.com/v1",
  api_key: nil

# Agent runtime tuning. `recent_messages_window` bounds layer 5 of the prompt
# (ContextBuilder) — the number of recent conversation turns included.
config :api_harness, :agent, recent_messages_window: 10

# Session-memory pipeline (spec 002). `topic` is the Phoenix.PubSub topic the
# Coordinator subscribes to and MessageController broadcasts turn events on.
# `max_concurrency` bounds how many distinct chat_ids the Coordinator processes
# at once (a given chat_id is always processed one turn at a time).
config :api_harness, :session_memory, topic: "session_memory:updates", max_concurrency: 10

# Default JWT signing secret for dev/test. Overridden at runtime from
# JWT_SECRET (config/runtime.exs) in any environment where it is set.
config :api_harness,
       :jwt_secret,
       "dev_test_insecure_jwt_secret_please_override_via_env_0123456789abcdef"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
