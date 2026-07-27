defmodule Wekui.ReportTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
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

    assert report =~ "1 person(s) waiting on the handle gate"
    assert report =~ "| Damarys M. | Damarys Melo |"
    assert report =~ "**withhold**"
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
end
