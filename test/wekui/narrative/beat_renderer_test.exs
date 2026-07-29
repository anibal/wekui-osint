defmodule Wekui.Narrative.BeatRendererTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.BeatRenderer

  @from ~U[2026-06-24 00:00:00.000000Z]
  @to ~U[2026-07-05 00:00:00.000000Z]

  setup do
    event = event!()
    agent = agent!(event)
    post = post!(event)

    la_guaira = place!(event, %{canonical_name: "La Guaira", type: "estado"})

    caraballeda =
      place!(event, %{canonical_name: "Caraballeda", type: "parroquia", parent_id: la_guaira.id})

    opp = place!(event, %{canonical_name: "OPP 25", type: "edificio", parent_id: caraballeda.id})

    %{
      event: event,
      agent: agent,
      post: post,
      la_guaira: la_guaira,
      caraballeda: caraballeda,
      opp: opp,
      # A claim reaches a reader only under a theme a person ratified, and the theme
      # is now the renderer's dispatch table — so the default is a real vocabulary
      # name and a test that wants another clause names the theme that carries it.
      theme:
        theme!(event, %{
          name: "Colapso estructural",
          applies_when: "the post states that a named building came down",
          nature: :happening
        })
    }
  end

  # The vocabulary IS the dispatch table now, so a test that wants a particular clause
  # asks for the theme that carries it — exactly as the real record does.
  defp theme_for(ctx, nil), do: ctx.theme

  defp theme_for(ctx, name) do
    case Enum.find(Wekui.Taxonomy.list_themes!(ctx.event.id), &(&1.name == name)) do
      nil ->
        theme!(ctx.event, %{
          name: name,
          applies_when: "the post asserts that #{name} occurred",
          nature: :happening
        })

      held ->
        held
    end
  end

  defp claim!(ctx, attrs, place, opts \\ []) do
    {theme, attrs} = Map.pop(attrs, :theme)

    c =
      Narrative.draft_claim!(
        Map.merge(
          %{
            event_id: ctx.event.id,
            theme_id: theme_for(ctx, theme).id,
            first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
            actor_id: ctx.agent.id,
            confidence: 0.9
          },
          attrs
        )
      )

    Narrative.link_place!(%{
      claim_id: c.id,
      place_id: place.id,
      how_resolved: :mention_exact,
      confidence: 0.9
    })

    Narrative.cite_post!(%{claim_id: c.id, post_id: ctx.post.id})

    for name <- opts[:persons] || [] do
      person = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: name})
      Narrative.link_person!(%{claim_id: c.id, person_id: person.id})
    end

    if opts[:support],
      do: Narrative.record_claim_support!(c, %{support: opts[:support], support_note: "x"})

    c
  end

  defp beat(_ctx, place), do: BeatRenderer.render(place.id, @from, @to)

  test "renders a rescue by the person's handle and role, and cites its post", ctx do
    claim!(
      ctx,
      %{
        kind: "rescate en curso",
        theme: "Persona rescatada con vida",
        subject: "un hombre de 21 años",
        status: "atrapado"
      },
      ctx.opp,
      persons: ["Aaron Levi Cantillo Vargas"]
    )

    prose = beat(ctx, ctx.caraballeda).prose
    assert prose =~ "Aaron C."
    assert prose =~ "un hombre de 21 años"
    assert prose =~ ~r/rescatar|rescataron/
    assert prose =~ "[1]"
  end

  test "a claim with no resolved person is told by role — never a raw name", ctx do
    claim!(
      ctx,
      %{
        kind: "rescate",
        theme: "Persona rescatada con vida",
        subject: "una mujer",
        status: "rescatado"
      },
      ctx.caraballeda
    )

    prose = beat(ctx, ctx.caraballeda).prose
    assert prose =~ "una mujer"
  end

  test "each theme reaches its own template", ctx do
    claim!(ctx, %{kind: "colapso", theme: "Colapso estructural"}, ctx.opp)

    claim!(
      ctx,
      %{kind: "búsqueda", theme: "Búsqueda de personas desaparecidas", subject: "una maestra"},
      ctx.opp
    )

    claim!(
      ctx,
      %{kind: "fallecimiento", theme: "Cuerpo recuperado o identificado", subject: "una persona"},
      ctx.opp
    )

    prose = beat(ctx, ctx.opp).prose
    assert prose =~ "el edificio colapsó"
    assert prose =~ "se buscaba a una maestra"
    assert prose =~ "fue recuperado el cuerpo de una persona"
  end

  test "an unsupported claim is attributed, not stated as fact", ctx do
    claim!(
      ctx,
      %{
        kind: "rescate",
        theme: "Persona rescatada con vida",
        subject: "un hombre",
        status: "rescatado"
      },
      ctx.caraballeda,
      support: :unsupported
    )

    assert beat(ctx, ctx.caraballeda).prose =~ "según un reporte sin confirmar"
  end

  test "scope holds by construction — an ancestor-place claim is excluded", ctx do
    claim!(
      ctx,
      %{
        kind: "cifra oficial",
        theme: "Declaración o cifra oficial",
        magnitude: %{"fallecidos" => 100, "heridos" => 200}
      },
      ctx.la_guaira
    )

    # A Caraballeda beat must not pull the state-level toll (La Guaira is its ancestor).
    refute beat(ctx, ctx.caraballeda).prose =~ "balance oficial"
    # A La Guaira beat does, formatting the numbers.
    assert beat(ctx, ctx.la_guaira).prose =~
             "el balance oficial reportó 100 fallecidos y 200 heridos"
  end

  test "groups by place and reaches into the subtree", ctx do
    claim!(ctx, %{kind: "colapso de edificio"}, ctx.opp)
    prose = beat(ctx, ctx.caraballeda).prose
    # The OPP 25 claim (a descendant of Caraballeda) is placed under its building.
    assert prose =~ "En OPP 25, el edificio colapsó tras el terremoto"
  end

  test "place groups read in chronological order, across a month boundary", ctx do
    # Default term ordering compares DateTime structs field by field in key order
    # — day before month before year — so June 29 would sort AFTER July 1 unless
    # the group sort names DateTime as its sorter.
    claim!(
      ctx,
      %{kind: "colapso de edificio", first_seen_at: ~U[2026-06-29 07:27:00.000000Z]},
      ctx.opp
    )

    claim!(
      ctx,
      %{
        kind: "cifra oficial",
        theme: "Declaración o cifra oficial",
        first_seen_at: ~U[2026-07-01 10:00:00.000000Z]
      },
      ctx.caraballeda
    )

    clauses = beat(ctx, ctx.caraballeda).clauses
    assert Enum.map(clauses, & &1.place_name) == ["OPP 25", "Caraballeda"]
    assert Enum.map(clauses, & &1.cite_ns) == [[1], [2]]
  end

  # The gate the free `kind` string could never have: a claim reaches a reader only
  # when the record can say what KIND of happening it is, and only a person can put a
  # theme into the vocabulary.
  describe "a claim reaches no reader without a ratified theme" do
    test "a claim with no theme at all is silent", ctx do
      Narrative.draft_claim!(%{
        event_id: ctx.event.id,
        kind: "colapso",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: ctx.agent.id,
        confidence: 0.9
      })
      |> then(fn claim ->
        Narrative.link_place!(%{
          claim_id: claim.id,
          place_id: ctx.opp.id,
          how_resolved: :mention_exact,
          confidence: 0.9
        })
      end)

      assert BeatRenderer.render(ctx.caraballeda.id, @from, @to).clauses == []
    end

    test "a theme nobody has ratified yet is refused at the write path", ctx do
      # Stronger than silence: the claim cannot be drafted at all. A vocabulary entry
      # nobody signed does not exist, so nothing can be filed under it.
      proposed =
        Wekui.Taxonomy.create_theme!(%{
          event_id: ctx.event.id,
          name: "colapso estructural",
          applies_when: "the post states that a named building came down",
          nature: :happening
        })

      error =
        assert_raise Ash.Error.Invalid, fn ->
          claim!(ctx, %{kind: "colapso", theme_id: proposed.id}, ctx.opp)
        end

      assert Exception.message(error) =~ "a person has taken into the vocabulary"
    end

    test "a topic is refused at the write path, before it can reach a beat", ctx do
      plea =
        Wekui.Taxonomy.create_theme!(%{
          event_id: ctx.event.id,
          name: "solicitud de información",
          applies_when: "the post asks whether anyone has news, and asserts nothing",
          nature: :topic,
          lifecycle: :active
        })

      error =
        assert_raise Ash.Error.Invalid, fn ->
          claim!(ctx, %{kind: "búsqueda", theme_id: plea.id}, ctx.opp)
        end

      assert Exception.message(error) =~ "is a topic, not a happening"
    end
  end

  # The fallback used to print `"#{kind}: #{subject}"` — a field name, a colon, and
  # often nothing at all — into a public memorial. It is how
  # `solicitud de información sobre edificio: []` reached a reader.
  describe "a theme the templates do not know still reads as Spanish" do
    test "it says that the thing happened, never a field name", ctx do
      claim!(ctx, %{kind: "saqueo", theme: "Saqueo de un comercio"}, ctx.opp)

      prose = beat(ctx, ctx.opp).prose

      assert prose =~ "se registró un saqueo de un comercio"
      refute prose =~ ":"
      refute prose =~ "saqueo:"
    end

    test "it names whom, when the claim knows", ctx do
      claim!(
        ctx,
        %{kind: "saqueo", theme: "Saqueo de un comercio", subject: "un comerciante"},
        ctx.opp
      )

      assert beat(ctx, ctx.opp).prose =~ "relativo a un comerciante"
    end

    test "an empty slot never reaches the reader", ctx do
      # No subject, no person, no magnitude: the worst case, and it must still be a
      # grammatical sentence rather than a colon with nothing after it.
      claim!(ctx, %{kind: "algo", theme: "Réplica sísmica"}, ctx.opp)

      prose = beat(ctx, ctx.opp).prose

      # The two shapes the old fallback produced: "kind: [1]" and "... con vida a [1]".
      refute prose =~ ~r/:\s*\[/
      refute prose =~ ~r/\s\[\d/
      assert prose =~ "se registró una réplica sísmica"
    end
  end
end
