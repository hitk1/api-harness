defmodule ApiHarnessWeb.AuthJSON do
  def login(%{token: token, user: user}) do
    %{token: token, user: %{id: user.id, name: user.name, email: user.email}}
  end
end
