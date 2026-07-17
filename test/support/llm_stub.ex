defmodule ApiHarness.LLMStub do
  @moduledoc """
  In-memory `ApiHarness.LLM.Provider` used in tests — no live OpenAI calls.

  Behaviour:

    * `chat_completion/2` returns deterministic canned output. With a
      `:json_schema` it branches on `:schema_name` to return a structured map
      for the planner / extractor / reconciler; without one it returns a canned
      assistant string.
    * `embed/2` returns a stable 1536-dim vector derived from the input text, so
      identical text embeds identically (handy for retrieval assertions).

  Tests can override behaviour globally:

      ApiHarness.LLMStub.set_error({:http_error, 503, %{}})  # force failures
      ApiHarness.LLMStub.set_chat_response(%{"steps" => [...]})
      ApiHarness.LLMStub.reset()

  For flows that make more than one structured-output call per invocation
  (e.g. planner → extractor → session reconciler within one `Runtime.run/3`),
  `set_chat_response_for/2` overrides a single `:schema_name` at a time so
  each stage can be scripted independently without colliding with the others:

      ApiHarness.LLMStub.set_chat_response_for("session_reconciliation", %{
        "action" => "update", "id" => entry_id, "content" => "..."
      })

  Overrides use application env (global) — tests that set them should run
  `async: false`.
  """
  @behaviour ApiHarness.LLM.Provider

  @env_key :llm_stub

  @impl true
  def chat_completion(messages, opts \\ []) do
    schema_name = Keyword.get(opts, :schema_name)

    case override() do
      %{error: reason} when not is_nil(reason) ->
        {:error, reason}

      %{by_schema: by_schema} when is_map_key(by_schema, schema_name) ->
        case Map.fetch!(by_schema, schema_name) do
          fun when is_function(fun, 2) -> fun.(messages, opts)
          response -> {:ok, response}
        end

      %{response: response} when not is_nil(response) ->
        if Keyword.has_key?(opts, :schema_name) do
          {:ok, response}
        else
          {:ok, default_response(messages, opts)}
        end

      _ ->
        {:ok, default_response(messages, opts)}
    end
  end

  @impl true
  def embed(text, _opts \\ []) do
    case override() do
      %{error: reason} when not is_nil(reason) -> {:error, reason}
      _ -> {:ok, deterministic_vector(text)}
    end
  end

  # --- test control helpers -------------------------------------------------

  @doc "Force both callbacks to return `{:error, reason}` (e.g. OpenAI outage)."
  def set_error(reason), do: put_override(%{override() | error: reason})

  @doc "Make `chat_completion/2` return `{:ok, response}` regardless of input."
  def set_chat_response(response), do: put_override(%{override() | response: response})

  @doc """
  Make `chat_completion/2` return `{:ok, response}` only for calls made with
  this exact `:schema_name` option — other schema names (and non-structured
  calls) keep falling back to `set_chat_response/1`'s override or the default.

  `response` may also be a 2-arity function `(messages, opts) -> {:ok, _} |
  {:error, _}`, evaluated on each matching call — handy for tests that need to
  block until signaled (e.g. to deterministically exercise concurrency).
  """
  def set_chat_response_for(schema_name, response) do
    current = override()
    by_schema = current |> Map.get(:by_schema, %{}) |> Map.put(schema_name, response)
    put_override(Map.put(current, :by_schema, by_schema))
  end

  @doc "Clear all overrides."
  def reset, do: put_override(empty())

  # --- defaults -------------------------------------------------------------

  defp default_response(messages, opts) do
    case Keyword.get(opts, :schema_name) do
      "agent_plan" ->
        %{
          "steps" => [
            %{"type" => "answer", "tool" => nil, "input" => %{}, "parallel" => false}
          ]
        }

      "knowledge_extraction" ->
        %{
          "items" => [
            %{
              "category" => "task",
              "kind" => "fact",
              "content" => "Stub-extracted fact: " <> last_user_content(messages),
              "durable" => true
            }
          ]
        }

      "memory_reconciliation" ->
        %{"action" => "create", "content" => last_user_content(messages)}

      _ ->
        "Stub assistant answer."
    end
  end

  defp last_user_content(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{role: "user", content: content} -> content
      %{"role" => "user", "content" => content} -> content
      _ -> nil
    end)
  end

  # Stable pseudo-embedding: same text → same vector.
  defp deterministic_vector(text) do
    seed = :erlang.phash2(text)
    for i <- 1..1536, do: :math.sin((seed + i) / 100.0)
  end

  # --- override storage -----------------------------------------------------

  defp override, do: Application.get_env(:api_harness, @env_key, empty())
  defp put_override(map), do: Application.put_env(:api_harness, @env_key, map)
  defp empty, do: %{error: nil, response: nil, by_schema: %{}}
end
