defmodule AuroraWeb.PageController do
  use AuroraWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
