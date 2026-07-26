defmodule Wekui.Clients.WorkerTest do
  use ExUnit.Case, async: true

  alias Wekui.Clients.Worker

  test "completes a prompt, returning the model's text content" do
    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => ~s({"claims": []})}}]})
    end)

    assert {:ok, %{content: ~s({"claims": []})}} = Worker.complete("prompt", model: "m")
  end

  test "an HTTP error is reported, not raised" do
    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Plug.Conn.send_resp(conn, 429, ~s({"error":"rate limited"}))
    end)

    assert {:error, {:http, 429, _body}} = Worker.complete("prompt")
  end

  test "ready? reflects a present api key" do
    assert Worker.ready?()
  end
end
