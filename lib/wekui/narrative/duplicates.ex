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

  ## Pairs are the unit it finds; groups are the unit a person reads

  `find/1` is pairwise because the rule above is pairwise. A corpus is not: 258 accounts
  of one building's collapse make thousands of pairs that say one thing. `cluster/1`
  joins the pairs back into the groups they describe — measured, **3,213 pairs were 261
  groups** — and that is the surface a person is given. See `cluster/1` for why a group
  is a candidate and never an assertion.
  """

  alias Wekui.Core
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

  # How alike two [[person]]s' names must read to be the same human being. The same
  # 0.92 the gazetteer settled on for places, reached from the other side: measured on
  # the corpus, one woman held four Person rows — "belkys josefina barreto garcia",
  # "belkis josefina barreto garcia", "belkys barreto", "belkis barreto" — and they
  # score 0.944 and up, while "gladismaria pineda ramirez" against "mirta guedez"
  # scores 0.567 and "jose luis perez" against "jose luis ramirez" scores 0.892.
  @name_threshold 0.92

  @doc """
  Every pair of current Claims in `event_id` that may be one happening, strongest
  first.

  Each entry is `%{claim:, other:, score:, subjects:, why:}` where `other` is the
  earlier account — the canonical, since a happening lives at its first evidence — and
  `claim` the later one a merge would fold into it.

  `subjects` says what the pair actually rests on, and it orders the list ahead of
  `score`: `:mark` (both subjects carry a number, which identifies), `:generic` (both
  name a subject that does not), `:absent` (neither names one at all). **A blank
  subject scores 1.0 against another blank subject** — `String.jaro_distance("", "")`
  is 1.0 — so sorting on the number alone put 2,467 pairs resting on nothing at the top
  of a person's queue, ahead of every pair resting on something. The number was not
  wrong; it was answering a question nobody asked.
  """
  def find(event_id) do
    names = names_by_person(event_id)
    scopes = scope_places(event_id)

    claims =
      event_id
      |> Narrative.current_claims!()
      |> Enum.map(&detail(&1, names, scopes))
      |> Enum.sort_by(&{&1.claim.first_seen_at, &1.claim.inserted_at, &1.claim.id})

    for {elder, i} <- Enum.with_index(claims),
        younger <- Enum.drop(claims, i + 1),
        same_kind?(elder, younger),
        marks(elder.subject) == marks(younger.subject),
        not different_people?(elder, younger),
        score = closeness(elder, younger),
        score >= @subject_threshold,
        together?(elder, younger, score) do
      %{
        claim: younger.claim,
        other: elder.claim,
        score: score,
        subjects: subjects(elder, younger),
        why: why(elder, younger)
      }
    end
    |> Enum.sort_by(&{rank(&1.subjects), -&1.score})
  end

  @doc """
  Groups `pairs` into the connected sets of Claims they join, largest first.

  **The finder reports pairs where a person needs groups.** 258 claims of one building's
  collapse produce hundreds of pairs saying one thing — that many accounts describe that
  collapse — and printed as pairs they are a wall. Measured on the corpus, 3,213 pairs
  were **261 groups**, and twelve of them held 77% of the pairs; one clique of 61 claims
  held 1,516 pairs by itself, 47% of everything.

  Each entry is `%{claims:, pairs:, size:}`.

  **A group is a candidate, not an assertion.** Connectedness is not transitive
  identity: `equipo USAR El Salvador` and `equipo USAR de Perú` are two teams, and both
  join a generic `equipo extranjero`, so one group holds all three. What a group says is
  *these accounts are worth looking at together* — nothing more. It follows that
  pairwise judging is the wrong instrument inside a dense group: refuting one edge
  leaves the group whole through any other path. A dense group needs a partition, and a
  partition is a [[person]]'s.
  """
  def cluster(pairs) do
    claims = pairs |> Enum.flat_map(&[&1.claim, &1.other]) |> Map.new(&{&1.id, &1})

    adjacency =
      Enum.reduce(pairs, %{}, fn pair, acc ->
        acc
        |> Map.update(pair.claim.id, [pair.other.id], &[pair.other.id | &1])
        |> Map.update(pair.other.id, [pair.claim.id], &[pair.claim.id | &1])
      end)

    {groups, _seen} =
      Enum.reduce(Map.keys(adjacency), {[], MapSet.new()}, fn id, {groups, seen} ->
        if MapSet.member?(seen, id) do
          {groups, seen}
        else
          group = reachable(adjacency, id)
          {[group | groups], MapSet.union(seen, group)}
        end
      end)

    groups
    |> Enum.map(fn group ->
      %{
        claims: group |> Enum.map(&claims[&1]) |> Enum.sort_by(& &1.first_seen_at),
        pairs: Enum.filter(pairs, &MapSet.member?(group, &1.claim.id)),
        size: MapSet.size(group)
      }
    end)
    |> Enum.sort_by(&{-&1.size, -length(&1.pairs)})
  end

  # Breadth-first, iterative: a group can hold sixty claims and a deep recursion over a
  # dense clique is a stack this does not need to spend.
  defp reachable(adjacency, start) do
    walk(adjacency, [start], MapSet.new([start]))
  end

  defp walk(_adjacency, [], seen), do: seen

  defp walk(adjacency, [id | rest], seen) do
    fresh = adjacency |> Map.get(id, []) |> Enum.reject(&MapSet.member?(seen, &1)) |> Enum.uniq()
    walk(adjacency, rest ++ fresh, Enum.reduce(fresh, seen, &MapSet.put(&2, &1)))
  end

  # What the pair rests on. An absent subject is not a generic one: "una mujer" at least
  # says a woman, and nothing says nothing.
  defp subjects(elder, younger) do
    cond do
      specific?(elder.subject) and specific?(younger.subject) -> :mark
      elder.subject == "" or younger.subject == "" -> :absent
      true -> :generic
    end
  end

  defp rank(:mark), do: 0
  defp rank(:generic), do: 1
  defp rank(:absent), do: 2

  defp detail(claim, names, scopes) do
    %{
      claim: claim,
      subject: Normalize.fold(claim.subject || ""),
      places: claim.id |> Narrative.list_claim_places!() |> MapSet.new(& &1.place_id),
      scopes: scopes,
      people:
        claim.id
        |> Narrative.list_claim_persons!()
        |> Enum.map(&Map.get(names, &1.person_id))
        |> Enum.reject(&(&1 in [nil, ""]))
    }
  end

  # THE RECORD ALREADY KNOWS WHO. When both accounts name whom they are about, the
  # names decide before any similarity of wording gets a vote — "una mujer de 60 años"
  # reads 1.0 against "una mujer de 60 años" and there were two of them, missing in the
  # same building. Measured, this refuses 122 of 3,213 pairs, and the adversarial judge
  # had upheld five of them as one happening: five people who would have been merged
  # away.
  #
  # It fires only when BOTH sides name someone. An unlinked claim asserts nothing about
  # identity, and absence is never disagreement — the same line drawn for a blank
  # subject and for an unaudited residue entry.
  defp different_people?(elder, younger) do
    elder.people != [] and younger.people != [] and
      not Enum.any?(elder.people, fn one ->
        Enum.any?(younger.people, &same_name?(one, &1))
      end)
  end

  # Recall over the SHORTER name's own words, not a whole-string comparison — the
  # ThemeResolver's lesson, and the corpus needs it: "belkys barreto" against "belkis
  # josefina barreto garcia" is one woman and scores 0.70 whole against 0.944 by words.
  # A dropped middle name is a matter of how much someone wrote down, not of who they
  # meant.
  defp same_name?(one, other) do
    {short, long} =
      case {String.split(one, " ", trim: true), String.split(other, " ", trim: true)} do
        {a, b} when length(a) <= length(b) -> {a, b}
        {a, b} -> {b, a}
      end

    case short do
      [] ->
        false

      short ->
        short
        |> Enum.map(fn word ->
          long |> Enum.map(&String.jaro_distance(word, &1)) |> Enum.max()
        end)
        |> then(&(Enum.sum(&1) / length(&1)))
        |> Kernel.>=(@name_threshold)
    end
  end

  defp names_by_person(event_id) do
    event_id
    |> Narrative.list_persons!()
    |> Map.new(&{&1.id, Normalize.fold(&1.normalized_name || &1.full_name || "")})
  end

  # The places that say WHERE THE CORPUS IS rather than where a happening was. An
  # administrative container holds the whole event by definition, so two accounts both
  # sitting in one is not a coincidence worth reporting. A `barrio` and a `sector` are
  # left in deliberately: they are coarse too, and cutting them as well took 1,099 pairs
  # to 989, but the finder's job is recall and the gate is downstream — a duplicate
  # never offered is a duplicate nobody ever rules on.
  @scope_types ~w(pais estado municipio parroquia)

  defp scope_places(event_id) do
    event_id
    |> Core.list_places!()
    |> Enum.filter(&(Normalize.fold(&1.type || "") in @scope_types))
    |> MapSet.new(& &1.id)
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
  #
  # And a place only tells two accounts apart if it could have told them apart. The
  # SCOPE places cannot: 380 of 2,596 claims sit at «Caraballeda» the parroquia and 62
  # at «La Guaira» the estado, because that is where the whole corpus is. Counting them
  # as agreement made one group of 61 support claims and another of 35 collapses, which
  # between them held 1,740 of the finder's 3,213 pairs — 54% of a person's queue,
  # saying only that everything happened in Caraballeda. Requiring a place finer than a
  # parroquia cut 3,120 pairs to 1,099 and the largest group from 61 accounts to 19.
  #
  # This is the pair-judge prompt's own sentence — *"a parish named in both is nearly
  # worthless, because everything here is in that parish"* — moved from rung five of
  # `docs/mechanisms.md` down to rung one, where it costs nothing and never varies.
  defp shares_place?(elder, younger) do
    shared = MapSet.intersection(elder.places, younger.places)

    Enum.any?(shared, &(not MapSet.member?(elder.scopes, &1)))
  end

  defp near_in_time?(elder, younger) do
    abs(DateTime.diff(elder.claim.first_seen_at, younger.claim.first_seen_at, :hour)) <= @hours
  end

  defp why(elder, younger) do
    hours = abs(DateTime.diff(elder.claim.first_seen_at, younger.claim.first_seen_at, :hour))

    mark =
      case subjects(elder, younger) do
        :mark ->
          "The subject carries its own mark, which holds even across a wrong place"

        :generic ->
          "Both are at the same place, #{hours}h apart, and the subject is generic"

        :absent ->
          "NEITHER NAMES A SUBJECT — only the kind, the place and #{hours}h hold them " <>
            "together, which is the weakest thing this offers"
      end

    "“#{named(younger.claim)}” and “#{named(elder.claim)}” may be one happening. #{mark}."
  end

  defp named(claim) do
    case String.trim(claim.subject || "") do
      "" -> claim.kind
      subject -> "#{claim.kind} — #{subject}"
    end
  end
end
