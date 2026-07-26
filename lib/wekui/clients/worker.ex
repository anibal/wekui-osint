defmodule Wekui.Clients.Worker do
  @moduledoc """
  The inference client — a text-completion worker. The pilot's worker is DeepSeek via
  DeepInfra's OpenAI-compatible endpoint (`POST /chat/completions`, bearer auth). It is
  a behaviour with a live `Req` impl, so the network never enters the test suite — tests
  inject `plug: {Req.Test, Wekui.Clients.Worker.Live}` through `config :wekui, :deepinfra,
  req_options:`. The caller owns retries; a missing key fails without touching the
  network.
  """

  @callback complete(prompt :: String.t(), opts :: keyword()) ::
              {:ok, %{content: String.t()}} | {:error, term()}
  @callback ready?() :: boolean()

  @doc "Completes `prompt`, returning the model's text. `opts`: `:model`, `:temperature`."
  def complete(prompt, opts \\ []), do: impl().complete(prompt, opts)

  @doc "Whether the worker can run — its API key is present. Preflight once before a fan-out."
  def ready?, do: impl().ready?()

  defp impl, do: Application.get_env(:wekui, :worker_client, Wekui.Clients.Worker.Live)
end
