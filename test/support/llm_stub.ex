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

  Overrides use application env (global) — tests that set them should run
  `async: false`.
  """
  @behaviour ApiHarness.LLM.Provider

  @env_key :llm_stub

  @impl true
  def chat_completion(messages, opts \\ []) do
    case override() do
      %{error: reason} when not is_nil(reason) ->
        {:error, reason}

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
  defp empty, do: %{error: nil, response: nil}
end
