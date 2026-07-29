defmodule Wekui.Narrative.PersonMergeTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.PersonMerge

  setup do
    event = event!()
    %{event: event, agent: agent!(event)}
  end

  defp person!(ctx, full_name) do
    Narrative.identify_person!(%{event_id: ctx.event.id, full_name: full_name})
  end

  defp claim!(ctx, people) do
    claim =
      Narrative.draft_claim!(%{
        event_id: ctx.event.id,
        kind: "rescate con vida",
        subject: "una mujer de 60 años",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: ctx.agent.id,
        confidence: 0.9
      })

    for one <- people, do: Narrative.link_person!(%{claim_id: claim.id, person_id: one.id})
    claim
  end

  # A claim lives at its FIRST evidence, so the earlier account is canonical there. A
  # person does not live at their first mention: the fullest name identifies them best
  # and makes the better handle.
  describe "which row survives" do
    test "the fullest name does, whichever way round it is handed over", ctx do
      short = person!(ctx, "Belkis Barreto")
      long = person!(ctx, "Belkys Josefina Barreto García")

      assert {:ok, survivor} = PersonMerge.merge(short, long, "one woman")
      assert survivor.full_name == "Belkys Josefina Barreto García"

      other_short = person!(ctx, "Belkys Barreto")
      assert {:ok, again} = PersonMerge.merge(survivor, other_short, "one woman")
      assert again.full_name == "Belkys Josefina Barreto García"
    end

    # An accent alone never gets this far: `identify` folds it, so "Ana López" and
    # "Ana Lopez" are already one row. These differ by a sound Spanish does not make.
    test "a tie falls to the earlier row, so the answer never depends on order", ctx do
      first = person!(ctx, "Ana Lopez")
      second = person!(ctx, "Ana Lopes")

      assert {:ok, survivor} = PersonMerge.merge(second, first, "one woman")
      assert survivor.id == first.id
    end
  end

  # A deprecation, never a rewrite. Nothing is deleted, so a wrong merge is legible and
  # reversible afterwards — which is what makes it safe for a machine to do.
  describe "what a merge leaves behind" do
    test "the folded row keeps its name and says what it became", ctx do
      short = person!(ctx, "Belkis Barreto")
      long = person!(ctx, "Belkys Josefina Barreto García")

      assert {:ok, survivor} = PersonMerge.merge(short, long, "same first name and surname")

      assert {:ok, folded} = Narrative.get_person(short.id)
      assert folded.full_name == "Belkis Barreto"
      assert folded.merged_into_id == survivor.id
      assert folded.merge_note == "same first name and surname"
      assert folded.merged_at
    end

    test "the survivor takes on the claims that named the other", ctx do
      short = person!(ctx, "Belkis Barreto")
      long = person!(ctx, "Belkys Josefina Barreto García")
      claim = claim!(ctx, [short])

      assert {:ok, survivor} = PersonMerge.merge(short, long, "one woman")

      named = claim.id |> Narrative.list_claim_persons!() |> Enum.map(& &1.person_id)
      assert survivor.id in named
    end

    # ClaimPerson is an immutable upsert. Deleting the old link would erase the true
    # fact that this post said "Belkis Barreto".
    test "the claim keeps its link to the name the post actually used", ctx do
      short = person!(ctx, "Belkis Barreto")
      long = person!(ctx, "Belkys Josefina Barreto García")
      claim = claim!(ctx, [short])

      assert {:ok, _survivor} = PersonMerge.merge(short, long, "one woman")

      named = claim.id |> Narrative.list_claim_persons!() |> Enum.map(& &1.person_id)
      assert short.id in named
    end

    test "a folded row stops being current, and nothing is deleted", ctx do
      short = person!(ctx, "Belkis Barreto")
      long = person!(ctx, "Belkys Josefina Barreto García")

      assert {:ok, survivor} = PersonMerge.merge(short, long, "one woman")

      current = ctx.event.id |> Narrative.current_persons!() |> Enum.map(& &1.id)
      assert current == [survivor.id]
      assert length(Narrative.list_persons!(ctx.event.id)) == 2
    end

    test "current/1 follows a chain to its end", ctx do
      a = person!(ctx, "Belkis Barreto")
      b = person!(ctx, "Belkys Barreto")
      c = person!(ctx, "Belkys Josefina Barreto García")

      # a and b tie on length, so the earlier row — a — survives the first fold.
      assert {:ok, first} = PersonMerge.merge(a, b, "one woman")
      assert first.id == a.id

      assert {:ok, survivor} = PersonMerge.merge(first, c, "one woman")
      assert survivor.id == c.id

      # b was folded into a, and a into c: reading through must reach the end.
      assert b.id |> Narrative.get_person!() |> PersonMerge.current() |> Map.get(:id) ==
               survivor.id
    end
  end

  describe "what it refuses" do
    test "a row merged with itself", ctx do
      one = person!(ctx, "Belkis Barreto")
      assert {:error, :same_person} = PersonMerge.merge(one, one, "why")
    end

    test "two rows of different events", ctx do
      other_event = event!()
      one = person!(ctx, "Belkis Barreto")
      two = Narrative.identify_person!(%{event_id: other_event.id, full_name: "Belkys Barreto"})

      assert {:error, :different_events} = PersonMerge.merge(one, two, "why")
    end

    # The survivor of the first merge is where a second one belongs, or the chain says
    # two different things about one person.
    test "a row that has already been folded away", ctx do
      short = person!(ctx, "Belkis Barreto")
      long = person!(ctx, "Belkys Josefina Barreto García")
      third = person!(ctx, "Belkys Barreto")

      assert {:ok, _survivor} = PersonMerge.merge(short, long, "one woman")
      assert {:error, :already_merged} = PersonMerge.merge(short, third, "one woman")
    end
  end
end
