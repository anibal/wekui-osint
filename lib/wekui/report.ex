defmodule Wekui.Report do
  @moduledoc """
  The record, written out as markdown a person can read and answer — the
  cheapest possible review surface until a console exists.

  Two halves, in this order because that is the order attention should go:

    * **What needs your call** — every place the system is honestly unsure and
      has stopped rather than guessed: a mention that matches a name which is
      *also* the beginning of another place's name (the ambiguity an exact
      gazetteer hit hides), a link the resolver scored low, a mention that
      resolved to nothing at all (and so appears in no [[beat]]), the [[person]]s
      waiting on the handle gate, the [[claim]]s the support gate flagged, and
      the [[place]]s a machine proposed. Each is numbered so an answer can name
      it.
    * **The record as it stands** — the beat a reader would meet, then every
      current claim with its evidence, its place and its verdict, then the run
      receipts.

  It reads; it never writes. Nothing here decides anything — that is the point:
  the questions go to a human and come back as deliberate acts through the same
  Ash actions the pipeline uses.

  **This output carries private full names.** The record protects them
  everywhere else — a claim and a beat may only ever show a derived handle — but
  a reviewer cannot confirm that "Aaron C." is the right handle for a name they
  cannot see. So the report shows them, says so at the top, and is written to a
  git-ignored path. It is a working document, not a publishable one.
  """

  alias Wekui.Capture
  alias Wekui.Core
  alias Wekui.Curation
  alias Wekui.Curation.Act
  alias Wekui.Gazetteer.Duplicates
  alias Wekui.Narrative
  alias Wekui.Narrative.Duplicates, as: ClaimDuplicates
  alias Wekui.Narrative.PlaceResolver
  alias Wekui.Normalize
  alias Wekui.Pipelines
  alias Wekui.Tree

  @low_confidence 0.7

  # A question with fifty candidates is a wall, not a question. The rest are
  # counted, never silently dropped.
  @max_candidates 6

  @doc """
  Renders the whole record of `event` as markdown. `opts`: `:at` (the timestamp
  in the header, defaults to now).
  """
  def render(event, opts \\ []) do
    at = Keyword.get_lazy(opts, :at, &DateTime.utc_now/0)
    world = gather(event)
    questions = questions(world)

    [
      header(event, world, questions, at),
      calls(questions),
      settled(world),
      story(world),
      claims_section(world),
      runs_section(world)
    ]
    |> Enum.join("\n")
  end

  ## ─────────────────────────── gathering ───────────────────────────

  # One read of everything the report needs, so the sections below are pure
  # shaping. At pilot scale this is a handful of queries; when the corpus grows
  # past a report you can read in one sitting, this is the thing to page.
  defp gather(event) do
    claims = Narrative.current_claims!(event.id)
    places = Core.list_places!(event.id)
    by_id = Map.new(places, &{&1.id, &1})

    %{
      event: event,
      claims: Enum.map(claims, &detail(&1, by_id)),
      places: places,
      by_id: by_id,
      name_index: name_index(places),
      persons: Narrative.list_persons!(event.id),
      runs: Pipelines.list_runs!(event.id),
      acts: Curation.list_acts!(event.id, load: [:actor])
    }
  end

  defp detail(claim, by_id) do
    links =
      claim.id
      |> Narrative.list_claim_places!()
      |> Enum.map(&%{link: &1, place: Map.get(by_id, &1.place_id)})

    posts =
      claim.id
      |> Narrative.list_claim_citations!()
      |> Enum.map(&Capture.get_post!(&1.post_id))

    persons =
      claim.id
      |> Narrative.list_claim_persons!()
      |> Enum.map(&Narrative.get_person!(&1.person_id))

    %{claim: claim, links: links, posts: posts, persons: persons}
  end

  # Every folded name any active place answers to, canonical and surface alike —
  # the same index the resolver matches against, kept here to ask a different
  # question of it: what ELSE begins with what the posts said.
  defp name_index(places) do
    active = Enum.filter(places, &(&1.lifecycle == :active))

    canonical = Enum.map(active, &{Normalize.fold(&1.canonical_name), &1})

    surface =
      Enum.flat_map(active, fn place ->
        place.id |> Core.list_place_names!() |> Enum.map(&{&1.normalized, place})
      end)

    Enum.uniq(canonical ++ surface)
  end

  ## ─────────────────────────── the questions ───────────────────────────

  defp questions(world) do
    ambiguous = ambiguous_names(world)
    covered = ambiguous |> Enum.flat_map(& &1.claim_ids) |> MapSet.new()

    [
      ambiguous,
      low_confidence(world, covered),
      unresolved(world),
      pending_persons(world),
      flagged_claims(world),
      proposed_places(world),
      duplicate_places(world),
      duplicate_claims(world)
    ]
    |> List.flatten()
    |> Enum.with_index(1)
    |> Enum.map(fn {question, n} -> Map.put(question, :n, n) end)
  end

  # The ambiguity an exact match hides: the posts said a name the gazetteer
  # holds, but that name is ALSO how another place's name begins. "Residencias
  # Caribe" resolves outright to the building that carries it as an alias, while
  # "Residencias Caribe, Torre C" stands next door — the resolver never looks,
  # because an exact hit wins before the ancestors are consulted.
  defp ambiguous_names(world) do
    world.claims
    |> Enum.flat_map(&mention_links/1)
    |> Enum.group_by(& &1.form, & &1)
    |> Enum.flat_map(fn {form, matches} ->
      linked = hd(matches).place

      # A true tie first — two places answering to the SAME name is a sharper
      # question than a name that merely starts alike, and when one exists the
      # look-alikes are noise beside it.
      case rivals(form, world, linked) do
        {:same_name, rivals} -> [same_name(form, matches, rivals)]
        {:begins_alike, []} -> []
        {:begins_alike, rivals} -> [ambiguity(form, matches, rivals)]
      end
    end)
    |> Enum.sort_by(&(-length(&1.claim_ids)))
  end

  # A claim's mention forms paired with the place each one actually links to.
  # One link and one mention is the common case; a claim spanning several places
  # pairs them in order, which is the best available reading without re-running
  # the resolver.
  #
  # A link a human set by hand is dropped: `:manual` IS the answer to "which
  # place did the posts mean", so re-asking it would be the report arguing with
  # a decision it already has. The gazetteer tie stays — this is the one
  # question that cannot suppress itself by watching a status.
  defp mention_links(%{claim: claim, links: links}) do
    forms = claim.place_mention |> PlaceResolver.parse() |> Enum.map(&hd(&1.forms))

    forms
    |> Enum.zip(links)
    |> Enum.reject(fn {_form, %{place: place}} -> is_nil(place) end)
    |> Enum.reject(fn {_form, %{link: link}} -> link.how_resolved == :manual end)
    |> Enum.map(fn {form, %{link: link, place: place}} ->
      %{form: form, place: place, claim: claim, confidence: link.confidence}
    end)
  end

  # Everything else in the gazetteer the posts could have meant. A place that
  # lives BENEATH the one we linked to is not a rival: linking the community
  # when the posts named no tower is the correct coarser answer, and the finer
  # place is reachable the moment a post names it. The tree resolves that
  # ambiguity structurally — so fixing the tree makes the question disappear,
  # which is the point of a recursive model.
  defp rivals(form, world, linked) do
    candidates =
      world.name_index
      |> Enum.reject(fn {_folded, place} -> place.id == linked.id end)
      |> Enum.uniq_by(fn {_folded, place} -> place.id end)

    # A place of the SAME name is a rival wherever it sits — being nested does not
    # help when the mention is word-for-word either one. Only a longer name is
    # settled by the tree.
    case Enum.filter(candidates, fn {folded, _place} -> folded == form end) do
      [] -> {:begins_alike, begins_alike(form, candidates, linked)}
      same -> {:same_name, Enum.map(same, fn {folded, place} -> named(folded, place) end)}
    end
  end

  defp begins_alike(form, candidates, linked) do
    beneath = MapSet.new(Tree.subtree_ids(Core.Place, linked.id))

    candidates
    |> Enum.filter(fn {folded, place} ->
      String.starts_with?(folded, form) and not MapSet.member?(beneath, place.id)
    end)
    |> Enum.map(fn {folded, place} -> named(folded, place) end)
  end

  defp named(folded, place), do: %{name: folded, place: place}

  # Two places carry the same name outright — the resolver had nothing to choose
  # by and picked one. Nothing about the mention can settle this; only a person
  # who knows the ground can.
  defp same_name(form, matches, rivals) do
    linked = hd(matches).place

    %{
      kind: :same_name,
      title: "Two places are called “#{form}” — which one?",
      claim_ids: Enum.map(matches, & &1.claim.id),
      body: """
      The posts said **#{form}**, and the gazetteer holds more than one place of
      exactly that name. The resolver took **#{path(linked)}**#{scored(matches)}
      — there was nothing in the mention to choose by.

      The others:

      #{Enum.map_join(rivals, "\n", &"  - #{path(&1.place)}")}

      Riding on the answer:

      #{Enum.map_join(matches, "\n", &"  - #{line(&1.claim)}")}
      """,
      answer:
        "Say which one a bare “#{form}” should mean — or whether these are one place recorded twice."
    }
  end

  defp ambiguity(form, matches, others) do
    linked = hd(matches).place
    {shown, rest} = Enum.split(others, @max_candidates)

    %{
      kind: :ambiguous_name,
      title: "Which place is “#{form}”?",
      claim_ids: Enum.map(matches, & &1.claim.id),
      body: """
      The posts said **#{form}**, and the gazetteer answers with
      **#{path(linked)}** — a name that place carries#{scored(matches)}, so the
      resolver matched it and weighed nothing else.

      But these places answer to a name that *begins* the same way:

      #{Enum.map_join(shown, "\n", &candidate/1)}
      #{if rest == [], do: "", else: "  - …and #{length(rest)} more"}
      Riding on the answer:

      #{Enum.map_join(matches, "\n", &"  - #{line(&1.claim)}")}
      """,
      answer:
        "Name the right place, or say “correct”. Wrong here misattributes every claim listed."
    }
  end

  # Which name matched matters more than the place's canonical name: "caraballeda,
  # residencias country mar" is why an unrelated-looking building is a candidate.
  defp candidate(%{name: name, place: place}), do: "  - “#{name}” → #{path(place)}"

  # How sure the resolver was, when it was not sure — an exact hit on a full name
  # scores 0.9, a tie it could not break scores 0.5, and that gap is the reader's
  # best cue about how much this question matters.
  defp scored(matches) do
    case Enum.find_value(matches, & &1.confidence) do
      nil -> ""
      confidence when confidence >= @low_confidence -> ""
      confidence -> " (and it was only #{confidence} sure — several places matched)"
    end
  end

  defp low_confidence(world, covered) do
    world.claims
    |> Enum.flat_map(fn detail ->
      for %{link: link, place: place} <- detail.links,
          place,
          link.confidence && link.confidence < @low_confidence,
          detail.claim.id not in covered do
        %{
          kind: :low_confidence,
          title: "A place link the resolver is unsure of (#{link.confidence})",
          claim_ids: [detail.claim.id],
          body: """
          “#{detail.claim.place_mention}” was linked to **#{path(place)}**
          (#{link.how_resolved}, confidence #{link.confidence}) — matched, but
          without anything in the mention to anchor which one was meant.

            - #{line(detail)}
          """,
          answer: "Confirm the place, or name the right one."
        }
      end
    end)
  end

  defp unresolved(world) do
    world.claims
    |> Enum.filter(&(&1.links == [] and &1.claim.place_mention not in [nil, ""]))
    |> case do
      [] ->
        []

      claims ->
        [
          %{
            kind: :unresolved,
            title: "#{length(claims)} mention(s) matched no place at all",
            claim_ids: Enum.map(claims, & &1.claim.id),
            body: """
            Nothing in the gazetteer answers to these, and the resolver never
            guesses a position in the tree. **A claim with no place appears in no
            beat** — it is not flagged to a reader anywhere; it is simply absent.

            #{Enum.map_join(claims, "\n", &"  - “#{&1.claim.place_mention}” — #{line(&1)}")}
            """,
            answer:
              "Name the place (and where it sits), or leave it — an honest absence beats a guess."
          }
        ]
    end
  end

  defp pending_persons(world) do
    case Enum.filter(world.persons, &(&1.status == :pending_review)) do
      [] ->
        []

      persons ->
        [
          %{
            kind: :pending_person,
            title: "#{length(persons)} person(s) waiting on the handle gate",
            claim_ids: [],
            body: """
            A reader only ever sees the handle. The full name is here so you can
            check the handle is right — it is written nowhere a reader reaches.

            | shown as | full name | in |
            |---|---|---|
            #{Enum.map_join(persons, "\n", &person_row(&1, world))}
            """,
            answer:
              "Per person: **approve** (handle stands), **withhold** (they drop out of every beat), or give a corrected handle."
          }
        ]
    end
  end

  defp person_row(person, world) do
    appears =
      world.claims
      |> Enum.filter(fn detail -> Enum.any?(detail.persons, &(&1.id == person.id)) end)
      |> Enum.map_join("; ", & &1.claim.kind)

    "| #{person.display_handle || "*(none — needs one)*"} | #{person.full_name} | #{appears} |"
  end

  # The only question a human's answer cannot silence by itself: accepting a
  # support verdict leaves the claim exactly as it was, so nothing about the
  # claim will ever say it was read. The curation act is the only record that it
  # was — which is precisely why `:accept_support` exists.
  #
  # It suppresses the verdict that was accepted, not the claim. Verify re-runs by
  # default and the judge may honestly move a claim from :overstated to
  # :unsupported; a worse verdict silently swallowed by an older acceptance is the
  # exact failure the honesty layer exists to prevent, so it asks again.
  defp flagged_claims(world) do
    accepted =
      for act <- world.acts,
          act.kind == :accept_support,
          into: MapSet.new(),
          do: {act.claim_id, act.before["support"]}

    world.claims
    |> Enum.filter(&(&1.claim.support in [:overstated, :unsupported]))
    |> Enum.reject(&MapSet.member?(accepted, {&1.claim.id, to_string(&1.claim.support)}))
    |> case do
      [] ->
        []

      claims ->
        [
          %{
            kind: :flagged,
            title: "#{length(claims)} claim(s) the support gate flagged",
            claim_ids: Enum.map(claims, & &1.claim.id),
            body: """
            The evidence does not bear these as they stand. Nothing is withheld —
            a beat tells them as “según un reporte sin confirmar”.

            #{Enum.map_join(claims, "\n", &"  - **#{&1.claim.support}** — #{line(&1)}\n    #{&1.claim.support_note}")}
            """,
            answer: "Correct the claim, retract it, or accept the attribution."
          }
        ]
    end
  end

  defp proposed_places(world) do
    case Enum.filter(world.places, &(&1.lifecycle == :proposed)) do
      [] ->
        []

      places ->
        [
          %{
            kind: :proposed_place,
            title: "#{length(places)} place(s) a machine proposed",
            claim_ids: [],
            body: """
            The resolver found the coarser place but not the finer one, so it
            proposed the finer under it. A proposed place cannot widen the name
            gate until a human promotes it.

            #{Enum.map_join(places, "\n", &"  - **#{&1.canonical_name}** (#{&1.type}) — #{path(&1)}")}
            """,
            answer: "Promote, rename, or discard."
          }
        ]
    end
  end

  # The gazetteer holding one place twice splits its story in half, and the split is
  # invisible until a claim happens to name it. So it is asked up front, over the
  # whole tree, rather than waited for.
  #
  # A "yes" folds one into the other and the pair leaves the tree. A "no" moves
  # nothing — so it needs an act, exactly like accepting a support verdict, or the
  # same pair comes back on every report forever.
  defp duplicate_places(world) do
    apart =
      for act <- world.acts,
          act.kind == :distinguish_places,
          into: MapSet.new(),
          do: MapSet.new([act.place_id, act.before["not_id"]])

    world.event.id
    |> Duplicates.find()
    |> Enum.reject(&MapSet.member?(apart, MapSet.new([&1.place.id, &1.other.id])))
    |> case do
      [] ->
        []

      found ->
        [
          %{
            kind: :duplicate_place,
            title: "#{length(found)} place(s) the gazetteer may hold twice",
            claim_ids: [],
            body: """
            Two rows for one place split its story: half the claims land on each, and
            a reader meets the same place twice. Nothing here is guessed at — a pair
            whose numbers or compass directions disagree is never offered, because
            that token is what tells two neighbours apart.

            | keep | may be the same as | how close | why |
            |---|---|---|---|
            #{Enum.map_join(found, "\n", &duplicate_row/1)}
            """,
            answer:
              "Per pair: **fold** (the second becomes a name of the first, and its " <>
                "children move up), or **apart** (they are two places — I record that " <>
                "so it is never asked again)."
          }
        ]
    end
  end

  defp duplicate_row(%{place: place, other: other, score: score, certainty: certainty}) do
    closeness = if certainty == :certain, do: "**same name**", else: Float.round(score, 2)

    "| #{path(other)} | **#{place.canonical_name}** (#{place.type}) | #{closeness} | " <>
      "#{if certainty == :certain, do: "it sits inside it", else: "a second spelling"} |"
  end

  # One happening told twice. Within a batch the deterministic merge holds this line;
  # across batches it does not, and that is the defect that compounds fastest as the
  # corpus grows. Same shape as the duplicate places, and it stops in the same place:
  # a "no" moves nothing, so it needs an act.
  defp duplicate_claims(world) do
    apart =
      for act <- world.acts,
          act.kind == :distinguish_claims,
          into: MapSet.new(),
          do: MapSet.new([act.claim_id, act.before["not_id"]])

    world.event.id
    |> ClaimDuplicates.find()
    |> Enum.reject(&MapSet.member?(apart, MapSet.new([&1.claim.id, &1.other.id])))
    |> case do
      [] ->
        []

      found ->
        [
          %{
            kind: :duplicate_claim,
            title: "#{length(found)} claim(s) that may be one happening told twice",
            claim_ids: Enum.flat_map(found, &[&1.claim.id, &1.other.id]),
            body: """
            A subject carrying its own mark — an age, a count — is offered wherever it
            appears; a generic subject is only offered when both accounts sit at the
            same place and close in time, because a woman missing in one building and
            a woman missing in another are two claims.

            #{Enum.map_join(found, "\n\n", &duplicate_claim_entry/1)}
            """,
            answer:
              "Per pair: **merge** (the earlier account keeps its evidence and absorbs " <>
                "the other's), or **apart** (two happenings — I record that so it is " <>
                "never asked again)."
          }
        ]
    end
  end

  defp duplicate_claim_entry(%{claim: claim, other: other, score: score}) do
    """
      - **#{line(other)}** — #{where(other)}
        may be **#{line(claim)}** — #{where(claim)}
        (subjects #{Float.round(score, 2)} alike)\
    """
  end

  defp where(claim) do
    claim.id
    |> Narrative.list_claim_places!()
    |> Enum.map_join(", ", fn link ->
      case Core.get_place(link.place_id) do
        {:ok, place} -> place.canonical_name
        _gone -> "—"
      end
    end)
    |> case do
      "" -> "*unplaced*"
      places -> places
    end
  end

  ## ─────────────────────────── sections ───────────────────────────

  defp header(event, world, questions, at) do
    """
    # El registro — #{event.name}

    *#{Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")} · #{length(world.claims)} current claims · \
    #{length(questions)} question(s) for you*

    > **This file names private individuals.** The record protects those names
    > everywhere a reader could reach — a claim and a beat carry only a derived
    > handle. They are here because you cannot check a handle you cannot see.
    > It is written to a git-ignored path: review it, then let it be overwritten.
    > Do not commit or share it.
    """
  end

  defp calls([]) do
    """

    ## What needs your call

    Nothing. Every mention resolved, every person is decided, every claim is
    supported.
    """
  end

  defp calls(questions) do
    """

    ## What needs your call

    Answer by number — here in the file or in chat. Nothing below has been
    guessed at: each is a place the system stopped rather than decide for you.

    #{Enum.map_join(questions, "\n", &"#{&1.n}. #{&1.title}")}

    #{Enum.map_join(questions, "\n", &question(&1))}
    """
  end

  defp question(q) do
    """
    ### Q#{q.n} — #{q.title}

    #{q.body}
    **To answer:** #{q.answer}

    ---
    """
  end

  # What a person already decided, so the report stops asking. Most questions
  # above suppress themselves by watching the state an answer moved; this
  # section is the other half of that — it says the answer was a deliberate act
  # by a named person, with a reason, on a date. Without it the report is a nag;
  # with it, it is the record of a conversation.
  defp settled(%{acts: []}), do: ""

  defp settled(world) do
    """

    ## What you already settled (#{length(world.acts)})

    Newest first. Each of these was a deliberate act — it is why the questions
    it answered are no longer above.

    | when | who | what | why |
    |---|---|---|---|
    #{Enum.map_join(world.acts, "\n", &act_row(&1, world))}
    """
  end

  defp act_row(act, world) do
    who = (act.actor && act.actor.name) || "*(unattributed)*"

    "| #{Calendar.strftime(act.inserted_at, "%b %d")} | #{who} | " <>
      "#{Act.phrase(act.kind)} #{target(act, world)}#{moved(act)} | #{act.reason} |"
  end

  defp target(%{place_id: id}, world) when not is_nil(id) do
    case Map.get(world.by_id, id) do
      nil -> "a place"
      place -> "**#{place.canonical_name}** (#{place.type})"
    end
  end

  defp target(%{person_id: id}, world) when not is_nil(id) do
    case Enum.find(world.persons, &(&1.id == id)) do
      nil -> "a person"
      person -> "**#{person.display_handle || person.full_name}**"
    end
  end

  # A retracted Claim is no longer current, so it is not in `world.claims` at all —
  # what the act recorded of it is the only way left to name it.
  defp target(%{claim_id: id} = act, world) when not is_nil(id) do
    case Enum.find(world.claims, &(&1.claim.id == id)) do
      nil -> withdrawn(act.before)
      detail -> "*#{line(detail)}*"
    end
  end

  defp target(_no_target, _world), do: "—"

  defp withdrawn(%{"kind" => kind} = before),
    do: "*#{kind}#{if before["subject"], do: " — #{before["subject"]}"}*"

  defp withdrawn(_no_record), do: "a claim"

  # Only worth saying when it actually moved, and only the fields this act touched.
  defp moved(%{after: nil}), do: ""
  defp moved(%{before: nil}), do: ""

  defp moved(%{before: before, after: later}) do
    case Enum.map_join(later, ", ", fn {key, to} -> "#{Map.get(before, key) || "—"} → #{to}" end) do
      "" -> ""
      moved -> " (#{moved})"
    end
  end

  # The beat the last completed run produced, kept as its receipt of output. It
  # is re-derivable from the claims at any time — this is what was rendered, not
  # a canonical story.
  defp story(world) do
    case Enum.find(world.runs, &(&1.status == :completed and is_map(&1.summary["beat"]))) do
      nil ->
        """

        ## The story as it reads now

        No completed run has rendered a beat yet.
        """

      run ->
        beat = run.summary["beat"]
        sources = beat["sources"] || []

        """

        ## The story as it reads now

        *#{run.options["place_name"]}, #{window(run)} — rendered by run `#{short(run.id)}`.*

        #{beat["prose"]}

        #{Enum.map_join(sources, "\n", &"[#{&1["n"]}] post #{&1["x_id"]}")}
        """
    end
  end

  defp claims_section(world) do
    """

    ## The claims (#{length(world.claims)})

    #{Enum.map_join(world.claims, "\n", &claim_entry/1)}
    """
  end

  defp claim_entry(%{claim: claim} = detail) do
    """
    ### #{claim.kind}#{if claim.subject, do: " — #{claim.subject}"}

    - **where** #{places_of(detail)}
    - **when** #{Calendar.strftime(claim.first_seen_at, "%Y-%m-%d %H:%M")} · **status** #{claim.status || "—"}#{magnitude(claim)}
    - **support** #{claim.support}#{if claim.support_note, do: " — #{claim.support_note}"}
    - **people** #{people_of(detail)}
    - **evidence**
    #{Enum.map_join(detail.posts, "\n", &"  - [#{&1.x_id}] #{excerpt(&1.text)}")}
    """
  end

  defp excerpt(text) do
    if String.length(text) > 180, do: String.slice(text, 0, 180) <> "…", else: text
  end

  defp places_of(%{claim: claim, links: []}), do: "*unresolved* — “#{claim.place_mention || "—"}”"

  defp places_of(%{claim: claim, links: links}) do
    told =
      Enum.map_join(links, ", ", fn %{link: l, place: p} -> "#{path(p)} (#{l.confidence})" end)

    "#{told} — from “#{claim.place_mention}”"
  end

  defp people_of(%{persons: []}), do: "—"

  defp people_of(%{persons: persons}) do
    Enum.map_join(persons, ", ", &"#{&1.display_handle || &1.full_name} (#{&1.status})")
  end

  defp magnitude(%{magnitude: nil}), do: ""
  defp magnitude(%{magnitude: m}), do: " · **magnitude** #{inspect(m)}"

  defp runs_section(world) do
    """

    ## The runs (#{length(world.runs)})

    | receipt | status | asked | extract | resolve | verify |
    |---|---|---|---|---|---|
    #{Enum.map_join(world.runs, "\n", &run_row/1)}
    """
  end

  defp run_row(run) do
    summary = run.summary || %{}
    options = run.options || %{}

    "| `#{short(run.id)}` | #{run.status} | #{options["place_name"]} #{window(run)} | " <>
      "#{stage(summary["extract"], ["drafted", "skipped"])} | " <>
      "#{stage(summary["resolve"], ["linked", "proposed"])} | " <>
      "#{stage(summary["verify"], ["supported", "unsupported"])} |"
  end

  defp stage(nil, _keys), do: "—"

  defp stage(counts, keys) do
    Enum.map_join(keys, ", ", &"#{&1} #{Map.get(counts, &1, 0)}")
  end

  ## ─────────────────────────── shared ───────────────────────────

  # A place named the way a person can place it: the node, then its parent.
  defp path(nil), do: "—"

  defp path(place) do
    case place.parent_id && Core.get_place(place.parent_id) do
      {:ok, parent} -> "#{place.canonical_name} (#{place.type}, under #{parent.canonical_name})"
      _no_parent -> "#{place.canonical_name} (#{place.type})"
    end
  end

  defp line(%{claim: claim}), do: line(claim)

  defp line(claim) do
    "#{claim.kind}#{if claim.subject, do: " — #{claim.subject}"} " <>
      "(#{Calendar.strftime(claim.first_seen_at, "%b %d")})"
  end

  defp window(run) do
    options = run.options || %{}

    case {options["from"], options["to"]} do
      {nil, _to} -> ""
      {from, to} -> "#{String.slice(from, 0, 10)} → #{String.slice(to || "", 0, 10)}"
    end
  end

  defp short(id), do: String.slice(id, 0, 8)
end
