defmodule Wekui.Pipelines.ResidueAudit do
  @moduledoc """
  Checks whether the extractor was right to say the vocabulary has no word for
  something — rung four of `docs/mechanisms.md`, the **audit prompt**: one narrow,
  checkable question about one artefact.

  The residue is the corpus asking for words, and it is the mechanism by which the
  vocabulary grows. That makes a FALSE entry expensive: it asks a person for a word
  they have already given. Measured on 22 accumulated entries, at least six named a
  happening the vocabulary already held — a trapped child, a journalist's appeal,
  neighbours mobilising — and the share was rising as the vocabulary grew from 17
  themes to 44.

  **The cause is retrieval, not vocabulary.** Grouping the block by family bought a
  drop from 11.9 to 5.4 residue entries per hundred posts and then began to loosen
  again. A longer list is harder to search, and no amount of formatting fixes that
  past some size. So the check moves downstream: let the extractor over-report, and
  audit what it reported.

  That is the project's standing posture — *recall first, precision through a
  downstream gate* — applied to the residue instead of to claims.

  **It never suppresses on a guess.** The prompt is told to answer NONE whenever it
  cannot tell, because a gap wrongly confirmed costs one glance and a real gap
  suppressed is a word the record never gets.
  """

  alias Wekui.Clients.Worker
  alias Wekui.Normalize
  alias Wekui.Pipelines.Extract
  alias Wekui.Taxonomy

  @prompt "prompts/residue_audit.v1.txt"

  @doc """
  Audits `entries` (strings the extractor reported as unfitted) against `event`'s
  active vocabulary.

  Returns `{:ok, %{real:, covered:, unaudited:}}` — `real` are the entries no theme
  covers, in their original order; `covered` maps an entry to the theme that already
  answers it; `unaudited` are entries the judge did not rule on, which are treated as
  REAL because silence must never suppress a gap.
  """
  def run(event, entries, opts \\ [])

  def run(_event, [], _opts), do: {:ok, %{real: [], covered: %{}, unaudited: []}}

  def run(event, entries, opts) do
    if Worker.ready?() do
      model = Keyword.get(opts, :model, "deepseek-ai/DeepSeek-V4-Flash")

      with rendered <- render(event, entries, opts),
           {:ok, %{content: content}} <- Worker.complete(rendered, model: model),
           {:ok, verdicts} <- parse(content) do
        {:ok, split(entries, verdicts, event)}
      end
    else
      {:error, {:state_gate, :worker_not_ready}}
    end
  end

  defp render(event, entries, opts) do
    numbered =
      entries
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, n} -> "#{n}. #{entry}" end)

    (opts[:prompt] || File.read!(@prompt))
    |> String.replace("{{vocabulary}}", Extract.vocabulary(event))
    |> String.replace("{{entries}}", numbered)
  end

  defp parse(content) do
    case content |> strip_fence() |> Jason.decode() do
      {:ok, %{"audit" => audit}} when is_list(audit) -> {:ok, audit}
      {:ok, _no_audit_key} -> {:error, :no_audit}
      {:error, error} -> {:error, {:invalid_json, error}}
    end
  end

  defp strip_fence(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
  end

  # A verdict only suppresses an entry when it names a theme that ACTUALLY EXISTS and
  # is active. A judge that invents a theme name has not covered anything, and its
  # word must not remove a gap from the list a person reads.
  defp split(entries, verdicts, event) do
    known =
      event.id
      |> Taxonomy.list_active_themes!()
      |> Map.new(&{Normalize.fold(&1.name), &1.name})

    by_n = Map.new(verdicts, fn v -> {v["n"], v} end)

    entries
    |> Enum.with_index(1)
    |> Enum.reduce(%{real: [], covered: %{}, unaudited: []}, fn {entry, n}, acc ->
      case by_n[n] do
        nil ->
          %{acc | real: acc.real ++ [entry], unaudited: acc.unaudited ++ [entry]}

        %{"verdict" => "COVERED", "theme" => theme} ->
          case Map.get(known, Normalize.fold(to_string(theme))) do
            nil -> %{acc | real: acc.real ++ [entry]}
            name -> %{acc | covered: Map.put(acc.covered, entry, name)}
          end

        _none_or_unreadable ->
          %{acc | real: acc.real ++ [entry]}
      end
    end)
  end
end
