defmodule ApiHarness.Memory.Extractor do
  @moduledoc """
  Extracts structured knowledge candidates from an assistant message (FR-018).
  Uses LLM structured outputs to produce typed items:
  `{category, kind, content, durable}`.
  """

  alias ApiHarness.LLM.Provider

  @extraction_schema %{
    type: "object",
    properties: %{
      items: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            category: %{type: "string", enum: ["user", "task", "domain"]},
            kind: %{type: "string", enum: ["preference", "goal", "constraint", "fact"]},
            content: %{type: "string"},
            durable: %{type: "boolean"}
          },
          required: ["category", "kind", "content", "durable"],
          additionalProperties: false
        }
      }
    },
    required: ["items"],
    additionalProperties: false
  }

  @doc """
  Extract knowledge candidates from `message` (an `ApiHarness.Chats.Message` or
  a map with a `:content` / `"content"` key).

  Returns `{:ok, [candidate_map]}` where each map has `category`, `kind`,
  `content`, `durable` keys. Non-durable candidates are included so the
  Reconciler can discard them explicitly (audit trail).
  """
  @spec extract(map()) :: {:ok, [map()]} | {:error, term()}
  def extract(message) do
    content = message.content || message["content"] || ""

    if String.trim(content) == "" do
      {:ok, []}
    else
      messages = [
        %{
          role: "system",
          content: """
          You are a knowledge extraction assistant. Given an assistant message from a legal AI chat,
          extract structured knowledge items the user might benefit from remembering.
          Classify each item by category (user/task/domain) and kind (preference/goal/constraint/fact).
          Mark `durable: true` only if the knowledge would remain useful in 30+ days.
          """
        },
        %{role: "user", content: "Extract knowledge from:\n\n#{content}"}
      ]

      opts = [json_schema: @extraction_schema, schema_name: "knowledge_extraction"]

      case Provider.chat_completion(messages, opts) do
        {:ok, %{"items" => items}} -> {:ok, items}
        {:ok, _} -> {:ok, []}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
