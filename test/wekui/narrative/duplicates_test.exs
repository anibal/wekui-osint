defmodule Wekui.Narrative.DuplicatesTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.Duplicates

  setup do
    event = event!()

    %{
      event: event,
      agent: agent!(event),
      caribe: place!(event, %{canonical_name: "Residencias Caribe", type: "edificio"}),
      corales: place!(event, %{canonical_name: "Los Corales", type: "barrio"})
    }
  end

  defp claim!(ctx, attrs, place \\ nil) do
    claim =
      Narrative.draft_claim!(
        Map.merge(
          %{
            event_id: ctx.event.id,
            kind: "rescate",
            first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
            actor_id: ctx.agent.id,
            confidence: 0.9
          },
          attrs
        )
      )

    if place do
      Narrative.link_place!(%{
        claim_id: claim.id,
        place_id: place.id,
        how_resolved: :mention_exact,
        confidence: 0.9
      })
    end

    claim
  end

  defp found(ctx), do: Duplicates.find(ctx.event.id)

  # From claim.md: "a specific subject and magnitude — a man of 21, 106 hours — hold
  # across noisy or even wrong place labels".
  describe "a subject carrying its own mark" do
    test "is offered even when the two claims sit at different places", ctx do
      claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.caribe)
      claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.corales)

      assert [finding] = found(ctx)
      assert finding.why =~ "carries its own mark"
    end

    test "is offered even when neither claim was placed at all", ctx do
      claim!(ctx, %{subject: "un hombre de 21 años"})
      claim!(ctx, %{subject: "hombre de 21 años"})

      assert [_finding] = found(ctx)
    end

    test "a different number is a different happening", ctx do
      claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.caribe)
      claim!(ctx, %{subject: "un hombre de 31 años"}, ctx.caribe)

      assert found(ctx) == []
    end
  end

  # "while a generic subject — a woman — cannot, and there the place must tell them
  # apart. A woman missing in one building and a woman missing in another are two
  # claims."
  describe "a generic subject" do
    test "is offered only when both claims sit at the same place", ctx do
      claim!(ctx, %{subject: "una mujer"}, ctx.caribe)
      claim!(ctx, %{subject: "una mujer"}, ctx.caribe)

      assert [finding] = found(ctx)
      assert finding.why =~ "same place"
    end

    test "a woman in one building and a woman in another are two claims", ctx do
      claim!(ctx, %{subject: "una mujer"}, ctx.caribe)
      claim!(ctx, %{subject: "una mujer"}, ctx.corales)

      assert found(ctx) == []
    end

    test "two unplaced generic claims are not offered — absence is not agreement", ctx do
      claim!(ctx, %{subject: "una mujer"})
      claim!(ctx, %{subject: "una mujer"})

      assert found(ctx) == []
    end

    test "the same place a week apart is not one happening", ctx do
      claim!(ctx, %{subject: "una mujer"}, ctx.caribe)

      claim!(
        ctx,
        %{subject: "una mujer", first_seen_at: ~U[2026-07-02 04:00:00.000000Z]},
        ctx.caribe
      )

      assert found(ctx) == []
    end
  end

  describe "the kind of change" do
    test "a search and a rescue are two happenings in one story, not one told twice", ctx do
      claim!(ctx, %{kind: "búsqueda", subject: "un hombre de 21 años"}, ctx.caribe)
      claim!(ctx, %{kind: "rescate", subject: "un hombre de 21 años"}, ctx.caribe)

      assert found(ctx) == []
    end

    # `kind` is an open string the extractor writes, so one verb arrives at two
    # lengths.
    test "one verb spelled at two lengths is one kind", ctx do
      claim!(ctx, %{kind: "rescate", subject: "un hombre de 21 años"}, ctx.caribe)
      claim!(ctx, %{kind: "rescate en curso", subject: "un hombre de 21 años"}, ctx.caribe)

      assert [_finding] = found(ctx)
    end

    # Measured across two independent extractions of the same nine posts: comparing
    # whole kind strings caught one real duplicate out of eight, because the
    # extractor writes one change at wildly different lengths. Comparing the leading
    # word caught them all. Each of these is a pair that measurement missed.
    for {short, long} <- [
          {"búsqueda", "búsqueda de persona desaparecida"},
          {"colapso", "colapso de edificio"},
          {"rescate", "rescate de una mujer"},
          {"cifra oficial", "cifra oficial de fallecidos y heridos"}
        ] do
      test "“#{short}” and “#{long}” are one kind", ctx do
        claim!(ctx, %{kind: unquote(short), subject: "un hombre de 21 años"}, ctx.caribe)
        claim!(ctx, %{kind: unquote(long), subject: "un hombre de 21 años"}, ctx.caribe)

        assert [_finding] = found(ctx)
      end
    end

    test "a long description does not make two changes into one", ctx do
      claim!(
        ctx,
        %{kind: "búsqueda de persona desaparecida", subject: "un hombre de 21 años"},
        ctx.caribe
      )

      claim!(ctx, %{kind: "rescate de una persona", subject: "un hombre de 21 años"}, ctx.caribe)

      assert found(ctx) == []
    end

    # The most generic subject there is, so it takes the generic path: the place and
    # the clock have to agree.
    test "two claims with no subject need the same place", ctx do
      claim!(ctx, %{kind: "colapso"}, ctx.caribe)
      claim!(ctx, %{kind: "colapso de edificio"}, ctx.corales)

      assert found(ctx) == []
    end
  end

  describe "the pair it offers" do
    test "names the earlier account first — a happening lives at its first evidence", ctx do
      first =
        claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.caribe)

      later =
        claim!(
          ctx,
          %{subject: "un hombre de 21 años", first_seen_at: ~U[2026-06-25 09:00:00.000000Z]},
          ctx.caribe
        )

      assert [%{other: other, claim: claim}] = found(ctx)
      assert other.id == first.id
      assert claim.id == later.id
    end

    test "a merged pair stops being offered", ctx do
      one = claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.caribe)
      two = claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.corales)

      Wekui.Curation.merge_claims!(one, two, curator!(ctx.event), "one rescue")

      assert found(ctx) == []
    end

    test "a retracted claim is not offered", ctx do
      claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.caribe)

      ctx
      |> claim!(%{subject: "un hombre de 21 años"}, ctx.caribe)
      |> Narrative.retract_claim!()

      assert found(ctx) == []
    end
  end
end
