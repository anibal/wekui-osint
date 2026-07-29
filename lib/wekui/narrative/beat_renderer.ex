defmodule Wekui.Narrative.BeatRenderer do
  @moduledoc """
  Renders the [[claim]]s that hold for a [[place]] and an interval into the Spanish a
  reader meets — a [[beat]] (`docs/pages/beat.md`, `docs/beat-scenarios.md`). Derived,
  never authored: it reads claim fields and words them, and cannot invent a fact.

  **Deterministic, no LLM over the LLM.** Prose is composed from claim fields by a
  per-`kind` template (matched on keywords, since `kind` is an open string) plus an
  anaphora pass and light connectives. `render/3` returns BOTH the assembled `prose`
  AND the structured `clauses` it was built from — the structured form is the
  "preprocessed options" a future LLM *polish* pass would refine, so the deterministic
  90% is never thrown away.

  Scope holds by construction: only claims whose place is in the target place's SUBTREE,
  current, and evidenced within the interval. The person red line is honoured at the
  point it bites — a person shows by their `display_handle` (e.g. "Aaron C."), later by
  first name (anaphora within the beat), or by role when there is no resolved person
  (minors carry none); never a raw name. Gender-neutral phrasings are chosen on purpose
  so the deterministic pass never guesses agreement.

  This iteration (per `docs/beat-scenarios.md`): no approval gate (render everything),
  CURRENT status only, group by place, an unsupported/overstated claim is ATTRIBUTED
  ("según un reporte sin confirmar") rather than dropped, day grain, per-claim citations.
  """

  alias Wekui.Capture
  alias Wekui.Core
  alias Wekui.Narrative
  alias Wekui.Narrative.ClaimPlace
  alias Wekui.Taxonomy
  alias Wekui.Tree

  require Ash.Query

  @doc """
  Renders a beat for `place_id` over `[from, to]`. Returns
  `%{place, from, to, clauses, prose, sources}` — `clauses` is the structured
  intermediate (one per claim, in reading order), `prose` the assembled Spanish, and
  `sources` the numbered citations resolving to posts.
  """
  def render(place_id, from, to) do
    place = Core.get_place!(place_id)
    subtree = Tree.subtree_ids(Core.Place, place_id)

    ordered = subtree |> in_scope_claims(from, to) |> order_by_place(subtree)

    {clauses, _seen, sources} =
      Enum.reduce(ordered, {[], MapSet.new(), []}, &render_one/2)

    clauses = Enum.reverse(clauses)

    %{
      place: place,
      from: from,
      to: to,
      clauses: clauses,
      sources: Enum.reverse(sources),
      prose: assemble(clauses)
    }
  end

  ## ─────────────────────────── gathering & ordering ───────────────────────────

  defp in_scope_claims(subtree, from, to) do
    ClaimPlace
    |> Ash.Query.filter(place_id in ^subtree)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.claim_id)
    |> Enum.uniq()
    |> Enum.map(&Narrative.get_claim!/1)
    |> Enum.filter(fn c ->
      is_nil(c.superseded_at) and not before?(c.first_seen_at, from) and
        not before?(to, c.first_seen_at) and themed?(c)
    end)
  end

  # THE GATE. A claim reaches a reader only if the record can say what KIND of
  # happening it is — which means a [[theme]] a person has taken into the vocabulary.
  #
  # A claim with no theme predates the vocabulary. Its `kind` is whatever a model
  # typed, and nothing could refuse one: that is how "¿alguien tiene información sobre
  # residencias Albatros?" became *a person is missing*, twenty-three times, and how
  # `solicitud de información sobre edificio: []` — a field name, a colon and nothing
  # — reached the memorial's Spanish.
  #
  # Those claims stay on the record: they are honest accounts of what the extractor
  # read, and the record is append-only. They simply do not speak until a themed
  # reading supersedes them.
  defp themed?(claim) do
    case claim.theme_id && Taxonomy.get_theme(claim.theme_id) do
      {:ok, %{lifecycle: :active, nature: :happening}} -> true
      _no_ratified_happening -> false
    end
  end

  defp before?(a, b), do: DateTime.compare(a, b) == :lt

  # Group by the claim's anchor place (its finest place inside the subtree), order the
  # groups by their earliest claim, and each group by time — the simplest ordering that
  # reads coherently. (Alternative left for later: a single chronological sweep across
  # places; it reads more jumpily when places interleave in time.)
  defp order_by_place(claims, subtree) do
    subtree_set = MapSet.new(subtree)

    claims
    |> Enum.map(fn c -> {c, anchor_place(c, subtree_set)} end)
    |> Enum.group_by(fn {_c, anchor} -> anchor && anchor.id end)
    # DateTime needs its own sorter here too: default term ordering compares the
    # structs field by field in key order — day before month before year — so
    # groups would read out in an order that is not chronological at all.
    |> Enum.sort_by(
      fn {_id, pairs} ->
        pairs |> Enum.map(fn {c, _} -> c.first_seen_at end) |> Enum.min(DateTime)
      end,
      DateTime
    )
    |> Enum.flat_map(fn {_id, pairs} ->
      pairs
      |> Enum.sort_by(fn {c, _} -> c.first_seen_at end, DateTime)
      |> Enum.map(fn {c, anchor} -> %{claim: c, anchor: anchor} end)
    end)
  end

  # The deepest place the claim links to that lies in the subtree — the most specific
  # place it belongs to for grouping.
  defp anchor_place(claim, subtree_set) do
    claim.id
    |> Narrative.list_claim_places!()
    |> Enum.map(&Core.get_place!(&1.place_id))
    |> Enum.filter(&MapSet.member?(subtree_set, &1.id))
    |> Enum.max_by(&length(Tree.ancestor_ids(Core.Place, &1.id)), fn -> nil end)
  end

  ## ─────────────────────────── rendering one claim ───────────────────────────

  defp render_one(%{claim: claim, anchor: anchor}, {clauses, seen, sources}) do
    {persons, seen} = person_phrase(claim, seen)
    {cites, sources} = cite(claim, sources)

    ctx = %{
      # The THEME, never `kind`. A claim only reaches here filed under a theme a
      # person ratified, so this string is curated Spanish — not whatever a model
      # typed. `kind` stays on the claim as provenance and is never displayed.
      theme: theme_name(claim),
      subject: claim.subject,
      status: claim.status,
      magnitude: claim.magnitude,
      person: persons
    }

    text = ctx |> clause() |> attribute(claim.support)

    entry = %{
      claim_id: claim.id,
      kind: claim.kind,
      place_id: anchor && anchor.id,
      place_name: anchor && anchor.canonical_name,
      text: text,
      support: claim.support,
      cite_ns: Enum.map(cites, & &1.n)
    }

    {[entry | clauses], seen, sources}
  end

  # A person shows by handle + role on first mention, first name after (anaphora within
  # the beat), or the claim's role when no person is resolved (minors carry none).
  defp person_phrase(claim, seen) do
    persons =
      claim.id
      |> Narrative.list_claim_persons!()
      |> Enum.map(&Narrative.get_person!(&1.person_id))
      |> Enum.filter(& &1.display_handle)

    case persons do
      [] ->
        {claim.subject, seen}

      [one] ->
        if MapSet.member?(seen, one.id) do
          {first_name(one.display_handle), seen}
        else
          phrase =
            [one.display_handle, claim.subject]
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join(", ")

          {phrase, MapSet.put(seen, one.id)}
        end

      many ->
        phrase = many |> Enum.map(& &1.display_handle) |> join_y()
        {phrase, Enum.reduce(many, seen, &MapSet.put(&2, &1.id))}
    end
  end

  defp first_name(handle), do: handle |> String.split() |> hd()

  defp theme_name(claim) do
    case claim.theme_id && Taxonomy.get_theme(claim.theme_id) do
      {:ok, theme} -> theme.name
      _unfiled -> nil
    end
  end

  ## ─────────────────────────── per-theme templates ───────────────────────────

  # THE VOCABULARY IS THE DISPATCH TABLE. This matched `kind` — an open string —
  # against five keyword families with a fallback that printed `"#{kind}: #{subject}"`,
  # which is a field name and a colon, in a public memorial. It is how
  # `solicitud de información sobre edificio: []` and
  # `70% de edificios afectados en Tanaguarena: []` reached the reader.
  #
  # Now it dispatches on the theme: a closed, ratified, curated set of Spanish names.
  # The families stay because a theme's name reads the way its family reads, and the
  # fallback can no longer print a field — the worst it can do is say plainly that
  # something of a named kind occurred.
  defp clause(ctx) do
    k = String.downcase(ctx.theme || "")

    cond do
      # Ordered by specificity so an overlapping keyword can't misfire: a toll that
      # mentions "fallecidos" is a toll, not a death; a body found "entre rescatistas"
      # is a death, not a rescue (rescue matches `rescat[ae]`, never "rescatista").
      k =~ ~r/cifra|balance|damnific/ -> toll_clause(ctx)
      k =~ ~r/colaps|derrumb|desplom/ -> collapse_clause(ctx)
      k =~ ~r/desaparec|búsqueda|busqueda|buscan|paradero|localiz/ -> search_clause(ctx)
      k =~ ~r/cuerpo|fallec|muert|cadáver|cadaver|víctima|victima/ -> death_clause(ctx)
      k =~ ~r/rescat[ae]|salvad/ -> rescue_clause(ctx)
      true -> generic_clause(ctx)
    end
  end

  defp rescue_clause(ctx) do
    tras = trapped(ctx.magnitude)

    if to_string(ctx.status) =~ ~r/rescatad|salvad|con vida/ do
      "los equipos rescataron con vida a #{ctx.person}#{tras}"
    else
      "los equipos trabajaron para rescatar con vida a #{ctx.person}#{tras}"
    end
  end

  defp search_clause(ctx), do: "se buscaba a #{ctx.person}"

  defp collapse_clause(_ctx), do: "el edificio colapsó tras el terremoto"

  defp death_clause(ctx), do: "fue recuperado el cuerpo de #{ctx.person || "una persona"}"

  defp toll_clause(ctx) do
    m = ctx.magnitude || %{}
    dead = num(m["fallecidos"] || m["muertos"] || m["deaths"])
    hurt = num(m["heridos"] || m["injured"])

    parts =
      [dead && "#{dead} fallecidos", hurt && "#{hurt} heridos"]
      |> Enum.reject(&is_nil/1)
      |> join_y()

    if parts == "",
      do: "el balance oficial fue actualizado",
      else: "el balance oficial reportó #{parts}"
  end

  # Never a field name, never a bare colon, never an empty slot. A theme the families
  # do not know still has a curated Spanish name, so the honest thing is to say that
  # it happened — and to name whom, when the claim knows.
  defp generic_clause(ctx) do
    what = ctx.theme |> to_string() |> String.trim() |> lower_first()
    whom = ctx.person || ctx.subject

    case {what, whom} do
      {"", nil} -> "se registró un hecho"
      {"", who} -> "se registró un hecho relativo a #{who}"
      {what, nil} -> "se registró #{article(what)}#{what}"
      {what, who} -> "se registró #{article(what)}#{what}, relativo a #{who}"
    end
  end

  # The vocabulary's names are written as labels ("Colapso estructural"), so they need
  # an article to sit inside a sentence. Spanish gender is guessed from the ending —
  # wrong sometimes, and a wrong article reads as a typo while a missing one reads as
  # a machine. The LLM polish pass the operator described is what fixes this properly.
  defp article(what) do
    cond do
      String.starts_with?(what, ["un ", "una ", "el ", "la ", "los ", "las "]) -> ""
      String.match?(what, ~r/^[^\s]*(a|ción|sión|dad)\b/u) -> "una "
      true -> "un "
    end
  end

  defp lower_first(""), do: ""
  defp lower_first(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest

  defp trapped(%{"hours" => h}) when not is_nil(h), do: ", tras #{h} horas bajo los escombros"
  defp trapped(%{"horas" => h}) when not is_nil(h), do: ", tras #{h} horas bajo los escombros"
  defp trapped(_), do: ""

  # An unsupported/overstated claim is told as a report, never as plain fact.
  defp attribute(text, support) when support in [:overstated, :unsupported] do
    "según un reporte sin confirmar, " <> text
  end

  defp attribute(text, _support), do: text

  ## ─────────────────────────── citations & assembly ───────────────────────────

  defp cite(claim, sources) do
    posts =
      claim.id
      |> Narrative.list_claim_citations!()
      |> Enum.map(&Capture.get_post!(&1.post_id))

    Enum.reduce(posts, {[], sources}, fn post, {acc, srcs} ->
      n = length(srcs) + 1
      src = %{n: n, post_id: post.id, x_id: post.x_id}
      {[src | acc], [src | srcs]}
    end)
    |> then(fn {added, srcs} -> {Enum.reverse(added), srcs} end)
  end

  # Group consecutive clauses by place ("En {place}, …"); a place repeated in a row uses
  # a connective ("además") instead of re-naming it.
  defp assemble(clauses) do
    clauses
    |> Enum.chunk_by(& &1.place_id)
    |> Enum.map(&render_group/1)
    |> Enum.join(" ")
  end

  defp render_group([first | _] = group) do
    header = if first.place_name, do: "En #{first.place_name}, ", else: ""

    body =
      group
      |> Enum.map(fn c -> "#{c.text}#{marks(c.cite_ns)}" end)
      |> Enum.join("; ")

    upcase_first(header <> body) <> "."
  end

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(s), do: s

  defp marks([]), do: ""
  defp marks(ns), do: ns |> Enum.map(&"[#{&1}]") |> Enum.join()

  defp join_y([]), do: ""
  defp join_y([one]), do: one
  defp join_y(list), do: "#{Enum.join(Enum.drop(list, -1), ", ")} y #{List.last(list)}"

  defp num(nil), do: nil

  defp num(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  defp num(n), do: to_string(n)
end
