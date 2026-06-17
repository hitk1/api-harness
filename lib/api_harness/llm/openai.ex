defmodule ApiHarness.LLM.OpenAI do
  @moduledoc """
  Req-based OpenAI provider (constitution: Req is the mandatory HTTP client).

  Implements `ApiHarness.LLM.Provider`:

    * `chat_completion/2` — `POST /chat/completions` with `gpt-4o-mini`.
      Pass `:json_schema` (and optional `:schema_name`) to enable structured
      outputs (`response_format: json_schema`); the parsed map is returned.
    * `embed/2` — `POST /embeddings` with `text-embedding-3-small`.

  Failures return `{:error, reason}`; callers fail fast (HTTP 502/503, no retry,
  no fallback — FR-013-A).
  """
  @behaviour ApiHarness.LLM.Provider

  require Logger

  @impl true
  def chat_completion(messages, opts \\ []) do
    body = %{model: config(:chat_model), messages: messages}

    body =
      case Keyword.get(opts, :json_schema) do
        nil ->
          body

        schema ->
          name = Keyword.get(opts, :schema_name, "structured_output")

          Map.put(body, :response_format, %{
            type: "json_schema",
            json_schema: %{name: name, strict: false, schema: schema}
          })
      end

    with {:ok, %{status: 200} = resp} <- post("/chat/completions", body),
         {:ok, content} <- extract_message_content(resp.body) do
      maybe_decode(content, opts)
    else
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def embed(text, _opts \\ []) do
    body = %{model: config(:embedding_model), input: text}

    with {:ok, %{status: 200} = resp} <- post("/embeddings", body),
         %{"data" => [%{"embedding" => embedding} | _]} <- resp.body do
      {:ok, embedding}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  defp post(path, body) do
    Req.post(req(), url: path, json: body)
  rescue
    e -> {:error, e}
  end

  defp req do
    Req.new(
      base_url: config(:base_url),
      auth: {:bearer, config(:api_key) || ""},
      receive_timeout: 60_000,
      retry: false
    )
  end

  defp extract_message_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}),
    do: {:ok, content}

  defp extract_message_content(other), do: {:error, {:unexpected_response, other}}

  defp maybe_decode(content, opts) do
    case Keyword.get(opts, :json_schema) do
      nil -> {:ok, content}
      _schema -> Jason.decode(content)
    end
  end

  defp config(key) do
    Application.fetch_env!(:api_harness, ApiHarness.LLM)[key]
  end
end
