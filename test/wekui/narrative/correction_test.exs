defmodule Wekui.Narrative.CorrectionTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.Correction

  setup do
    event = event!()

    %{
      event: event,
      place: place!(event),
      agent: agent!(event),
      curator: curator!(event, %{name: "Aníbal Rojas"}),
      p1: post!(event),
      p2: post!(event)
    }
  end

  defp claim!(ctx, attrs \\ %{}) do
    Narrative.draft_claim!(
      Map.merge(
        %{
          event_id: ctx.event.id,
          kind: "rescate",
          subject: "un hombre de 31 años",
          place_mention: "Caraballeda",
          first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
          actor_id: ctx.agent.id,
          confidence: 0.9
        },
        attrs
      )
    )
  end

  describe "a correction is a successor, never an edit" do
    test "the corrected account is a new claim and the wrong one is closed onto it", ctx do
      wrong = claim!(ctx)

      {:ok, right} = Correction.correct(wrong, %{subject: "un hombre de 21 años"}, ctx.curator)

      refute right.id == wrong.id
      assert right.subject == "un hombre de 21 años"
      assert is_nil(right.superseded_at)

      closed = Narrative.get_claim!(wrong.id)
      assert closed.superseded_at
      assert closed.superseded_by_id == right.id
      # The record can still be asked what it used to say.
      assert closed.subject == "un hombre de 31 años"
    end

    test "the happening keeps its first evidence — only its description was wrong", ctx do
      wrong = claim!(ctx)

      {:ok, right} = Correction.correct(wrong, %{kind: "búsqueda"}, ctx.curator)

      assert right.first_seen_at == wrong.first_seen_at
    end

    test "the successor is the curator's account, and carries no confidence", ctx do
      wrong = claim!(ctx)

      {:ok, right} = Correction.correct(wrong, %{status: "rescatado"}, ctx.curator)

      assert right.actor_id == ctx.curator.id
      assert is_nil(right.confidence)
    end

    test "only the fields given move; the rest carry", ctx do
      wrong = claim!(ctx, %{nuance: "según un familiar", magnitude: %{"horas" => 6}})

      {:ok, right} = Correction.correct(wrong, %{kind: "búsqueda"}, ctx.curator)

      assert right.kind == "búsqueda"
      assert right.subject == wrong.subject
      assert right.nuance == "según un familiar"
      assert right.magnitude == %{"horas" => 6}
      assert right.place_mention == "Caraballeda"
    end

    test "several fields correct at once", ctx do
      wrong = claim!(ctx)

      {:ok, right} =
        Correction.correct(
          wrong,
          %{kind: "búsqueda", subject: "un hombre de 21 años", status: "desaparecido"},
          ctx.curator
        )

      assert right.kind == "búsqueda"
      assert right.subject == "un hombre de 21 años"
      assert right.status == "desaparecido"
    end
  end

  describe "what a correction carries" do
    test "the evidence did not change, so the citations carry", ctx do
      wrong = claim!(ctx)
      Narrative.cite_post!(%{claim_id: wrong.id, post_id: ctx.p1.id})
      Narrative.cite_post!(%{claim_id: wrong.id, post_id: ctx.p2.id})

      {:ok, right} = Correction.correct(wrong, %{kind: "búsqueda"}, ctx.curator)

      cited = right.id |> Narrative.list_claim_citations!() |> MapSet.new(& &1.post_id)
      assert cited == MapSet.new([ctx.p1.id, ctx.p2.id])
    end

    test "the people it is about carry", ctx do
      wrong = claim!(ctx)

      person =
        Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Aaron Camacho"})

      Narrative.link_person!(%{claim_id: wrong.id, person_id: person.id})

      {:ok, right} = Correction.correct(wrong, %{status: "rescatado"}, ctx.curator)

      assert [link] = Narrative.list_claim_persons!(right.id)
      assert link.person_id == person.id
    end

    test "the places carry, provenance and all, when the mention is not what was wrong", ctx do
      wrong = claim!(ctx)

      Narrative.link_place!(%{
        claim_id: wrong.id,
        place_id: ctx.place.id,
        how_resolved: :mention_exact,
        confidence: 0.9
      })

      {:ok, right} = Correction.correct(wrong, %{subject: "un hombre de 21 años"}, ctx.curator)

      assert [link] = Narrative.list_claim_places!(right.id)
      assert link.place_id == ctx.place.id
      assert link.how_resolved == :mention_exact
      assert link.confidence == 0.9
    end

    test "a person's own placement stays :manual across a correction", ctx do
      wrong = claim!(ctx)

      Narrative.link_place!(%{
        claim_id: wrong.id,
        place_id: ctx.place.id,
        how_resolved: :manual,
        confidence: nil
      })

      {:ok, right} = Correction.correct(wrong, %{kind: "búsqueda"}, ctx.curator)

      assert [link] = Narrative.list_claim_places!(right.id)
      assert link.how_resolved == :manual
    end

    test "correcting the mention drops the placement it produced", ctx do
      wrong = claim!(ctx)

      Narrative.link_place!(%{
        claim_id: wrong.id,
        place_id: ctx.place.id,
        how_resolved: :mention_exact,
        confidence: 0.9
      })

      {:ok, right} = Correction.correct(wrong, %{place_mention: "Tanaguarena"}, ctx.curator)

      # Correcting where it happened IS the statement that the placement was wrong.
      # The next resolve reads the corrected text.
      assert Narrative.list_claim_places!(right.id) == []
      # And what it used to be placed at survives on the closed account.
      assert [_kept] = Narrative.list_claim_places!(wrong.id)
    end

    test "the support verdict does NOT carry — the gate judged the wrong words", ctx do
      wrong =
        ctx
        |> claim!()
        |> Narrative.record_claim_support!(%{
          support: :overstated,
          support_note: "the posts do not give an age"
        })

      {:ok, right} = Correction.correct(wrong, %{subject: "un hombre"}, ctx.curator)

      assert right.support == :unverified
      assert is_nil(right.support_note)
    end
  end

  describe "what a correction refuses" do
    test "a field it may not touch is named, not silently dropped", ctx do
      wrong = claim!(ctx)

      assert {:error, {:not_correctable, [:first_seen_at]}} =
               Correction.correct(wrong, %{first_seen_at: DateTime.utc_now()}, ctx.curator)
    end

    test "a support verdict is not a person's to assert here", ctx do
      wrong = claim!(ctx)

      assert {:error, {:not_correctable, [:support]}} =
               Correction.correct(wrong, %{support: :supported}, ctx.curator)
    end

    test "a correction that changes nothing is refused", ctx do
      wrong = claim!(ctx)

      assert {:error, :no_change} =
               Correction.correct(wrong, %{subject: "un hombre de 31 años"}, ctx.curator)
    end

    test "an already-superseded claim cannot be corrected", ctx do
      closed = ctx |> claim!() |> Narrative.retract_claim!()

      assert {:error, :not_current} = Correction.correct(closed, %{kind: "búsqueda"}, ctx.curator)
    end

    test "a curator of another Event cannot correct this one's claim", ctx do
      stranger = curator!(event!(), %{name: "Someone Else"})

      assert {:error, :different_events} =
               Correction.correct(claim!(ctx), %{kind: "búsqueda"}, stranger)
    end

    test "an agent does not correct — it re-extracts", ctx do
      assert {:error, :not_a_person} =
               Correction.correct(claim!(ctx), %{kind: "búsqueda"}, ctx.agent)
    end

    test "a refusal leaves the claim exactly as it stood", ctx do
      wrong = claim!(ctx)

      assert {:error, :no_change} = Correction.correct(wrong, %{kind: "rescate"}, ctx.curator)

      still = Narrative.get_claim!(wrong.id)
      assert is_nil(still.superseded_at)
      assert length(Narrative.list_claims!(ctx.event.id)) == 1
    end
  end

  describe "changes/2" do
    test "reports only the fields that would actually move", ctx do
      claim = claim!(ctx)

      assert Correction.changes(claim, %{kind: "rescate", subject: "un hombre"}) ==
               %{subject: "un hombre"}
    end

    test "clearing an optional field is a change", ctx do
      claim = claim!(ctx, %{nuance: "según un familiar"})

      assert Correction.changes(claim, %{nuance: nil}) == %{nuance: nil}
    end
  end
end
