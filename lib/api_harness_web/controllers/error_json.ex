defmodule ApiHarnessWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # Friendly messages for the statuses used by this API (auth/agent paths).
  def render("401.json", _assigns), do: %{errors: %{detail: "unauthenticated"}}
  def render("404.json", _assigns), do: %{errors: %{detail: "not found"}}
  def render("422.json", _assigns), do: %{errors: %{detail: "could not interpret request"}}
  def render("502.json", _assigns), do: %{errors: %{detail: "ai provider unavailable"}}
  def render("503.json", _assigns), do: %{errors: %{detail: "ai provider unavailable"}}

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
