defmodule Wekui.Narrative.PersonDuplicates do
  @moduledoc """
  Finds [[person]] rows that may be one human being, so the same person is not counted
  twice in everything the record later says.

  Places have `Wekui.Gazetteer.Duplicates` and claims have `Wekui.Narrative.Duplicates`.
  People had nothing, and people are the only one of the three who are human beings in a
  memorial. Measured on the pilot event: **668 rows, zero exact name collisions** — which
  is exactly why nothing noticed — and one woman holding four of them.

  ## It proposes candidates. It never decides.

  Deciding is `Wekui.Pipelines.PersonJudge`'s, because the answer needs meaning and not
  string distance: `Belkys`/`Beky` is one woman sharing almost no letters, while `José
  Luis Pérez`/`José Luis Ramírez` share almost everything and are two men. This module's
  only job is to narrow 668 rows — **222,778 pairs** — into blocks small enough to be
  answerable, and it is tuned for RECALL: a pair it never proposes is a pair nobody ever
  rules on.

  ## Two ways in, because names alone have a ceiling

    * **by name** — a Spanish-aware phonetic fold, then recall over the shorter name's
      own words. Catches `Belkis`/`Belkys` and `Rey Rujano`/`Reyrujan`.
    * **by context** — rows whose claims sit at the same place within a day and share at
      least one word. Measured, this found **152 pairs the name rule missed**, among them
      `Ezio Narducci`/`Miriam Narducci` and `Ulises Rojas`/`Sinayt Rojas`.

  ## Two rules the spike had to learn, both already paid for elsewhere

    * **A one-word name is a hub.** `Adriana` reads alike to `Adriana Patricia Flores`,
      `Adriana Pérez Pérez` and `Adriana Utrer` — three different women. A bare given
      name carries no identity, exactly as a generic subject carries none, so it makes no
      name edge and may only be joined by context.
    * **A block is a NEIGHBOURHOOD, not a connected component.** Transitive closure
      chained **223 unrelated people** into one block — the same clique defect that made a
      61-claim group of the duplicate finder. A row and its direct neighbours is bounded
      by construction and cannot chain.

  Together those took the blocking from 68 blocks with a largest of 223 to **144 blocks
  with a largest of 16**.
  """

  alias Wekui.Narrative
  alias Wekui.Normalize

  # How alike two names must sound to be worth asking about. Loose on purpose — this
  # stage over-groups, and the judge is what refuses.
  @bar 0.88

  # Two claims a day apart at one place are the same episode of one disaster.
  @hours 24

  # A word too short to identify anyone: "de", "la", "del" join everything.
  @shortest 4

  # How alike two name-words must sound to be the same word.
  @same 0.9

  @doc """
  Blocks of Persons in `event_id` that may include one human being written twice,
  largest first. Each entry is `%{persons:, size:}`.

  Merged-away rows are never offered: they have already been ruled on.
  """
  def find(event_id) do
    people = Narrative.current_persons!(event_id)
    by_id = Map.new(people, &{&1.id, &1})
    keyed = Map.new(people, &{&1.id, keys(&1.full_name || "")})
    detail = Map.new(people, &{&1.id, detail(&1)})

    name_edges =
      for {a, i} <- Enum.with_index(people),
          b <- Enum.drop(people, i + 1),
          alike?(keyed[a.id], keyed[b.id]),
          do: {a.id, b.id}

    context_edges =
      for {a, i} <- Enum.with_index(people),
          b <- Enum.drop(people, i + 1),
          MapSet.size(detail[a.id].places) > 0,
          not MapSet.disjoint?(detail[a.id].places, detail[b.id].places),
          near?(detail[a.id], detail[b.id]),
          shares_a_word?(keyed[a.id], keyed[b.id]),
          do: {a.id, b.id}

    (name_edges ++ context_edges)
    |> Enum.uniq()
    |> neighbourhoods()
    |> Enum.map(fn block ->
      %{
        persons: block |> Enum.map(&by_id[&1]) |> Enum.sort_by(& &1.full_name),
        size: MapSet.size(block)
      }
    end)
    |> Enum.sort_by(&(-&1.size))
  end

  @doc """
  Whether two names are the same person **by position** — the same first name, and
  everything the shorter name says after it also said by the longer.

  This is the operator's rule, and it is code rather than prose for a measured reason: as
  a prompt it did not hold. Told in its own text that *"Belkis and Belkys are one name"*,
  the model split them anyway in every run, because the family signal beside it outranked
  the spelling rule. Precedence a model must apply to every pair in a fixed order belongs
  in code — so a pair this returns true for never reaches the judge at all.

  A one-word name answers `false`: a bare given name identifies nobody.
  """
  def same_by_position?(one, other) do
    case {keys(one), keys(other)} do
      {[_alone], _} ->
        false

      {_, [_alone]} ->
        false

      {[], _} ->
        false

      {_, []} ->
        false

      {[first_a | tail_a], [first_b | tail_b]} ->
        sounds_alike?(first_a, first_b) and same_surnames?(tail_a, tail_b)
    end
  end

  # WHICH WORD IS THE FIRST SURNAME CANNOT BE READ OFF THE POSITION. "José Luis Pérez" is
  # a first name, a middle name and one surname; "José Pérez García" is a first name and
  # two surnames. Both are three words. So this counts no positions — it asks whether
  # everything the SHORTER name says after the first name is also said by the longer one.
  # A dropped middle name or second surname then costs nothing, while a surname that is
  # simply different fails.
  defp same_surnames?(one, other) do
    {short, long} = if length(one) <= length(other), do: {one, other}, else: {other, one}

    short != [] and
      (Enum.all?(short, fn word -> Enum.any?(long, &sounds_alike?(word, &1)) end) or
         sounds_alike?(Enum.join(short), Enum.join(long)))
  end

  defp sounds_alike?(a, b), do: String.jaro_distance(a, b) >= @same

  ## ─────────────────────────── sounding it out ───────────────────────────

  @doc """
  A Spanish name reduced to how it SOUNDS. Each rule is one confusion a frightened
  relative actually types: Spanish does not distinguish b from v, or s from z from soft
  c; h is silent; ll and y are one sound; a final y is the vowel i.
  """
  def phonetic(word) do
    word
    |> Normalize.fold()
    |> String.replace("v", "b")
    |> String.replace("h", "")
    |> String.replace("ll", "y")
    |> String.replace("qu", "k")
    |> String.replace(~r/gu([ei])/, "g\\1")
    |> String.replace(~r/c([ei])/, "s\\1")
    |> String.replace("z", "s")
    |> String.replace("c", "k")
    |> String.replace("y", "i")
    |> String.replace(~r/(.)\1+/, "\\1")
  end

  defp keys(name) do
    name
    |> Normalize.fold()
    |> String.split(" ", trim: true)
    |> Enum.map(&phonetic/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Recall over the SHORTER name's own words: "belkys barreto" against "belkis josefina
  # barreto garcia" reads 0.70 as a whole string and 0.944 by words, and it is one woman.
  defp alike?(a, b) do
    {short, long} = if length(a) <= length(b), do: {a, b}, else: {b, a}

    case short do
      # A one-word name is a hub; it may only be joined by context.
      [_bare_given_name] ->
        false

      [] ->
        false

      short ->
        short
        |> Enum.map(fn word ->
          long |> Enum.map(&String.jaro_distance(word, &1)) |> Enum.max()
        end)
        |> then(&(Enum.sum(&1) / length(&1)))
        |> Kernel.>=(@bar)
    end
  end

  # Without this, everyone in one building is a candidate for everyone else in it.
  defp shares_a_word?(a, b) do
    Enum.any?(a, fn word ->
      String.length(word) >= @shortest and
        Enum.any?(b, &(String.jaro_distance(word, &1) >= 0.86))
    end)
  end

  defp near?(one, other) do
    Enum.any?(one.at, fn a ->
      Enum.any?(other.at, &(abs(DateTime.diff(a, &1, :hour)) <= @hours))
    end)
  end

  defp detail(person) do
    claims =
      person.id
      |> Narrative.person_arc!()
      |> Enum.map(fn link ->
        case Narrative.get_claim(link.claim_id) do
          {:ok, claim} -> claim
          {:error, _gone} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    places =
      claims
      |> Enum.flat_map(fn claim ->
        claim.id |> Narrative.list_claim_places!() |> Enum.map(& &1.place_id)
      end)
      |> MapSet.new()

    %{
      claims: claims,
      places: places,
      at: claims |> Enum.map(& &1.first_seen_at) |> Enum.reject(&is_nil/1)
    }
  end

  ## ─────────────────────────── blocks ───────────────────────────

  # A row and its DIRECT neighbours. A neighbourhood wholly inside another says nothing
  # the larger one does not, so it is dropped; the rest may overlap, and the judge's
  # answers are reconciled afterwards.
  defp neighbourhoods(edges) do
    adjacency =
      Enum.reduce(edges, %{}, fn {a, b}, acc ->
        acc |> Map.update(a, [b], &[b | &1]) |> Map.update(b, [a], &[a | &1])
      end)

    all =
      adjacency
      |> Enum.map(fn {id, neighbours} -> MapSet.new([id | neighbours]) end)
      |> Enum.uniq()

    Enum.reject(all, fn block ->
      Enum.any?(all, &(MapSet.size(&1) > MapSet.size(block) and MapSet.subset?(block, &1)))
    end)
  end

  @doc """
  Who each Person is named BESIDE — the other Persons a claim names in the same breath.

  Read the right way round this is the strongest signal there is, and it points at
  DIFFERENT: families live together, so families were buried together, and one post asks
  after a whole household at once. Being named together means a brother and a sister, not
  one person written twice. Offered to a model as evidence of SAMENESS it merged whole
  families; inverted, it was the best-scoring and only stable prompt tried.
  """
  def beside(event_id) do
    event_id
    |> Narrative.current_claims!()
    |> Enum.flat_map(fn claim ->
      ids = claim.id |> Narrative.list_claim_persons!() |> Enum.map(& &1.person_id) |> Enum.uniq()
      for a <- ids, b <- ids, a != b, do: {a, b}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, others} -> {id, MapSet.new(others)} end)
  end
end
