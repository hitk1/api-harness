defmodule ApiHarnessWeb.FallbackController do
  @moduledoc """
  Translates controller `{:error, reason}` tuples into JSON error responses of
  the shape `{"errors": {"detail": ...}}`, per the API contracts.

  Status mapping:

    * `:missing_credentials` → 400 "email and password are required"
    * `:empty_content`       → 400 "content is required"
    * `:invalid_credentials` → 401 "invalid credentials"
    * `:unauthenticated`     → 401 "unauthenticated"
    * `:not_found`           → 404 "not found"
    * `:planner_failed`      → 422 "could not interpret request"
    * `%Ecto.Changeset{}`    → 422 (field-level errors)
    * `:llm_unavailable`     → 502 "ai provider unavailable"
  """
  use ApiHarnessWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: changeset_errors(changeset)})
  end

  def call(conn, {:error, reason}) do
    {status, detail} = map_error(reason)

    conn
    |> put_status(status)
    |> json(%{errors: %{detail: detail}})
  end

  defp map_error(:missing_credentials), do: {:bad_request, "email and password are required"}
  defp map_error(:empty_content), do: {:bad_request, "content is required"}
  defp map_error(:invalid_credentials), do: {:unauthorized, "invalid credentials"}
  defp map_error(:unauthenticated), do: {:unauthorized, "unauthenticated"}
  defp map_error(:not_found), do: {:not_found, "not found"}
  defp map_error(:planner_failed), do: {:unprocessable_entity, "could not interpret request"}
  defp map_error(:llm_unavailable), do: {:bad_gateway, "ai provider unavailable"}
  defp map_error(_other), do: {:internal_server_error, "internal server error"}

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
