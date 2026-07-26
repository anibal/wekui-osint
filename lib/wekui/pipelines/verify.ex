defmodule Wekui.Pipelines.Verify do
  @moduledoc """
  The support gate: does a [[claim]]'s cited evidence bear it, at the strength it
  states? For a claim it gathers the cited [[post]]s, asks the inference
  `Wekui.Clients.Worker` to judge the claim against them, and records the verdict —
  supported, overstated, or unsupported — with a one-line reason. Citation *presence*
  is not support; this checks *entailment*, the honesty gap the record's whole thesis
  turns on.

  A first backstop, flag-only: nothing is withheld from a reader here, the verdict is
  recorded for a human to service (`docs/evaluation-matrix.md`).
  """

  alias Wekui.Capture
  alias Wekui.Clients.Worker
  alias Wekui.Narrative

  @default_prompt_file "prompts/support.v1.txt"
  @default_model "deepseek-ai/DeepSeek-V4-Flash"

  @doc """
  Judges `claim` against its cited Posts and records the support verdict. `opts`:
  `:prompt_file`, `:model`. Returns `{:ok, claim}` with the verdict recorded, or
  `{:error, reason}` when the worker is unreachable or its output does not parse.
  """
  def run(claim, opts \\ []) do
    prompt =
      opts
      |> Keyword.get(:prompt_file, @default_prompt_file)
      |> File.read!()
      |> render(claim, cited_posts(claim))

    with {:ok, %{content: content}} <-
           Worker.complete(prompt, model: Keyword.get(opts, :model, @default_model)),
         {:ok, verdict, note} <- parse(content) do
      {:ok, Narrative.record_claim_support!(claim, %{support: verdict, support_note: note})}
    end
  end

  defp cited_posts(claim) do
    claim.id
    |> Narrative.list_claim_citations!()
    |> Enum.map(&Capture.get_post!(&1.post_id))
  end

  defp render(template, claim, posts) do
    evidence = Enum.map_join(posts, "\n", fn p -> "[#{p.x_id}] #{p.text}" end)

    template
    |> String.replace("{{kind}}", claim.kind || "—")
    |> String.replace("{{subject}}", claim.subject || "—")
    |> String.replace("{{place}}", claim.place_mention || "—")
    |> String.replace("{{magnitude}}", magnitude(claim.magnitude))
    |> String.replace("{{status}}", claim.status || "—")
    |> String.replace("{{evidence}}", evidence)
  end

  defp magnitude(nil), do: "—"
  defp magnitude(map), do: Jason.encode!(map)

  defp parse(content) do
    case content |> strip_fence() |> Jason.decode() do
      {:ok, %{"verdict" => verdict} = decoded}
      when verdict in ["supported", "overstated", "unsupported"] ->
        {:ok, String.to_existing_atom(verdict), decoded["note"]}

      {:ok, other} ->
        {:error, {:bad_verdict, other}}

      {:error, error} ->
        {:error, {:invalid_json, error}}
    end
  end

  defp strip_fence(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
  end
end
