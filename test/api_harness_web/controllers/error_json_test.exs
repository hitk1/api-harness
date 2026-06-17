defmodule ApiHarnessWeb.ErrorJSONTest do
  use ApiHarnessWeb.ConnCase, async: true

  test "renders 404" do
    assert ApiHarnessWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "not found"}}
  end

  test "renders 500" do
    assert ApiHarnessWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
