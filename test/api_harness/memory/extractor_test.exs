defmodule ApiHarness.Memory.ExtractorTest do
  use ApiHarness.DataCase, async: false

  alias ApiHarness.Memory.Extractor
  alias ApiHarness.LLMStub

  setup do
    LLMStub.reset()
    :ok
  end

  describe "extract/1" do
    test "returns structured candidates with correct keys" do
      message = %{content: "O prazo prescricional de ação trabalhista é de 2 anos."}
      assert {:ok, items} = Extractor.extract(message)
      assert is_list(items)

      for item <- items do
        assert Map.has_key?(item, "category")
        assert Map.has_key?(item, "kind")
        assert Map.has_key?(item, "content")
        assert Map.has_key?(item, "durable")
        assert item["category"] in ["user", "task", "domain"]
        assert item["kind"] in ["preference", "goal", "constraint", "fact"]
      end
    end

    test "returns empty list for empty content" do
      assert {:ok, []} = Extractor.extract(%{content: ""})
      assert {:ok, []} = Extractor.extract(%{content: "   "})
    end

    test "propagates LLM error" do
      LLMStub.set_error({:http_error, 503, %{}})
      assert {:error, _} = Extractor.extract(%{content: "Some content"})
    end
  end
end
