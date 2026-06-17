defmodule ApiHarness.Memory.Retriever do
  @moduledoc """
  Relevance-based retrieval via pgvector cosine similarity (FR-020, research §5).

  Embeds the query text, then retrieves the top-K most similar persistent
  memories for `user_id`, optionally filtered by category.

  Layer 2 (ContextBuilder) retrieves `domain` category memories.
  Layer 4 retrieves `user` + `task` category memories (FR-022-A).
  """
  import Ecto.Query

  alias ApiHarness.LLM.Provider
  alias ApiHarness.Memory.PersistentMemory
  alias ApiHarness.Repo

  @default_top_k 5

  @doc """
  Retrieve the top `k` most similar memories for `user_id` nearest to `query`.
  Optionally pass `category:` to filter by a single category.
  """
  @spec retrieve(integer(), String.t(), keyword()) ::
          {:ok, [PersistentMemory.t()]} | {:error, term()}
  def retrieve(user_id, query, opts \\ []) do
    k = Keyword.get(opts, :k, @default_top_k)
    category = Keyword.get(opts, :category)

    with {:ok, embedding} <- Provider.embed(query) do
      vector = Pgvector.new(embedding)

      base =
        from pm in PersistentMemory,
          where: pm.user_id == ^user_id,
          order_by: fragment("embedding <=> ?", ^vector),
          limit: ^k

      base =
        if category do
          from pm in base, where: pm.category == ^category
        else
          base
        end

      {:ok, Repo.all(base)}
    end
  end
end
