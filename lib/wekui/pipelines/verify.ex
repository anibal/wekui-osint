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

  ## What it judges against

  The claim's [[theme]] and **that theme's own `applies_when`** — the rule a person
  ratified, which states exactly what a post must assert for the happening to apply, and
  which names the theme it is most often confused with.

  Until v2 the gate never saw it. It was handed `kind`, the extractor's free-text note —
  the field the extraction prompt itself calls *"a note on how the post read"* that
  *"nothing is filed by"*. So the gate judged a label the system says means nothing while
  the actual contract sat unread, and it reached the right answer on the plea-read-as-a-
  search by reasoning from the word "búsqueda", which is not in the vocabulary at all. It
  got lucky. `kind` is still passed, labelled as carrying no authority, because it is
  evidence of how the extractor read the post.

  ## A claim with no ratified happening is not this gate's question

  76 claims predate the vocabulary and carry no theme. v2 first handed the model *"judge
  it on the evidence alone"*, and it **invented a standard to judge against** — one note
  read *"la regla exige…"* where no rule exists. Two of the four adjudicated v2 errors
  were on that path. So `judge/2` refuses outright: a claim with no ratified rule cannot
  be checked against one, and it cannot be filed either way. That is rung 1 of
  `docs/mechanisms.md` deleting a question instead of paying a model to answer it badly.
  """

  alias Wekui.Capture
  alias Wekui.Clients.Worker
  alias Wekui.Narrative
  alias Wekui.Taxonomy

  @default_prompt_file "prompts/support.v2.txt"
  @default_model "deepseek-ai/DeepSeek-V4-Flash"

  @doc """
  Judges `claim` against its cited Posts and records the support verdict. `opts`:
  `:prompt_file`, `:model`. Returns `{:ok, claim}` with the verdict recorded, or
  `{:error, reason}` when the worker is unreachable or its output does not parse.
  """
  def run(claim, opts \\ []) do
    with {:ok, verdict, note} <- judge(claim, opts) do
      {:ok, Narrative.record_claim_support!(claim, %{support: verdict, support_note: note})}
    end
  end

  @doc """
  Judges `claim` and returns `{:ok, verdict, note}` **without recording anything**.

  Separated from `run/2` so a prompt revision can be measured against claims that already
  carry a verdict, without overwriting the verdicts it is being measured against. An
  evaluation that mutates its own baseline can only be run once.
  """
  def judge(%{theme_id: nil} = claim, _opts), do: {:error, {:no_ratified_rule, claim.id}}

  def judge(claim, opts) do
    prompt =
      opts
      |> Keyword.get(:prompt_file, @default_prompt_file)
      |> File.read!()
      |> render(claim, cited_posts(claim))

    with {:ok, %{content: content}} <-
           Worker.complete(prompt, model: Keyword.get(opts, :model, @default_model)) do
      parse(content)
    end
  end

  def judge(claim), do: judge(claim, [])

  defp cited_posts(claim) do
    claim.id
    |> Narrative.list_claim_citations!()
    |> Enum.map(&Capture.get_post!(&1.post_id))
  end

  defp render(template, claim, posts) do
    evidence = Enum.map_join(posts, "\n", fn p -> "[#{p.x_id}] #{p.text}" end)
    {theme, applies_when} = ratified_rule(claim)

    template
    |> String.replace("{{theme}}", theme)
    |> String.replace("{{applies_when}}", applies_when)
    |> String.replace("{{kind}}", claim.kind || "—")
    |> String.replace("{{subject}}", claim.subject || "—")
    |> String.replace("{{place}}", claim.place_mention || "—")
    |> String.replace("{{magnitude}}", magnitude(claim.magnitude))
    |> String.replace("{{status}}", claim.status || "—")
    |> String.replace("{{evidence}}", evidence)
  end

  defp ratified_rule(claim) do
    case Taxonomy.get_theme(claim.theme_id) do
      {:ok, theme} -> {theme.name, theme.applies_when}
      {:error, _gone} -> {"ninguno", "—"}
    end
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
