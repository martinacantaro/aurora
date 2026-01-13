defmodule Aurora.Repo do
  use Ecto.Repo,
    otp_app: :aurora,
    adapter: Ecto.Adapters.Postgres
end
