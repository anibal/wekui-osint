defmodule Wekui.CurationTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Curation
  alias Wekui.Narrative

  setup do
    event = event!()
    agent = agent!(event)

    claim =
      Narrative.draft_claim!(%{
        event_id: event.id,
        kind: "rescate",
        subject: "una mujer",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: agent.id,
        confidence: 0.9
      })

    %{
      event: event,
      agent: agent,
      claim: claim,
      curator: curator!(event, %{name: "Aníbal Rojas"}),
      place: place!(event)
    }
  end

  defp only_act!(event), do: event.id |> Curation.list_acts!() |> hd()

  describe "an act carries the who, the when and the why" do
    test "promoting a place records the person, the reason and the move", ctx do
      proposed = place!(ctx.event, %{canonical_name: "Edificio OPP 25", lifecycle: :proposed})

      promoted = Curation.promote_place!(proposed, ctx.curator, "confirmed on the ground")

      assert promoted.lifecycle == :active

      act = only_act!(ctx.event)
      assert act.kind == :promote_place
      assert act.actor_id == ctx.curator.id
      assert act.reason == "confirmed on the ground"
      assert act.place_id == proposed.id
      assert act.before == %{"lifecycle" => "proposed"}
      assert act.after == %{"lifecycle" => "active"}
      # The when is the row's own birthday — there is no second timestamp to drift.
      assert act.inserted_at
    end

    test "the act names a person by name, which is the whole point", ctx do
      Curation.approve_person!(person!(ctx.event), ctx.curator, "handle checked")

      {:ok, act} = Curation.get_act(only_act!(ctx.event).id, load: [:actor])
      assert act.actor.kind == :person
      assert act.actor.name == "Aníbal Rojas"
    end

    test "a reason is required — an act without one is not a record", ctx do
      assert_raise Ash.Error.Invalid, fn ->
        Curation.promote_place!(
          place!(ctx.event, %{lifecycle: :proposed}),
          ctx.curator,
          ""
        )
      end
    end
  end

  # The guarantee the whole layer rests on: a change without its act is exactly the
  # unattributed act this exists to abolish, so neither may land without the other.
  describe "the change and its act are one transaction" do
    test "a refused act takes the change down with it", ctx do
      proposed = place!(ctx.event, %{lifecycle: :proposed})

      # An agent cannot curate — the act is refused after promote_place! has already
      # succeeded inside the transaction.
      assert_raise Ash.Error.Invalid, fn ->
        Curation.promote_place!(proposed, ctx.agent, "a machine should not decide this")
      end

      assert Core.get_place!(proposed.id).lifecycle == :proposed
      assert Curation.list_acts!(ctx.event.id) == []
    end

    test "a refused change writes no act", ctx do
      active = place!(ctx.event, %{lifecycle: :active})

      assert_raise Ash.Error.Invalid, fn ->
        Curation.promote_place!(active, ctx.curator, "already active")
      end

      assert Curation.list_acts!(ctx.event.id) == []
    end
  end

  describe "an agent is never a curator" do
    test "the act refuses an agent actor by name", ctx do
      error =
        assert_raise Ash.Error.Invalid, fn ->
          Curation.record_act!(%{
            event_id: ctx.event.id,
            actor_id: ctx.agent.id,
            kind: :accept_support,
            reason: "r",
            claim_id: ctx.claim.id
          })
        end

      assert Exception.message(error) =~ "must be a person"
    end
  end

  describe "exactly one target" do
    defp record!(ctx, attrs) do
      Curation.record_act!(
        Map.merge(
          %{
            event_id: ctx.event.id,
            actor_id: ctx.curator.id,
            kind: :accept_support,
            reason: "r"
          },
          attrs
        )
      )
    end

    test "no target is refused", ctx do
      error = assert_raise Ash.Error.Invalid, fn -> record!(ctx, %{}) end
      assert Exception.message(error) =~ "an act is about something"
    end

    test "two targets are refused", ctx do
      error =
        assert_raise Ash.Error.Invalid, fn ->
          record!(ctx, %{claim_id: ctx.claim.id, place_id: ctx.place.id})
        end

      assert Exception.message(error) =~ "exactly one thing"
    end

    test "one target passes", ctx do
      assert %{claim_id: claim_id} = record!(ctx, %{claim_id: ctx.claim.id})
      assert claim_id == ctx.claim.id
    end
  end

  describe "places" do
    test "reparent records the tree move by name", ctx do
      parent =
        place!(ctx.event, %{canonical_name: "Conjunto Residencial Caribe", type: "edificio"})

      tower = place!(ctx.event, %{canonical_name: "Torre C", type: "edificio"})

      Curation.reparent_place!(tower, parent, ctx.curator, "the towers belong to the community")

      act = only_act!(ctx.event)
      assert act.kind == :reparent_place
      assert act.before == %{"parent" => nil}
      assert act.after == %{"parent" => "Conjunto Residencial Caribe (edificio)"}
    end

    test "retype records the label, folded as the Place folds it", ctx do
      Curation.retype_place!(ctx.place, "Parróquia", ctx.curator, "it is a parish")

      assert only_act!(ctx.event).after == %{"type" => "parroquia"}
    end

    test "deprecate carries the reason into the Place's own status note", ctx do
      replacement = place!(ctx.event, %{canonical_name: "Caraballeda (parroquia)"})

      deprecated =
        Curation.deprecate_place!(ctx.place, replacement, ctx.curator, "recorded twice")

      assert deprecated.lifecycle == :deprecated
      assert deprecated.status_note == "recorded twice"
      assert only_act!(ctx.event).after["replaced_by"] =~ "Caraballeda"
    end

    test "discard records why it was a mistake", ctx do
      discarded = Curation.discard_place!(ctx.place, ctx.curator, "no such place")

      assert discarded.lifecycle == :discarded
      assert only_act!(ctx.event).reason == "no such place"
    end
  end

  describe "claims" do
    test "link adds a place by hand, with no confidence", ctx do
      Curation.link_claim_place!(ctx.claim, ctx.place, ctx.curator, "this is Caraballeda")

      assert [link] = Narrative.list_claim_places!(ctx.claim.id)
      assert link.how_resolved == :manual
      # A person decides; a person does not estimate.
      assert is_nil(link.confidence)

      act = only_act!(ctx.event)
      assert act.before == %{"places" => nil}
      assert act.after == %{"places" => "Caraballeda (parroquia)"}
    end

    test "link only adds — a happening can span adjacent places", ctx do
      other = place!(ctx.event, %{canonical_name: "Tanaguarena", type: "sector"})

      Curation.link_claim_place!(ctx.claim, ctx.place, ctx.curator, "here")
      Curation.link_claim_place!(ctx.claim, other, ctx.curator, "and here")

      assert length(Narrative.list_claim_places!(ctx.claim.id)) == 2
    end

    test "relink drops the places it was about and keeps the one it is", ctx do
      wrong = place!(ctx.event, %{canonical_name: "Caraballeda", type: "populated_place"})

      Narrative.link_place!(%{
        claim_id: ctx.claim.id,
        place_id: wrong.id,
        how_resolved: :mention_exact,
        confidence: 0.5
      })

      Curation.relink_claim_place!(
        ctx.claim,
        ctx.place,
        ctx.curator,
        "a bare Caraballeda means the parish"
      )

      assert [link] = Narrative.list_claim_places!(ctx.claim.id)
      assert link.place_id == ctx.place.id
      assert link.how_resolved == :manual

      act = only_act!(ctx.event)
      assert act.kind == :relink_claim_place
      # What the link read before survives here — that is what makes dropping it safe.
      assert act.before == %{"places" => "Caraballeda (populated_place)"}
      assert act.after == %{"places" => "Caraballeda (parroquia)"}
    end

    test "relinking onto a place the claim already holds keeps it and drops the rest", ctx do
      other = place!(ctx.event, %{canonical_name: "Tanaguarena", type: "sector"})

      Narrative.link_place!(%{
        claim_id: ctx.claim.id,
        place_id: ctx.place.id,
        how_resolved: :mention_exact,
        confidence: 0.5
      })

      Narrative.link_place!(%{
        claim_id: ctx.claim.id,
        place_id: other.id,
        how_resolved: :sweep,
        confidence: 0.4
      })

      Curation.relink_claim_place!(ctx.claim, ctx.place, ctx.curator, "only the parish")

      assert [link] = Narrative.list_claim_places!(ctx.claim.id)
      assert link.place_id == ctx.place.id
      assert link.how_resolved == :manual
      assert is_nil(link.confidence)
    end

    test "retract withdraws the claim and says why", ctx do
      Curation.retract_claim!(ctx.claim, ctx.curator, "the post was a rumour")

      # Retraction closes the answer with no successor — the Judgment spine's shape.
      retracted = Narrative.get_claim!(ctx.claim.id)
      assert retracted.superseded_at
      assert is_nil(retracted.superseded_by_id)
      assert only_act!(ctx.event).before == %{"kind" => "rescate", "subject" => "una mujer"}
    end

    test "accept_support changes nothing and records that it was read", ctx do
      flagged =
        Narrative.record_claim_support!(ctx.claim, %{
          support: :overstated,
          support_note: "the posts say rescued, the claim says dead"
        })

      Curation.accept_support!(flagged, ctx.curator, "the attribution is fine as it stands")

      # Nothing moved — which is exactly why the act has to exist.
      assert Narrative.get_claim!(ctx.claim.id).support == :overstated

      act = only_act!(ctx.event)
      assert act.kind == :accept_support
      assert act.before["support"] == "overstated"
      assert is_nil(act.after)
    end
  end

  describe "persons" do
    test "approve moves the gate and records who opened it", ctx do
      person = person!(ctx.event)

      approved = Curation.approve_person!(person, ctx.curator, "handle checked against the post")

      assert approved.status == :approved
      act = only_act!(ctx.event)
      assert act.person_id == person.id
      assert act.before == %{"status" => "pending_review"}
      assert act.after == %{"status" => "approved"}
    end

    test "withhold drops them out of every beat", ctx do
      assert Curation.withhold_person!(person!(ctx.event), ctx.curator, "a minor").status ==
               :withheld
    end

    test "set_handle records the correction both ways", ctx do
      person = person!(ctx.event, "María de la Cruz Pérez")

      Curation.set_person_handle!(
        person,
        "María P.",
        ctx.curator,
        "the particle is not a surname"
      )

      act = only_act!(ctx.event)
      assert act.before["display_handle"] == person.display_handle
      assert act.after == %{"display_handle" => "María P."}
    end

    test "set_kind records private → public", ctx do
      Curation.set_person_kind!(person!(ctx.event), :public, ctx.curator, "an official")

      assert only_act!(ctx.event).after == %{"kind" => "public"}
    end
  end

  describe "the trail" do
    test "acts read newest first, and every one is kept", ctx do
      person = person!(ctx.event)
      Curation.approve_person!(person, ctx.curator, "first call")
      Curation.withhold_person!(Narrative.get_person!(person.id), ctx.curator, "second thoughts")

      assert [second, first] = Curation.list_acts!(ctx.event.id)
      # A stamp would have lost the first call; the record keeps both, in order.
      assert first.reason == "first call"
      assert second.reason == "second thoughts"
    end

    test "another Event's acts are not this Event's", ctx do
      other = event!()
      Curation.approve_person!(person!(ctx.event), ctx.curator, "here")

      Curation.approve_person!(
        person!(other),
        curator!(other, %{name: "Aníbal Rojas"}),
        "there"
      )

      assert [act] = Curation.list_acts!(ctx.event.id)
      assert act.reason == "here"
    end

    test "a curator cannot act on another Event's record", ctx do
      stranger = curator!(event!(), %{name: "Aníbal Rojas"})

      assert_raise Ash.Error.Invalid, fn ->
        Curation.approve_person!(person!(ctx.event), stranger, "not mine to decide")
      end
    end
  end

  defp person!(event, full_name \\ "Aaron Camacho") do
    Narrative.identify_person!(%{event_id: event.id, full_name: full_name})
  end
end
