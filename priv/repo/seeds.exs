# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     ApiHarness.Repo.insert!(%ApiHarness.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias ApiHarness.Accounts
alias ApiHarness.Repo

# Idempotent seed: only create if the user doesn't exist yet.
unless Repo.exists?(from u in ApiHarness.Accounts.User, where: u.email == "advogado@example.com") do
  {:ok, user} =
    Accounts.create_user(%{
      name: "Eduardo Advogado",
      email: "advogado@example.com",
      password: "s3cr3tpassword"
    })

  IO.puts("Seed user created: #{user.email} (id=#{user.id})")
end
