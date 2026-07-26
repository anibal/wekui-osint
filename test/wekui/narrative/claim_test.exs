defmodule Wekui.Narrative.ClaimTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative

  setup do
    event = event!()

    %{
      event: event,
      agent: agent!(event),
      post: post!(event)
    }
  end

  defp claim_attrs(ctx, attrs \\ %{}) do
    Map.merge(
      %{
        event_id: ctx.event.id,
        kind: "rescate",
        subject: "un hombre de 21 años",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: ctx.agent.id,
        confidence: 0.9
      },
      attrs
    )
  end

  defp draft!(ctx, attrs \\ %{}), do: Narrative.draft_claim!(claim_attrs(ctx, attrs))
  defp draft(ctx, attrs), do: Narrative.draft_claim(claim_attrs(ctx, attrs))

  describe "draft — recording an account of a happening" do
    test "records the claim's structured fields; it is current", ctx do
      c = draft!(ctx, %{magnitude: %{"hours" => 106}, status: "rescatado"})

      assert c.event_id == ctx.event.id
      assert c.kind == "rescate"
      assert c.subject == "un hombre de 21 años"
      assert c.magnitude == %{"hours" => 106}
      assert c.status == "rescatado"
      assert c.actor_id == ctx.agent.id
      assert c.confidence == 0.9
      assert c.first_seen_at == ~U[2026-06-25 04:00:00.000000Z]
      assert c.superseded_at == nil
    end

    for field <- [:event_id, :kind, :first_seen_at, :actor_id] do
      test "requires #{field}", ctx do
        assert {:error, %Ash.Error.Invalid{}} =
                 Narrative.draft_claim(Map.delete(claim_attrs(ctx), unquote(field)))
      end
    end

    test "an agent's claim requires a confidence", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Narrative.draft_claim(Map.delete(claim_attrs(ctx), :confidence))
    end

    # A claim's Places are ClaimPlace links resolved from place_mention, not an
    # attribute set at draft time — see Wekui.Narrative.ClaimPlaceTest.
  end

  describe "a claim's references must belong to its Event" do
    setup do
      %{other: event!()}
    end

    test "rejects an Actor from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} = draft(ctx, %{actor_id: agent!(ctx.other).id})
    end
  end

  describe "retraction" do
    test "closes the claim without a successor", ctx do
      c = draft!(ctx)
      Narrative.retract_claim!(c)

      reloaded = Narrative.get_claim!(c.id)
      assert reloaded.superseded_at != nil
      assert reloaded.superseded_by_id == nil
    end

    test "refuses to reclose an already-closed claim", ctx do
      c = draft!(ctx)
      Narrative.retract_claim!(c)
      assert {:error, %Ash.Error.Invalid{}} = Narrative.retract_claim(c)
    end
  end

  describe "reads" do
    test "by_event scopes claims to one Event, oldest first", ctx do
      other = event!()
      a = draft!(ctx)
      b = draft!(ctx, %{kind: "colapso", subject: nil})

      assert Enum.map(Narrative.list_claims!(ctx.event.id), & &1.id) == [a.id, b.id]
      assert Narrative.list_claims!(other.id) == []
    end

    test "current_for_event excludes a retracted claim, earliest happening first", ctx do
      early = draft!(ctx, %{first_seen_at: ~U[2026-06-25 02:00:00.000000Z]})
      late = draft!(ctx, %{first_seen_at: ~U[2026-06-25 06:00:00.000000Z]})
      gone = draft!(ctx, %{first_seen_at: ~U[2026-06-25 03:00:00.000000Z]})
      Narrative.retract_claim!(gone)

      assert Enum.map(Narrative.current_claims!(ctx.event.id), & &1.id) == [early.id, late.id]
    end
  end

  describe "citations — the Posts that evidence a claim" do
    test "cites a Post, and citing the same Post again changes nothing", ctx do
      c = draft!(ctx)
      first = Narrative.cite_post!(%{claim_id: c.id, post_id: ctx.post.id})
      again = Narrative.cite_post!(%{claim_id: c.id, post_id: ctx.post.id})

      assert again.id == first.id
      assert Enum.map(Narrative.list_claim_citations!(c.id), & &1.id) == [first.id]
    end

    test "rejects a Post from another Event", ctx do
      c = draft!(ctx)
      other_post = post!(event!())

      assert {:error, %Ash.Error.Invalid{}} =
               Narrative.cite_post(%{claim_id: c.id, post_id: other_post.id})
    end
  end

  describe "the person red line — no private individual is named" do
    test "refuses a private name in the subject", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               draft(ctx, %{subject: "Belkys Josefina Barreto García"})
    end

    test "refuses a private name in the nuance", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               draft(ctx, %{nuance: "rescatada junto a Pedro Ramírez González"})
    end

    test "accepts a role-only subject", ctx do
      assert %{} = draft!(ctx, %{subject: "una mujer de 60 años y sus dos hijos"})
    end

    test "a public figure may be named in a nuance but never in a subject", ctx do
      assert %{} = draft!(ctx, %{subject: nil, nuance: "según el presidente Nicolás Maduro"})
      assert {:error, %Ash.Error.Invalid{}} = draft(ctx, %{subject: "Nicolás Maduro"})
    end

    test "the Montero hole is closed — a public figure used to place a private person is refused",
         ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               draft(ctx, %{subject: "el padre de la pianista Gabriela Montero"})
    end

    test "an institution passes even the strict subject", ctx do
      assert %{} = draft!(ctx, %{subject: "USAR El Salvador"})
    end
  end
end
