defmodule AuroraWeb.Plugs.Auth do
  @moduledoc """
  Simple password-based authentication plug for single-user access.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :authenticated) do
      conn
    else
      conn
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Verifies the password against the stored hash.
  The password hash should be set in the AURORA_PASSWORD_HASH environment variable.
  To generate a hash, run: Bcrypt.hash_pwd_salt("your_password")
  """
  def verify_password(password) do
    case get_password_hash() do
      nil ->
        # If no password is set, accept "aurora" as default for development
        password == "aurora"

      hash ->
        Bcrypt.verify_pass(password, hash)
    end
  end

  defp get_password_hash do
    System.get_env("AURORA_PASSWORD_HASH")
  end
end
