defmodule Wekui.Narrative.PersonDuplicatesTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.PersonDuplicates

  setup do
    event = event!()

    %{
      event: event,
      agent: agent!(event),
      caribe: place!(event, %{canonical_name: "Residencias Caribe", type: "edificio"})
    }
  end

  defp person!(ctx, full_name) do
    Narrative.identify_person!(%{event_id: ctx.event.id, full_name: full_name})
  end

  defp claim!(ctx, people) do
    claim =
      Narrative.draft_claim!(%{
        event_id: ctx.event.id,
        kind: "persona desaparecida",
        subject: "dos personas",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: ctx.agent.id,
        confidence: 0.9
      })

    Narrative.link_place!(%{
      claim_id: claim.id,
      place_id: ctx.caribe.id,
      how_resolved: :mention_exact,
      confidence: 0.9
    })

    for one <- people, do: Narrative.link_person!(%{claim_id: claim.id, person_id: one.id})
    claim
  end

  defp block_with(ctx, names) do
    Enum.find(PersonDuplicates.find(ctx.event.id), fn block ->
      held = MapSet.new(block.persons, & &1.full_name)
      Enum.all?(names, &MapSet.member?(held, &1))
    end)
  end

  # The upsert holds a name written the same way twice and nothing more. Measured on the
  # corpus: 668 rows, ZERO exact name collisions, and one woman holding four of them.
  # Exact matching reports "all clear" and is completely useless.
  describe "the blocks it offers" do
    test "one woman written four ways is offered together", ctx do
      for name <- [
            "Belkys Josefina Barreto García",
            "Belkis Josefina Barreto García",
            "Belkys Barreto",
            "Belkis Barreto"
          ] do
        person!(ctx, name)
      end

      assert block_with(ctx, ["Belkys Barreto", "Belkis Josefina Barreto García"])
    end

    # "Adriana" reads alike to Adriana Patricia Flores, Adriana Pérez Pérez and Adriana
    # Utrer — three different women — and transitive closure chained 223 unrelated
    # people into one block through names like it.
    test "a bare given name joins nobody by name alone", ctx do
      person!(ctx, "Adriana")
      person!(ctx, "Adriana Patricia Flores")
      person!(ctx, "Adriana Pérez Pérez")

      refute block_with(ctx, ["Adriana", "Adriana Patricia Flores"])
    end

    test "two people who share nothing are not offered", ctx do
      person!(ctx, "Gladismaria Pineda Ramirez")
      person!(ctx, "Mirta Guedez")

      assert PersonDuplicates.find(ctx.event.id) == []
    end

    # Names alone have a ceiling. Measured, context found 152 pairs the name rule missed.
    test "context offers a pair the name rule cannot reach", ctx do
      ezio = person!(ctx, "Ezio Narducci")
      miriam = person!(ctx, "Miriam Narducci")

      refute block_with(ctx, ["Ezio Narducci", "Miriam Narducci"])

      claim!(ctx, [ezio, miriam])

      assert block_with(ctx, ["Ezio Narducci", "Miriam Narducci"])
    end

    test "a row already merged away is never offered again", ctx do
      long = person!(ctx, "Belkys Josefina Barreto García")
      short = person!(ctx, "Belkis Barreto")

      assert block_with(ctx, ["Belkys Josefina Barreto García", "Belkis Barreto"])

      Narrative.merge_person!(short, %{merged_into_id: long.id, merge_note: "one woman"})

      refute block_with(ctx, ["Belkys Josefina Barreto García", "Belkis Barreto"])
    end
  end

  # The operator's rule: FIRST NAME · middle · FIRST SURNAME · second surname, and the
  # short everyday form is the same person as the long disaster form. It lives in code
  # because as prose the model would not obey it — told in its own text that "Belkis and
  # Belkys are one name", it split them anyway, in every run.
  describe "the same person by position" do
    test "the everyday form and the disaster form are one person" do
      assert PersonDuplicates.same_by_position?(
               "Belkys Barreto",
               "Belkys Josefina Barreto García"
             )
    end

    test "spelling is not identity" do
      assert PersonDuplicates.same_by_position?("Belkis Barreto", "Belkys Barreto")

      assert PersonDuplicates.same_by_position?(
               "Belkis Josefina Barreto Garcia",
               "Belkys Josefina Barreto García"
             )
    end

    # Two sisters carry BOTH surnames identically. Everything matches except the part
    # that identifies, and merging them erases a girl.
    test "two sisters are two people" do
      refute PersonDuplicates.same_by_position?(
               "Valentina Juliette Azocar Milano",
               "Victoria Antonela Azocar Milano"
             )
    end

    test "a different first name is a different person, however much else matches" do
      refute PersonDuplicates.same_by_position?("Cattleya Guanipa", "Nayhara Guanipa")
      refute PersonDuplicates.same_by_position?("Ali García", "José García")
    end

    # "José Luis Pérez" is a first name, a middle name and one surname; "José Pérez
    # García" is a first name and two surnames. Both are three words, so no rule that
    # counts positions can tell them apart.
    test "a different surname is a different person, at the same word count" do
      refute PersonDuplicates.same_by_position?("José Luis Pérez", "José Luis Ramírez")
    end

    test "a one-word name identifies nobody" do
      refute PersonDuplicates.same_by_position?("Adriana", "Adriana Patricia Flores")
      refute PersonDuplicates.same_by_position?("Belkys", "Belkys Barreto")
    end

    # Where a surname is split is a matter of spelling, not of naming — the same lesson
    # the gazetteer learned on "Mc Donalds" against "McDonald's".
    test "a surname written as one word is the same surname" do
      assert PersonDuplicates.same_by_position?(
               "María Fernanda Rey Rujano",
               "María Fernanda Reyrujan"
             )
    end
  end

  # Families live together, so families were buried together and are asked after in one
  # post. Being named together means DIFFERENT people; reading it the other way round
  # merged whole families.
  describe "who a person is named beside" do
    test "two people in one claim are recorded as named together", ctx do
      one = person!(ctx, "Cattleya Guanipa")
      other = person!(ctx, "Nayhara Guanipa")

      claim!(ctx, [one, other])

      beside = PersonDuplicates.beside(ctx.event.id)
      assert MapSet.member?(beside[one.id], other.id)
      assert MapSet.member?(beside[other.id], one.id)
    end

    test "two people in separate claims are not named together", ctx do
      one = person!(ctx, "Cattleya Guanipa")
      other = person!(ctx, "Nayhara Guanipa")

      claim!(ctx, [one])
      claim!(ctx, [other])

      beside = PersonDuplicates.beside(ctx.event.id)
      refute Map.has_key?(beside, one.id)
    end
  end
end
