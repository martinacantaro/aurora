defmodule AuroraWeb.SessionController do
  use AuroraWeb, :controller

  alias AuroraWeb.Plugs.Auth

  def new(conn, _params) do
    render(conn, :login, error: nil)
  end

  def create(conn, %{"password" => password}) do
    if Auth.verify_password(password) do
      conn
      |> put_session(:authenticated, true)
      |> redirect(to: "/")
    else
      render(conn, :login, error: "Invalid password")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/login")
  end
end
