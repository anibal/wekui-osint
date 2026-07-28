defmodule Wekui.Narrative.PlaceResolverTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Narrative
  alias Wekui.Narrative.PlaceResolver
  alias Wekui.Normalize

  require Ash.Query

  # A small Caraballeda tree, plus a second "Los Cocos" in another parroquia so the
  # generic name has to be disambiguated by its ancestors.
  setup do
    event = event!()
    agent = agent!(event)
    post = post!(event)

    caraballeda = place!(event, %{canonical_name: "Caraballeda", type: "parroquia"})

    tanaguarena =
      place!(event, %{canonical_name: "Tanaguarena", type: "sector", parent_id: caraballeda.id})

    opp25 =
      place!(event, %{canonical_name: "OPP 25", type: "edificio", parent_id: tanaguarena.id})

    caribe =
      place!(event, %{
        canonical_name: "Residencias Caribe",
        type: "edificio",
        parent_id: caraballeda.id
      })

    los_cocos =
      place!(event, %{canonical_name: "Los Cocos", type: "sector", parent_id: caraballeda.id})

    maiquetia = place!(event, %{canonical_name: "Maiquetía", type: "parroquia"})

    _other_cocos =
      place!(event, %{canonical_name: "Los Cocos", type: "sector", parent_id: maiquetia.id})

    %{
      event: event,
      agent: agent,
      post: post,
      caraballeda: caraballeda,
      tanaguarena: tanaguarena,
      opp25: opp25,
      caribe: caribe,
      los_cocos: los_cocos
    }
  end

  defp resolve!(ctx, mention) do
    claim =
      Narrative.draft_claim!(%{
        event_id: ctx.event.id,
        kind: "colapso",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        place_mention: mention,
        actor_id: ctx.agent.id,
        confidence: 0.8
      })

    {:ok, summary} = PlaceResolver.resolve(claim, actor_id: ctx.agent.id, post_id: ctx.post.id)
    {claim, summary}
  end

  defp links(claim), do: Narrative.list_claim_places!(claim.id)

  # Every mention below is verbatim from the record. The resolver read six of the
  # fourteen comma-separated mentions backwards, placed those claims on a parroquia,
  # and asked a person to confirm it.
  describe "which segment is the finest — real mentions, both directions" do
    test "fine-to-coarse still reads as it always did" do
      assert [%{original: "edificio OPP 25", ancestors: ["tanaguarena", "caraballeda"]}] =
               PlaceResolver.parse("edificio OPP 25, Tanaguarena, Caraballeda")
    end

    test "coarse-to-fine no longer places the claim on the parish" do
      assert [%{original: "edificio Roca Azul", ancestors: ["caraballeda"]}] =
               PlaceResolver.parse("Caraballeda, edificio Roca Azul")

      assert [%{original: "residencias Caribe", ancestors: ["caraballeda"]}] =
               PlaceResolver.parse("Caraballeda, residencias Caribe")

      assert [%{original: "Hotel Eduard's building", ancestors: ["la guaira"]}] =
               PlaceResolver.parse("La Guaira, Hotel Eduard's building")
    end

    test "a landmark named mid-segment does not steal the finest position" do
      # "diagonal al Hotel Las 15 Letras" locates the building; it is not the building.
      # Only the LEADING word of a segment counts, so the hotel stays an ancestor.
      assert [%{original: "edificio Las Palmas"}] =
               PlaceResolver.parse(
                 "Macuto, La Guaira, bajada del Playón, diagonal al Hotel Las 15 Letras, edificio Las Palmas"
               )
    end

    test "an administrative level never outranks a bare name" do
      assert [%{original: "Playa Los Cocos", ancestors: ["la guaira"]}] =
               PlaceResolver.parse("Playa Los Cocos, estado La Guaira")
    end

    test "a tie keeps the original reading — two bare names stay fine-first" do
      assert [%{original: "Tanaguarena", ancestors: ["caraballeda"]}] =
               PlaceResolver.parse("Tanaguarena, Caraballeda")
    end
  end

  # The operator ruled on 2026-07-27 that "the numeral names another building". This is
  # that ruling reaching the resolver, on the exact case from the record that exposed it.
  describe "a numeral refuses a fuzzy match, however close the strings read" do
    setup ctx do
      tower =
        place!(ctx.event, %{
          canonical_name: "Torre Celta Mar 1",
          type: "edificio",
          parent_id: ctx.caraballeda.id,
          names: [{"Torre Celta Mar 1", :raw}, {"edificio celtamar", :raw}, {"celtamar i", :raw}]
        })

      %{tower: tower}
    end

    test "“edificio Celta Mar II” is not Torre Celta Mar 1", ctx do
      {claim, summary} = resolve!(ctx, "edificio Celta Mar II, Tanaguarena")

      # It reached the tower through the numeral-LESS alias "edificio celtamar" at
      # 0.93 — so the check has to read the PLACE, not the name that matched.
      refute Enum.any?(links(claim), &(&1.place_id == ctx.tower.id))
      assert summary.linked == 0
    end

    test "the same name without a numeral still matches", ctx do
      {claim, _summary} = resolve!(ctx, "edificio Celtamar, Caraballeda")

      assert Enum.any?(links(claim), &(&1.place_id == ctx.tower.id))
    end
  end

  describe "matching against the gazetteer" do
    test "a full hierarchy resolves to the finest existing place — the building", ctx do
      {claim, summary} =
        resolve!(ctx, "edificio OPP 25, sector Tanaguarena, parroquia Caraballeda")

      assert summary.linked == 1
      assert [link] = links(claim)
      assert link.place_id == ctx.opp25.id
      assert link.how_resolved == :mention_exact
    end

    test "a coarse mention resolves to the parroquia", ctx do
      {claim, _} = resolve!(ctx, "Caraballeda")
      assert [link] = links(claim)
      assert link.place_id == ctx.caraballeda.id
    end

    test "a fuzzy mention still reaches its place", ctx do
      {claim, _} = resolve!(ctx, "Residencia Caribe, Caraballeda")
      assert [link] = links(claim)
      assert link.place_id == ctx.caribe.id
      assert link.how_resolved == :mention_fuzzy
    end

    test "a generic name is disambiguated by its ancestors", ctx do
      {claim, _} = resolve!(ctx, "Los Cocos, Caraballeda")
      assert [link] = links(claim)
      assert link.place_id == ctx.los_cocos.id
      assert link.how_resolved == :mention_exact
    end

    test "a claim can resolve to several sibling places at once", ctx do
      {claim, summary} = resolve!(ctx, "Tanaguarena y Los Cocos, Caraballeda")

      assert summary.linked == 2

      assert claim |> links() |> Enum.map(& &1.place_id) |> Enum.sort() ==
               Enum.sort([ctx.tanaguarena.id, ctx.los_cocos.id])
    end
  end

  describe "proposing what the tree does not yet have" do
    test "a finer place absent from the tree is proposed under its matched ancestor", ctx do
      {claim, summary} = resolve!(ctx, "edificio Roca Park, Tanaguarena")

      assert summary.proposed == 1
      assert [link] = links(claim)
      assert link.how_resolved == :mention_ancestor

      proposed = Ash.get!(Core.Place, link.place_id, authorize?: false)
      assert Normalize.fold(proposed.canonical_name) == "roca park"
      assert proposed.type == "edificio"
      assert proposed.parent_id == ctx.tanaguarena.id
      # Born :proposed — it must NOT be active (so it cannot widen the F54 gate).
      assert proposed.lifecycle == :proposed
      assert proposed.proposed_from_post_id == ctx.post.id
    end

    test "the same not-yet-in-tree building is proposed once, not duplicated", ctx do
      {_c1, _} = resolve!(ctx, "edificio Roca Park, Tanaguarena")
      {_c2, _} = resolve!(ctx, "edificio Roca Park, Tanaguarena")

      roca =
        Core.Place
        |> Ash.Query.filter(event_id == ^ctx.event.id)
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&(Normalize.fold(&1.canonical_name) == "roca park"))

      assert length(roca) == 1
    end
  end

  describe "when nothing resolves" do
    test "a name that matches nothing at any level is left unresolved — no link, no guess", ctx do
      {claim, summary} = resolve!(ctx, "Edificio Fantasma")

      assert links(claim) == []
      assert summary.unresolved == ["Edificio Fantasma"]
    end

    test "a blank mention resolves to nothing — the claim is event-wide", ctx do
      {claim, summary} = resolve!(ctx, nil)
      assert links(claim) == []
      assert summary == %{mentions: 0, linked: 0, proposed: 0, unresolved: [], settled: 0}
    end
  end

  # A place link is an upsert that overwrites how_resolved and confidence — right when
  # the resolver corrects itself, wrong when it would overwrite a person. Without this
  # guard the second run of the pipeline silently undoes every curation act.
  describe "a claim a person already placed by hand" do
    test "is left exactly as the person left it, and counted as settled", ctx do
      {claim, _first} = resolve!(ctx, "Residencias Caribe")
      assert [%{how_resolved: :mention_exact}] = links(claim)

      # The person says it was really the parroquia, not the building.
      Narrative.unlink_place!(hd(links(claim)))

      Narrative.link_place!(%{
        claim_id: claim.id,
        place_id: ctx.caraballeda.id,
        how_resolved: :manual,
        confidence: nil
      })

      {:ok, summary} = PlaceResolver.resolve(claim, actor_id: ctx.agent.id, post_id: ctx.post.id)

      assert summary.settled == 1
      assert summary.linked == 0

      # Not overwritten back to :mention_exact, and the building was not re-added.
      assert [only] = links(claim)
      assert only.place_id == ctx.caraballeda.id
      assert only.how_resolved == :manual
      assert is_nil(only.confidence)
    end

    test "a claim with no manual link still resolves normally", ctx do
      {claim, _first} = resolve!(ctx, "Residencias Caribe")

      {:ok, summary} = PlaceResolver.resolve(claim, actor_id: ctx.agent.id, post_id: ctx.post.id)

      assert summary.settled == 0
      assert summary.linked == 1
    end
  end
end
