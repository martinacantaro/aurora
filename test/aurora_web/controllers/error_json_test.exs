defmodule AuroraWeb.ErrorJSONTest do
  use AuroraWeb.ConnCase, async: true

  test "renders 404" do
    assert AuroraWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert AuroraWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
