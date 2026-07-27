defmodule Wekui.Narrative.Duplicates do
  @moduledoc """
  Finds Claims that may be one happening told twice, so a person rules on them before
  the record fills up with them.

  One happening is one [[claim]] (`docs/pages/claim.md`). Within a single extraction
  batch the deterministic merge already holds that line. Across batches it does not:
  the same rescue reported at one minute and again at noon arrives as two claims, and
  as the corpus grows past a pilot that is the defect that compounds fastest.

  This is the place-shaped rule turned on claims — the same shape as
  `Wekui.Gazetteer.Duplicates`, and it stops in the same place, at a judgement no
  string can make.

  ## What the vocabulary already says, made mechanical

  From [[claim]]: *"Two accounts are one claim when their distinguishing marks match,
  weighed by how specific they are: a specific subject and magnitude — a man of 21,
  106 hours — hold across noisy or even wrong place labels, while a generic subject —
  a woman — cannot, and there the place must tell them apart. A woman missing in one
  building and a woman missing in another are two claims."*

  So specificity decides how much evidence a pair needs:

    * a **specific** subject — one carrying a number, an age, a count — is its own
      distinguishing mark, and carries across a wrong place label;
    * a **generic** subject — "una mujer", "un hombre" — proves nothing by itself, and
      the pair only stands if the two claims are **at the same place** and close in
      time.

  Either way the two must describe the same **kind** of change: a search and a rescue
  are two happenings in one story, not one happening told twice. That is a [[person]]'s
  arc, and it is not a merge.

  ## Where it stops

  It proposes; it never merges. Two accounts can differ in every string and be one
  happening, and can match in every string and be two — a woman missing in one
  building and a woman missing in another. Nothing here reaches that, which is why the
  answer is a person's, recorded by `Wekui.Curation.merge_claims!/4` or
  `Wekui.Curation.distinguish_claims!/4`. Deterministic and read-only: no model.
  """

  alias Wekui.Narrative
  alias Wekui.Normalize

  # Two claim kinds agree when their FIRST words agree. `kind` is an open string the
  # extractor writes, and it writes one change at wildly different lengths —
  # "búsqueda" and "búsqueda de persona desaparecida", "colapso" and "colapso de
  # edificio", "cifra oficial" and "cifra oficial de fallecidos y heridos". Measured
  # across two independent extractions of the same nine posts, comparing the whole
  # string caught one real duplicate out of eight; comparing the head caught them
  # all, and still refuses "búsqueda" against "rescate".
  @head_threshold 0.9

  # Whole-string agreement still counts, for the pairs that are simply worded alike.
  @kind_threshold 0.8

  # How alike two subjects must read to be worth a person's attention.
  @subject_threshold 0.82

  # A generic subject proves nothing on its own, so its pair must also sit close in
  # time. Wide on purpose: a rescue reported at one minute and again at noon is one
  # rescue, and the report is cheap while a missed duplicate is not.
  @hours 36

  @doc """
  Every pair of current Claims in `event_id` that may be one happening, strongest
  first.

  Each entry is `%{claim:, other:, score:, why:}` where `other` is the earlier
  account — the canonical, since a happening lives at its first evidence — and
  `claim` the later one a merge would fold into it.
  """
  def find(event_id) do
    claims =
      event_id
      |> Narrative.current_claims!()
      |> Enum.map(&detail/1)
      |> Enum.sort_by(&{&1.claim.first_seen_at, &1.claim.inserted_at, &1.claim.id})

    for {elder, i} <- Enum.with_index(claims),
        younger <- Enum.drop(claims, i + 1),
        same_kind?(elder, younger),
        marks(elder.subject) == marks(younger.subject),
        score = closeness(elder, younger),
        score >= @subject_threshold,
        together?(elder, younger, score) do
      %{
        claim: younger.claim,
        other: elder.claim,
        score: score,
        why: why(elder, younger)
      }
    end
    |> Enum.sort_by(&(-&1.score))
  end

  defp detail(claim) do
    %{
      claim: claim,
      subject: Normalize.fold(claim.subject || ""),
      places: claim.id |> Narrative.list_claim_places!() |> MapSet.new(& &1.place_id)
    }
  end

  # A search and a rescue are two happenings in one story — a person's arc, which is
  # not a merge. Only the same kind of change can be the same happening.
  defp same_kind?(elder, younger) do
    one = Normalize.fold(elder.claim.kind)
    other = Normalize.fold(younger.claim.kind)

    String.jaro_distance(head(one), head(other)) >= @head_threshold or
      String.jaro_distance(one, other) >= @kind_threshold
  end

  # The word the kind leads with — the change itself, before the extractor's trailing
  # description of it.
  defp head(kind) do
    case String.split(kind, " ", trim: true) do
      [first | _rest] -> first
      [] -> kind
    end
  end

  defp closeness(elder, younger), do: String.jaro_distance(elder.subject, younger.subject)

  # The same rule the gazetteer learned on places, and for the same reason: "un hombre
  # de 21 años" and "un hombre de 31 años" read 0.97 alike and are two different men.
  # The number that differs is the number that identifies. Only the subject's numbers
  # count — a magnitude honestly differs between two accounts of one happening, where
  # an age does not.
  defp marks(subject) do
    ~r/\d+/ |> Regex.scan(subject) |> Enum.map(fn [digits] -> digits end) |> Enum.sort()
  end

  # The specificity rule. A subject carrying a number is its own mark and holds across
  # a wrong place; a generic one needs the place and the clock to agree.
  defp together?(elder, younger, _score) do
    if specific?(elder.subject) and specific?(younger.subject) do
      true
    else
      shares_place?(elder, younger) and near_in_time?(elder, younger)
    end
  end

  # "un hombre de 21 años" carries its own identity; "una mujer" does not. A number is
  # the mark the vocabulary names — an age, a count, an hour.
  defp specific?(subject), do: Regex.match?(~r/\d/, subject)

  # Both empty means neither claim was placed, which is not agreement about anything.
  defp shares_place?(elder, younger) do
    not MapSet.disjoint?(elder.places, younger.places) and MapSet.size(elder.places) > 0
  end

  defp near_in_time?(elder, younger) do
    abs(DateTime.diff(elder.claim.first_seen_at, younger.claim.first_seen_at, :hour)) <= @hours
  end

  defp why(elder, younger) do
    hours = abs(DateTime.diff(elder.claim.first_seen_at, younger.claim.first_seen_at, :hour))

    mark =
      if specific?(elder.subject) and specific?(younger.subject),
        do: "The subject carries its own mark, which holds even across a wrong place",
        else: "Both are at the same place, #{hours}h apart, and the subject is generic"

    "“#{younger.claim.kind} — #{younger.claim.subject}” and " <>
      "“#{elder.claim.kind} — #{elder.claim.subject}” may be one happening. #{mark}."
  end
end
