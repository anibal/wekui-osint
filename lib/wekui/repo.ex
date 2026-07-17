defmodule Wekui.Repo do
  use Ecto.Repo,
    otp_app: :wekui,
    adapter: Ecto.Adapters.Postgres
end
