defmodule ApiHarness.LLM.TokenCounter do
  @moduledoc """
  Counts tokens for LLM prompts using tiktoken (o200k_base for gpt-4o-mini).
  Falls back to ceil(byte_size/4) if the NIF is unavailable.
  """
  require Logger

  @model "gpt-4o-mini"

  @doc "Returns the token count for text. Never raises."
  @spec count(String.t()) :: non_neg_integer()
  def count(text) when is_binary(text) do
    case tiktoken_count(text) do
      {:ok, n} -> n
      {:error, _} -> fallback_count(text)
    end
  end

  def count(_), do: 0

  defp tiktoken_count(text) do
    # Try to call tiktoken NIF if available.
    # Using apply/3 to avoid compile-time dependency on the NIF being loaded.
    case Code.ensure_loaded(Tiktoken) do
      {:module, _} ->
        try do
          result = apply(Tiktoken, :count_tokens, [@model, text, :no_special_tokens])

          case result do
            {:ok, n} when is_integer(n) -> {:ok, n}
            n when is_integer(n) -> {:ok, n}
            _ -> {:error, :unexpected_result}
          end
        rescue
          e ->
            Logger.warning("TokenCounter: tiktoken failed: #{inspect(e)}, using fallback")
            {:error, :nif_error}
        end

      {:error, _} ->
        {:error, :not_available}
    end
  end

  defp fallback_count(text) do
    max(1, div(byte_size(text), 4))
  end
end
