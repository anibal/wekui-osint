defmodule Wekui.Narrative.ClaimPersonTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative

  setup do
    event = event!()
    agent = agent!(event)

    draft = fn attrs ->
      Narrative.draft_claim!(
        Map.merge(
          %{
            event_id: event.id,
            kind: "rescate",
            subject: "un hombre",
            first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
            actor_id: agent.id,
            confidence: 0.9
          },
          attrs
        )
      )
    end

    person = fn name -> Narrative.identify_person!(%{event_id: event.id, full_name: name}) end

    %{event: event, draft: draft, person: person}
  end

  test "a claim links to the people it is about, idempotently", %{draft: draft, person: person} do
    c = draft.(%{})
    p1 = person.("Yaneth Tejera")
    p2 = person.("Shaznay Mirabal")

    Narrative.link_person!(%{claim_id: c.id, person_id: p1.id})
    Narrative.link_person!(%{claim_id: c.id, person_id: p2.id})
    again = Narrative.link_person!(%{claim_id: c.id, person_id: p1.id})

    ids = Narrative.list_claim_persons!(c.id) |> Enum.map(& &1.person_id) |> Enum.sort()
    assert ids == Enum.sort([p1.id, p2.id])
    assert again.person_id == p1.id
  end

  test "a person's arc gathers their claims across happenings", %{draft: draft, person: person} do
    p = person.("Julio Josué Freitas Rodríguez")

    early =
      draft.(%{
        first_seen_at: ~U[2026-06-25 03:00:00.000000Z],
        kind: "desaparicion",
        status: "desaparecido"
      })

    late =
      draft.(%{
        first_seen_at: ~U[2026-06-28 12:00:00.000000Z],
        kind: "rescate",
        status: "rescatado"
      })

    Narrative.link_person!(%{claim_id: early.id, person_id: p.id})
    Narrative.link_person!(%{claim_id: late.id, person_id: p.id})

    arc = Narrative.person_arc!(p.id) |> Enum.map(& &1.claim_id) |> Enum.sort()
    assert arc == Enum.sort([early.id, late.id])
  end

  test "a claim and a person of different events cannot link", %{draft: draft} do
    c = draft.(%{})
    other = event!()

    stranger =
      Narrative.identify_person!(%{event_id: other.id, full_name: "Antonio José Cabrera Meneses"})

    assert {:error, %Ash.Error.Invalid{}} =
             Narrative.link_person(%{claim_id: c.id, person_id: stranger.id})
  end

  test "place_mention is held on the claim as the raw text the resolver reads", %{draft: draft} do
    c = draft.(%{place_mention: "edificio OPP 25, Tanaguarena"})
    assert c.place_mention == "edificio OPP 25, Tanaguarena"
  end
end
