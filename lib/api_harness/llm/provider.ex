defmodule ApiHarness.LLM.Provider do
  @moduledoc """
  Behaviour for an LLM backend. The concrete implementation is resolved from
  application config (`config :api_harness, ApiHarness.LLM, provider: ...`) so
  tests can inject a stub (no live OpenAI calls — Test Discipline).

  See `ApiHarness.LLM.OpenAI` for the production implementation and
  `ApiHarness.LLMStub` (test support) for the in-memory double.
  """

  @typedoc "A chat message in OpenAI format: `%{role: \"system\"|\"user\"|\"assistant\", content: ...}`"
  @type message :: %{required(:role) => String.t(), required(:content) => String.t()}

  @typedoc "Options for `c:chat_completion/2`. `:json_schema` enables structured outputs."
  @type chat_opts :: keyword()

  @doc """
  Run a chat completion over `messages`.

  Returns `{:ok, content}` where `content` is the assistant string, or, when a
  `:json_schema` option is supplied, `{:ok, decoded_map}` with the parsed
  structured output. Returns `{:error, reason}` on failure (caller maps to
  502/503 — fail fast, no retry).
  """
  @callback chat_completion([message()], chat_opts()) ::
              {:ok, String.t() | map()} | {:error, term()}

  @doc """
  Embed `text` into a dense vector. Returns `{:ok, [float()]}` or `{:error, reason}`.
  """
  @callback embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}

  @doc "The configured provider module."
  @spec impl() :: module()
  def impl do
    Application.fetch_env!(:api_harness, ApiHarness.LLM)[:provider]
  end

  @doc "Delegates to the configured provider's `chat_completion/2`."
  @spec chat_completion([message()], chat_opts()) :: {:ok, String.t() | map()} | {:error, term()}
  def chat_completion(messages, opts \\ []), do: impl().chat_completion(messages, opts)

  @doc "Delegates to the configured provider's `embed/2`."
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []), do: impl().embed(text, opts)
end
