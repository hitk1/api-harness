defmodule ApiHarness.Context.Compaction.Registry do
  @moduledoc "Registry for compaction workers keyed by {:compaction, chat_id}."

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end
