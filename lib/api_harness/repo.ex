defmodule ApiHarness.Repo do
  use Ecto.Repo,
    otp_app: :api_harness,
    adapter: Ecto.Adapters.Postgres
end
