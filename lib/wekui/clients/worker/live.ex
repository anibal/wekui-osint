defmodule Wekui.Clients.Worker.Live do
  @moduledoc """
  The live DeepInfra worker over `Req` (OpenAI-compatible chat completions). One
  request per call, no retries — the caller owns retry policy. The API key is read
  from `config :wekui, :deepinfra` and is never logged or put in an error.
  """

  @behaviour Wekui.Clients.Worker

  @default_base_url "https://api.deepinfra.com/v1/openai"
  @default_model "deepseek-ai/DeepSeek-V4-Flash"
  @path "/chat/completions"

  @impl true
  def ready?, do: key() not in [nil, ""]

  @impl true
  def complete(prompt, opts) when is_binary(prompt) do
    if ready?() do
      config = Application.get_env(:wekui, :deepinfra, [])

      req =
        [
          auth: {:bearer, key()},
          receive_timeout: config[:receive_timeout] || 180_000,
          retry: false,
          json: %{
            model: Keyword.get(opts, :model, config[:model] || @default_model),
            temperature: Keyword.get(opts, :temperature, 0),
            messages: [%{role: "user", content: prompt}]
          }
        ]
        |> Keyword.merge(config[:req_options] || [])

      (config[:base_url] || @default_base_url)
      |> Kernel.<>(@path)
      |> Req.post(req)
      |> handle()
    else
      {:error, {:state_gate, :missing_api_key}}
    end
  end

  defp handle({:ok, %{status: 200, body: body}}) do
    case get_in(body, ["choices", Access.at(0), "message", "content"]) do
      content when is_binary(content) -> {:ok, %{content: content}}
      _malformed -> {:error, {:malformed_output, body}}
    end
  end

  defp handle({:ok, %{status: status, body: body}}), do: {:error, {:http, status, body}}
  defp handle({:error, exception}), do: {:error, {:transport, exception}}

  defp key, do: Application.get_env(:wekui, :deepinfra, [])[:api_key]
end
