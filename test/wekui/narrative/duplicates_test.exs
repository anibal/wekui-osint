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

  # A place only tells two accounts apart if it COULD have. 380 of 2,596 claims sat at
  # «Caraballeda» the parroquia because that is where the whole corpus is, and counting
  # that as agreement built one group of 61 support claims and another of 35 collapses —
  # 1,740 of 3,213 pairs saying only that everything happened in Caraballeda.
  describe "a place that says where the corpus is" do
    test "sharing the parroquia everything is in is not sharing a place", ctx do
      parroquia = place!(ctx.event, %{canonical_name: "Caraballeda", type: "parroquia"})

      claim!(ctx, %{kind: "colapso de edificio"}, parroquia)
      claim!(ctx, %{kind: "colapso de edificio"}, parroquia)

      assert found(ctx) == []
    end

    test "sharing a building still is", ctx do
      claim!(ctx, %{kind: "colapso de edificio"}, ctx.caribe)
      claim!(ctx, %{kind: "colapso de edificio"}, ctx.caribe)

      assert [_finding] = found(ctx)
    end

    # The subject carries its own mark, so the place never had to decide.
    test "a subject with its own mark does not need a place at all", ctx do
      parroquia = place!(ctx.event, %{canonical_name: "Caraballeda", type: "parroquia"})

      claim!(ctx, %{subject: "un hombre de 21 años"}, parroquia)
      claim!(ctx, %{subject: "un hombre de 21 años"}, parroquia)

      assert [_finding] = found(ctx)
    end

    test "a building shared beside the parroquia is enough", ctx do
      parroquia = place!(ctx.event, %{canonical_name: "Caraballeda", type: "parroquia"})

      one = claim!(ctx, %{kind: "colapso de edificio"}, parroquia)
      two = claim!(ctx, %{kind: "colapso de edificio"}, parroquia)

      for claim <- [one, two] do
        Narrative.link_place!(%{
          claim_id: claim.id,
          place_id: ctx.caribe.id,
          how_resolved: :mention_exact,
          confidence: 0.9
        })
      end

      assert [_finding] = found(ctx)
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

  # The record already knows WHO. Two women of 60 went missing in one building; both
  # claims read "una mujer de 60 años" and scored a perfect match, and two adversarial
  # readings agreed they were one happening. The Person rows behind them said
  # "gladismaria pineda ramirez" and "mirta guedez" the whole time.
  describe "the persons a claim names" do
    defp person!(ctx, full_name) do
      Narrative.identify_person!(%{event_id: ctx.event.id, full_name: full_name})
    end

    defp about!(claim, person) do
      Narrative.link_person!(%{claim_id: claim.id, person_id: person.id})
      claim
    end

    test "two claims naming different people are never one happening", ctx do
      ctx
      |> claim!(%{kind: "persona desaparecida", subject: "una mujer de 60 años"}, ctx.caribe)
      |> about!(person!(ctx, "Gladismaria Pineda Ramirez"))

      ctx
      |> claim!(%{kind: "persona desaparecida", subject: "una mujer de 60 años"}, ctx.caribe)
      |> about!(person!(ctx, "Mirta Guedez"))

      assert found(ctx) == []
    end

    test "a dropped middle name is not a different person", ctx do
      # One woman, four Person rows on the real corpus. A name written short is still
      # her name.
      ctx
      |> claim!(%{kind: "rescate", subject: "una mujer de 60 años"}, ctx.caribe)
      |> about!(person!(ctx, "Belkys Josefina Barreto García"))

      ctx
      |> claim!(%{kind: "rescate", subject: "una mujer de 60 años"}, ctx.caribe)
      |> about!(person!(ctx, "Belkis Barreto"))

      assert [_finding] = found(ctx)
    end

    test "a claim that names nobody does not disagree with one that does", ctx do
      ctx
      |> claim!(%{kind: "persona desaparecida", subject: "un hombre de 21 años"}, ctx.caribe)
      |> about!(person!(ctx, "Aaron Colmenares"))

      claim!(ctx, %{kind: "persona desaparecida", subject: "un hombre de 21 años"}, ctx.caribe)

      assert [_finding] = found(ctx)
    end

    test "two claims naming the same person still stand together", ctx do
      person = person!(ctx, "Aaron Colmenares")

      ctx
      |> claim!(%{kind: "persona desaparecida", subject: "un hombre de 21 años"}, ctx.caribe)
      |> about!(person)

      ctx
      |> claim!(%{kind: "persona desaparecida", subject: "un hombre de 21 años"}, ctx.corales)
      |> about!(person)

      assert [_finding] = found(ctx)
    end

    # Two men sharing a first and middle name are two men. The bar has to sit above
    # that, or the gate is decoration.
    test "a shared given name is not a shared identity", ctx do
      ctx
      |> claim!(%{kind: "cuerpo recuperado", subject: "un hombre"}, ctx.caribe)
      |> about!(person!(ctx, "José Luis Pérez"))

      ctx
      |> claim!(%{kind: "cuerpo recuperado", subject: "un hombre"}, ctx.caribe)
      |> about!(person!(ctx, "José Luis Ramírez"))

      assert found(ctx) == []
    end
  end

  # `String.jaro_distance("", "")` is 1.0, so two claims that name no subject at all
  # scored a PERFECT match on subjects neither of them had — and sorting on the number
  # put 2,467 such pairs, 77% of the corpus's findings, above every pair resting on
  # something. The number was never wrong. It was answering a question nobody asked.
  describe "what the pair rests on" do
    test "two absent subjects are named as absent, not as a perfect match", ctx do
      claim!(ctx, %{kind: "colapso de edificio", subject: nil}, ctx.caribe)
      claim!(ctx, %{kind: "colapso de edificio", subject: nil}, ctx.caribe)

      assert [finding] = found(ctx)
      assert finding.subjects == :absent
      assert finding.why =~ "NEITHER NAMES A SUBJECT"
      # And it does not print an empty dash where a subject would go.
      refute finding.why =~ "— ”"
    end

    test "a subject carrying a number outranks one that does not, and both outrank none",
         ctx do
      claim!(ctx, %{kind: "colapso de edificio", subject: nil}, ctx.caribe)
      claim!(ctx, %{kind: "colapso de edificio", subject: nil}, ctx.caribe)
      claim!(ctx, %{kind: "rescate", subject: "una mujer"}, ctx.caribe)
      claim!(ctx, %{kind: "rescate", subject: "una mujer"}, ctx.caribe)
      claim!(ctx, %{kind: "rescate", subject: "un hombre de 21 años"}, ctx.caribe)
      claim!(ctx, %{kind: "rescate", subject: "un hombre de 21 años"}, ctx.caribe)

      assert [:mark | rest] = Enum.map(found(ctx), & &1.subjects)
      assert :generic in rest
      assert List.last(rest) == :absent
    end
  end

  # The finder is pairwise because its rule is. A corpus is not: 258 accounts of one
  # collapse make thousands of pairs saying one thing.
  describe "grouping the pairs a person has to read" do
    test "three accounts of one happening are one group, not three pairs", ctx do
      for _one_of_three <- 1..3 do
        claim!(ctx, %{subject: "un niño de 11 años"}, ctx.caribe)
      end

      pairs = found(ctx)
      assert length(pairs) == 3

      assert [group] = Duplicates.cluster(pairs)
      assert group.size == 3
      assert length(group.pairs) == 3
    end

    test "two unrelated happenings stay two groups", ctx do
      claim!(ctx, %{subject: "un niño de 11 años"}, ctx.caribe)
      claim!(ctx, %{subject: "un niño de 11 años"}, ctx.caribe)
      claim!(ctx, %{subject: "una mujer de 40 años"}, ctx.corales)
      claim!(ctx, %{subject: "una mujer de 40 años"}, ctx.corales)

      assert [one, two] = Duplicates.cluster(found(ctx))
      assert one.size == 2
      assert two.size == 2
    end

    # Connectedness is not transitive identity. A generic account joins two specific
    # ones that are plainly different things, and the group holds all three — which is
    # exactly why a group is a candidate to look at, never an assertion to act on.
    test "a group can hold two happenings joined through a third", ctx do
      claim!(ctx, %{kind: "equipo extranjero", subject: nil}, ctx.caribe)
      claim!(ctx, %{kind: "equipo extranjero de El Salvador", subject: nil}, ctx.caribe)
      claim!(ctx, %{kind: "equipo extranjero de Perú", subject: nil}, ctx.caribe)

      assert [group] = Duplicates.cluster(found(ctx))
      assert group.size == 3
    end

    test "the largest group comes first", ctx do
      for _one_of_four <- 1..4, do: claim!(ctx, %{subject: "un niño de 11 años"}, ctx.caribe)
      claim!(ctx, %{subject: "una mujer de 40 años"}, ctx.corales)
      claim!(ctx, %{subject: "una mujer de 40 años"}, ctx.corales)

      assert [big, small] = Duplicates.cluster(found(ctx))
      assert big.size == 4
      assert small.size == 2
    end

    test "no pairs are no groups" do
      assert Duplicates.cluster([]) == []
    end
  end
end
