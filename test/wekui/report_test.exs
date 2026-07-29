defmodule Wekui.ReportTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Curation
  alias Wekui.Narrative
  alias Wekui.Report

  setup do
    event = event!()
    agent = agent!(event)
    caraballeda = place!(event, %{canonical_name: "Caraballeda", type: "parroquia"})

    caribe =
      place!(event, %{canonical_name: "Caribe", type: "barrio", parent_id: caraballeda.id})

    %{event: event, agent: agent, caraballeda: caraballeda, caribe: caribe}
  end

  defp claim!(ctx, attrs, opts \\ []) do
    claim =
      Narrative.draft_claim!(
        Map.merge(
          %{
            event_id: ctx.event.id,
            kind: "búsqueda",
            first_seen_at: ~U[2026-06-25 04:02:00.000000Z],
            actor_id: ctx.agent.id,
            confidence: 0.9
          },
          attrs
        )
      )

    if place = opts[:place] do
      Narrative.link_place!(%{
        claim_id: claim.id,
        place_id: place.id,
        how_resolved: opts[:how] || :mention_exact,
        confidence: opts[:confidence] || 0.9
      })
    end

    claim
  end

  test "the whole record renders, with the claims and their evidence", ctx do
    post = post!(ctx.event, %{x_id: "76", text: "desaparecidas en Residencias Caribe"})
    claim = claim!(ctx, %{subject: "dos mujeres", place_mention: "Caribe"}, place: ctx.caribe)
    Narrative.cite_post!(%{claim_id: claim.id, post_id: post.id})

    report = Report.render(ctx.event)

    assert report =~ "# El registro — #{ctx.event.name}"
    assert report =~ "1 current claims"
    assert report =~ "### búsqueda — dos mujeres"
    assert report =~ "[76] desaparecidas en Residencias Caribe"
    assert report =~ "Caribe (barrio, under Caraballeda)"
  end

  test "warns that it names private individuals", ctx do
    assert Report.render(ctx.event) =~ "This file names private individuals"
  end

  test "a clean record asks nothing", ctx do
    claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)

    report = Report.render(ctx.event)
    assert report =~ "Nothing. Every mention resolved"
  end

  test "asks which place, when another answers to a name beginning the same way", ctx do
    # The hazard an exact gazetteer hit hides: the mention matches this building's
    # alias outright, while a longer-named building stands next door.
    conjunto =
      place!(ctx.event, %{
        canonical_name: "Conjunto Residencial Caribe",
        type: "edificio",
        parent_id: ctx.caribe.id,
        names: [{"Conjunto Residencial Caribe", :raw}, {"Residencias Caribe", :raw}]
      })

    place!(ctx.event, %{
      canonical_name: "Residencias Caribe, Torre C",
      type: "edificio",
      parent_id: ctx.caribe.id
    })

    claim!(ctx, %{subject: "una maestra", place_mention: "Residencias Caribe"}, place: conjunto)

    report = Report.render(ctx.event)

    assert report =~ "Which place is “residencias caribe”?"
    assert report =~ "Conjunto Residencial Caribe (edificio, under Caribe)"
    assert report =~ "“residencias caribe, torre c” → Residencias Caribe, Torre C"
    assert report =~ "una maestra"
  end

  # At 107 posts this class was 15 separate questions and the operator said he would
  # not answer them. At 2,791 it was 152 — a question class growing with the corpus,
  # which is the failure `docs/mechanisms.md` exists to forbid.
  test "many unsure links become ONE question with a bounded sample", ctx do
    # A place with no look-alike, so these are low-confidence links and NOT the
    # gazetteer tie — `ambiguous_names/1` asks that, and it already asks it once.
    lonely =
      place!(ctx.event, %{
        canonical_name: "Quinta Zarzamora",
        type: "edificio",
        parent_id: ctx.caraballeda.id
      })

    for n <- 1..20 do
      claim!(ctx, %{subject: "persona #{n}", place_mention: "Quinta Zarzamora"},
        place: lonely,
        how: :mention_fuzzy,
        confidence: 0.65
      )
    end

    report = Report.render(ctx.event)

    assert report =~ "place link(s) the resolver was unsure of — 3 to spot-check"
    # One question, not twenty.
    assert report |> String.split("A place link the resolver is unsure of") |> length() == 1
    assert report =~ "that is a rule, and it will settle the other"
  end

  test "says how unsure the resolver was when it was not sure", ctx do
    place!(ctx.event, %{
      canonical_name: "Caribe Mar",
      type: "edificio",
      parent_id: ctx.caraballeda.id
    })

    claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe, confidence: 0.5)

    assert Report.render(ctx.event) =~ "only 0.5 sure"
  end

  test "a look-alike BENEATH the linked place is no rival — the tree settles it", ctx do
    # Linking the community when the posts named no tower is the correct coarser
    # answer, and the tower is reachable the moment a post names it. Putting the
    # tower where it belongs is what makes the question go away.
    place!(ctx.event, %{
      canonical_name: "Caribe Torre C",
      type: "edificio",
      parent_id: ctx.caribe.id
    })

    claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)

    assert Report.render(ctx.event) =~ "Nothing. Every mention resolved"
  end

  test "asks the sharper question when two places carry the same name outright", ctx do
    # The parroquia and the town inside it are both called Caraballeda: nothing in
    # a bare mention can choose, so the look-alikes are noise beside this.
    place!(ctx.event, %{
      canonical_name: "Caraballeda",
      type: "populated_place",
      parent_id: ctx.caraballeda.id
    })

    place!(ctx.event, %{
      canonical_name: "Caraballeda Humboldt",
      type: "sector",
      parent_id: ctx.caraballeda.id
    })

    claim!(ctx, %{place_mention: "Caraballeda"}, place: ctx.caraballeda, confidence: 0.5)

    report = Report.render(ctx.event)

    assert report =~ "Two places are called “caraballeda” — which one?"
    assert report =~ "whether these are one place recorded twice"
    refute report =~ "Caraballeda Humboldt"
  end

  test "asks about a mention that matched nothing — invisible to every beat", ctx do
    claim!(ctx, %{subject: "un hombre", place_mention: "Caraballeda-La Guaira"})

    report = Report.render(ctx.event)

    assert report =~ "matched no place at all"
    assert report =~ "“Caraballeda-La Guaira”"
    assert report =~ "appears in no"
  end

  test "asks about the people waiting on the handle gate, showing the name to check", ctx do
    claim = claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)
    person = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Damarys Melo"})
    Narrative.link_person!(%{claim_id: claim.id, person_id: person.id})

    report = Report.render(ctx.event)

    assert report =~ "1 person(s) at the handle gate"
    assert report =~ "| Damarys M. | Damarys Melo |"
    # Nothing is auto-approved: being told is a decision about dignity and it stays his.
    assert report =~ "Nothing below was approved for you"
  end

  # Human attention is bounded and machine attention is not, so what a person must
  # look at cannot grow with the corpus (`docs/mechanisms.md`).
  test "the handle gate asks about a bounded sample, however many people arrive", ctx do
    claim = claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)

    for n <- 1..25 do
      person =
        Narrative.identify_person!(%{
          event_id: ctx.event.id,
          full_name: "Nombre#{n} Apellido#{n}"
        })

      Narrative.link_person!(%{claim_id: claim.id, person_id: person.id})
    end

    report = Report.render(ctx.event)

    assert report =~ "25 person(s) at the handle gate"
    assert report =~ ~r/rule\(s\) would settle them/
    assert report =~ "derived cleanly and collide with nobody — 3 to spot-check"
    # A rule per group, never a row per person.
    assert report =~ "Give a rule for each group above, not a handle each"
    assert report =~ "approve the rest as a batch"
  end

  test "a handle two people share is a defect, and it is shown as one", ctx do
    claim = claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)

    for full_name <- ["Damarys Melo", "Damarys Medina"] do
      person = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: full_name})
      Narrative.link_person!(%{claim_id: claim.id, person_id: person.id})
    end

    report = Report.render(ctx.event)

    assert report =~ ~r/1 handle\(s\) shared by two or more people/
  end

  test "a name the derivation refused is separated from the ones it read", ctx do
    claim = claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)

    # A lone token: `Handle` refuses rather than guess, and a person must write one.
    lone = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Marcela"})
    Narrative.link_person!(%{claim_id: claim.id, person_id: lone.id})

    report = Report.render(ctx.event)

    assert report =~ "the derivation refused as **a lone token**"
  end

  test "asks about a claim the support gate flagged", ctx do
    ctx
    |> claim!(%{place_mention: "Caribe"}, place: ctx.caribe)
    |> Narrative.record_claim_support!(%{support: :unsupported, support_note: "nadie lo dice"})

    report = Report.render(ctx.event)

    assert report =~ "1 claim(s) the support gate flagged"
    assert report =~ "nadie lo dice"
  end

  test "asks about a place a machine proposed", ctx do
    Core.create_place!(%{
      event_id: ctx.event.id,
      canonical_name: "OPP 25",
      type: "edificio",
      parent_id: ctx.caribe.id
    })

    claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)

    report = Report.render(ctx.event)

    assert report =~ "1 place(s) a machine proposed"
    assert report =~ "**OPP 25** (edificio"
  end

  describe "the vocabulary waiting to be signed" do
    test "a proposed theme is asked about, and it is asked first", ctx do
      Wekui.Taxonomy.Seed.litoral_central(ctx.event.id)

      report = Report.render(ctx.event)

      assert report =~ "theme(s) proposed for the vocabulary"
      # It governs everything under it, so it leads.
      assert report =~ ~r/1\.\s+\d+ theme\(s\) proposed/
      assert report =~ "Happenings — a claim may carry these"
      assert report =~ "Topics — a post is about these"
      # The rule is the column being signed, not the name.
      assert report =~ "applies when the post"
    end

    test "a vocabulary the person has signed stops being asked about", ctx do
      Wekui.Taxonomy.Seed.litoral_central(ctx.event.id)
      curator = curator!(ctx.event, %{name: "Aníbal Rojas"})

      for theme <- Wekui.Taxonomy.list_themes!(ctx.event.id) do
        Curation.promote_theme!(theme, curator, "ratified")
      end

      report = Report.render(ctx.event)

      refute report =~ "proposed for the vocabulary"
      assert report =~ "took into the vocabulary"
    end

    test "an event with no themes is not asked about one", ctx do
      refute Report.render(ctx.event) =~ "proposed for the vocabulary"
    end
  end

  describe "what a person already settled" do
    setup ctx do
      Map.put(ctx, :curator, curator!(ctx.event, %{name: "Aníbal Rojas"}))
    end

    test "an act is shown with the person, the date, the move and the reason", ctx do
      proposed =
        Core.create_place!(%{
          event_id: ctx.event.id,
          canonical_name: "OPP 25",
          type: "edificio",
          parent_id: ctx.caribe.id
        })

      Curation.promote_place!(proposed, ctx.curator, "confirmed on the ground")

      report = Report.render(ctx.event)

      assert report =~ "## What you already settled (1)"
      assert report =~ "| Aníbal Rojas | promoted **OPP 25** (edificio) (proposed → active) |"
      assert report =~ "confirmed on the ground"
    end

    # A retracted claim leaves the current record, so only the act still names it.
    test "a retracted claim is still named in the trail that retracted it", ctx do
      claim = claim!(ctx, %{subject: "un hombre", place_mention: "Caribe"}, place: ctx.caribe)

      Curation.retract_claim!(claim, ctx.curator, "the post was a rumour")

      report = Report.render(ctx.event)

      assert report =~ "retracted *búsqueda — un hombre*"
      assert report =~ "the post was a rumour"
      assert report =~ "## The claims (0)"
    end

    test "a report with no acts carries no such section", ctx do
      claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)

      refute Report.render(ctx.event) =~ "What you already settled"
    end

    # The tie in the gazetteer does not go away when a human answers it, so this
    # question cannot suppress itself the way a status-driven one does.
    test "the same-name question stops being asked once the link is manual", ctx do
      place!(ctx.event, %{
        canonical_name: "Caraballeda",
        type: "populated_place",
        parent_id: ctx.caraballeda.id
      })

      claim =
        claim!(ctx, %{place_mention: "Caraballeda"}, place: ctx.caraballeda, confidence: 0.5)

      assert Report.render(ctx.event) =~ "Two places are called"

      Curation.relink_claim_place!(
        claim,
        ctx.caraballeda,
        ctx.curator,
        "a bare Caraballeda means the parish"
      )

      report = Report.render(ctx.event)
      refute report =~ "Two places are called"
      assert report =~ "a bare Caraballeda means the parish"
    end

    # The one question no state change can answer: accepting a verdict leaves the
    # claim exactly as it stood, so only the act says it was read.
    test "a flagged claim stops being asked once the verdict is accepted", ctx do
      claim =
        ctx
        |> claim!(%{place_mention: "Caribe"}, place: ctx.caribe)
        |> Narrative.record_claim_support!(%{
          support: :unsupported,
          support_note: "nadie lo dice"
        })

      assert Report.render(ctx.event) =~ "claim(s) the support gate flagged"

      Curation.accept_support!(claim, ctx.curator, "the source is named in the beat")

      report = Report.render(ctx.event)
      refute report =~ "claim(s) the support gate flagged"
      assert report =~ "accepted the support verdict on"
    end

    # An acceptance answers a verdict, not a claim: verify re-runs by default, and a
    # judge that moves :overstated → :unsupported must be asked about again.
    test "a WORSE verdict is asked about again, even after an acceptance", ctx do
      claim =
        ctx
        |> claim!(%{place_mention: "Caribe"}, place: ctx.caribe)
        |> Narrative.record_claim_support!(%{support: :overstated, support_note: "too strong"})

      Curation.accept_support!(claim, ctx.curator, "the source is named in the beat")
      refute Report.render(ctx.event) =~ "claim(s) the support gate flagged"

      claim.id
      |> Narrative.get_claim!()
      |> Narrative.record_claim_support!(%{support: :unsupported, support_note: "nadie lo dice"})

      report = Report.render(ctx.event)
      assert report =~ "1 claim(s) the support gate flagged"
      assert report =~ "nadie lo dice"
    end

    # Asked over the whole tree, up front — a duplicate splits a story long before
    # any claim happens to name it.
    test "asks about a place the gazetteer may hold twice", ctx do
      place!(ctx.event, %{
        canonical_name: "Caraballeda",
        type: "populated_place",
        parent_id: ctx.caraballeda.id
      })

      report = Report.render(ctx.event)

      assert report =~ "1 place(s) the gazetteer may hold twice"
      assert report =~ "**same name**"
      assert report =~ "**apart**"
    end

    test "a folded pair stops being asked about", ctx do
      duplicate =
        place!(ctx.event, %{
          canonical_name: "Caraballeda",
          type: "populated_place",
          parent_id: ctx.caraballeda.id
        })

      Curation.fold_place_into!(duplicate, ctx.caraballeda, ctx.curator, "popular speech")

      refute Report.render(ctx.event) =~ "the gazetteer may hold twice"
    end

    # "No, those are two places" moves no status. Without the act it would be asked
    # again on every report, forever — the same shape as accepting a support verdict.
    test "a pair ruled apart stops being asked about", ctx do
      one = place!(ctx.event, %{canonical_name: "La Costanera", type: "calle"})
      two = place!(ctx.event, %{canonical_name: "Avenida La Costanera", type: "calle"})

      assert Report.render(ctx.event) =~ "the gazetteer may hold twice"

      Curation.distinguish_places!(two, one, ctx.curator, "the avenue and the beach are not one")

      report = Report.render(ctx.event)
      refute report =~ "the gazetteer may hold twice"
      assert report =~ "kept apart **Avenida La Costanera**"
      assert report =~ "the avenue and the beach are not one"
    end

    test "a second correction is listed beside the first, newest first", ctx do
      person = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Damarys Melo"})

      Curation.approve_person!(person, ctx.curator, "handle checked")

      person.id
      |> Narrative.get_person!()
      |> Curation.withhold_person!(ctx.curator, "she asked us not to")

      report = Report.render(ctx.event)

      assert report =~ "## What you already settled (2)"
      # A stamp would show only the second; the record shows the change of mind.
      assert report =~ "handle checked"
      assert report =~ "she asked us not to"

      {withheld_at, _len} = :binary.match(report, "withheld **Damarys M.**")
      {approved_at, _len} = :binary.match(report, "approved **Damarys M.**")
      assert withheld_at < approved_at
    end
  end

  test "questions are numbered so an answer can name one", ctx do
    claim!(ctx, %{place_mention: "en ninguna parte"})
    claim = claim!(ctx, %{place_mention: "Caribe"}, place: ctx.caribe)
    person = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Damarys Melo"})
    Narrative.link_person!(%{claim_id: claim.id, person_id: person.id})

    report = Report.render(ctx.event)

    assert report =~ "### Q1 —"
    assert report =~ "### Q2 —"
    assert report =~ "2 question(s) for you"
  end

  test "carries the beat the last completed run rendered, and the run table", ctx do
    Wekui.Pipelines.start_run!(%{
      event_id: ctx.event.id,
      actor_id: ctx.agent.id,
      kind: :read_path,
      options: %{"place_name" => "Caraballeda", "from" => "2026-06-25T00:00:00Z", "to" => nil}
    })
    |> Wekui.Pipelines.finalize_run!(%{
      summary: %{
        "extract" => %{"drafted" => 8, "skipped" => 0},
        "beat" => %{
          "prose" => "En Caribe, el edificio colapsó.",
          "sources" => [%{"n" => 1, "x_id" => "129"}]
        }
      }
    })

    report = Report.render(ctx.event)

    assert report =~ "En Caribe, el edificio colapsó."
    assert report =~ "[1] post 129"
    assert report =~ "drafted 8, skipped 0"
  end

  test "says so plainly when no run has rendered a beat", ctx do
    assert Report.render(ctx.event) =~ "No completed run has rendered a beat yet"
  end

  # The finder offers pairs; a person is asked about groups. Measured on the corpus,
  # 3,213 pairs were 261 groups — printed as pairs the question is a wall.
  describe "the claims that may be one happening told more than once" do
    defp duplicates!(ctx) do
      for _one_of_three <- 1..3 do
        claim!(ctx, %{kind: "rescate", subject: "un niño de 11 años"}, place: ctx.caribe)
      end
    end

    test "are asked as one group, counting the pairs behind it", ctx do
      duplicates!(ctx)

      report = Report.render(ctx.event)

      assert report =~
               "1 group(s) of claims that may be one happening told more than once (3 pairs)"

      assert report =~ "**3 accounts**, joined by 3 pair(s) — subjects carry their own marks"
      # And it says what a group is, so nobody reads it as a verdict.
      assert report =~ "A group is what to **look at together**, never what to merge"
    end

    test "a group where nothing names a subject says so, rather than showing a score", ctx do
      for _one_of_two <- 1..2 do
        claim!(ctx, %{kind: "colapso de edificio", subject: nil}, place: ctx.caribe)
      end

      report = Report.render(ctx.event)

      assert report =~ "**no account names a subject** — the weakest thing this offers"
    end

    test "a pair a person set apart is never asked again", ctx do
      [one, two, three] = duplicates!(ctx)
      curator = curator!(ctx.event)

      Curation.distinguish_claims!(one, two, curator, "two boys, two buildings")
      Curation.distinguish_claims!(one, three, curator, "two boys, two buildings")
      Curation.distinguish_claims!(two, three, curator, "two boys, two buildings")

      refute Report.render(ctx.event) =~ "may be one happening told more than once"
    end

    # A machine may withdraw another machine's proposal — that is all a `:pair_judge`
    # receipt does. It never merges: `Wekui.Curation` refuses an agent as curator.
    test "a pair two adversarial readings withdrew leaves the question, and says so", ctx do
      [one, two, three] = duplicates!(ctx)

      Wekui.Pipelines.start_run!(%{
        event_id: ctx.event.id,
        actor_id: ctx.agent.id,
        kind: :pair_judge,
        options: %{}
      })
      |> Wekui.Pipelines.finalize_run!(%{
        summary: %{
          "different" => [[one.id, two.id], [one.id, three.id]],
          "same" => [[two.id, three.id]]
        }
      })

      report = Report.render(ctx.event)

      assert report =~ "**2 accounts**"
      assert report =~ "withdrew 2"
      assert report =~ "⚑"
    end
  end
end
