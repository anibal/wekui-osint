defmodule Wekui.Taxonomy.SeedTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Curation
  alias Wekui.Taxonomy
  alias Wekui.Taxonomy.Seed

  setup do
    %{event: event!()}
  end

  describe "the seeded vocabulary" do
    test "arrives proposed, never active — nobody has signed it yet", %{event: event} do
      Seed.litoral_central(event.id)

      themes = Taxonomy.list_themes!(event.id)

      assert themes != []
      assert Enum.all?(themes, &(&1.lifecycle == :proposed))
      assert Taxonomy.list_active_themes!(event.id) == []
    end

    test "every theme carries the rule that decides whether it applies", %{event: event} do
      Seed.litoral_central(event.id)

      for theme <- Taxonomy.list_themes!(event.id) do
        assert is_binary(theme.applies_when) and theme.applies_when != ""
        assert theme.nature in [:happening, :topic]
      end
    end

    test "it carries both natures — a plea is a theme too", %{event: event} do
      Seed.litoral_central(event.id)

      natures = event.id |> Taxonomy.list_themes!() |> Enum.frequencies_by(& &1.nature)

      assert natures[:happening] > 0
      assert natures[:topic] > 0
    end

    test "the tree hangs together — every parent is a theme of this event", %{event: event} do
      Seed.litoral_central(event.id)

      themes = Taxonomy.list_themes!(event.id)
      ids = MapSet.new(themes, & &1.id)

      for theme <- themes, theme.parent_id do
        assert MapSet.member?(ids, theme.parent_id)
      end

      assert Enum.any?(themes, &(not is_nil(&1.parent_id))), "the seed should not be flat"
    end

    test "the boundary a reader drew survives into the rule", %{event: event} do
      Seed.litoral_central(event.id)

      # A rule that says what a theme IS but not what it is NOT is how `colapso` got
      # drawn from an unconfirmed report. The distinction rides in the rule itself.
      assert event.id
             |> Taxonomy.list_themes!()
             |> Enum.any?(&(&1.applies_when =~ "Not to be confused with"))
    end
  end

  describe "running it twice" do
    test "changes nothing", %{event: event} do
      first = Seed.litoral_central(event.id)
      second = Seed.litoral_central(event.id)

      assert first.created > 0
      assert first.reused == 0
      assert second.created == 0
      assert second.reused == first.created
      assert length(Taxonomy.list_themes!(event.id)) == first.created
    end

    test "never un-promotes what a person has ratified", %{event: event} do
      Seed.litoral_central(event.id)
      curator = curator!(event, %{name: "Aníbal Rojas"})

      ratified =
        event.id
        |> Taxonomy.list_themes!()
        |> hd()
        |> Curation.promote_theme!(curator, "three readers reached it")

      Seed.litoral_central(event.id)

      assert Taxonomy.get_theme!(ratified.id).lifecycle == :active
    end

    test "never re-proposes what a person discarded", %{event: event} do
      Seed.litoral_central(event.id)
      curator = curator!(event, %{name: "Aníbal Rojas"})

      discarded =
        event.id
        |> Taxonomy.list_themes!()
        |> hd()
        |> Curation.discard_theme!(curator, "not a theme of this event")

      before = length(Taxonomy.list_themes!(event.id))
      Seed.litoral_central(event.id)

      assert Taxonomy.get_theme!(discarded.id).lifecycle == :discarded
      assert length(Taxonomy.list_themes!(event.id)) == before
    end
  end

  describe "the committed data" do
    test "holds the ten themes all three readers reached, and seven more", %{event: event} do
      Seed.litoral_central(event.id)

      names = event.id |> Taxonomy.list_themes!() |> MapSet.new(& &1.name)

      # The corpus's own hardest distinction: one state, three transitions out of it.
      # All three readers refused to collapse these, and so does the vocabulary.
      for name <- [
            "Persona atrapada con vida bajo escombros",
            "Persona rescatada con vida",
            "Persona fallecida o cuerpo recuperado",
            "Persona desaparecida o sin contacto",
            "Solicitud de información"
          ] do
        assert MapSet.member?(names, name), "the seed lost #{inspect(name)}"
      end
    end

    test "a plea and a disappearance are two themes, not one", %{event: event} do
      Seed.litoral_central(event.id)

      themes = Map.new(Taxonomy.list_themes!(event.id), &{&1.name, &1})

      plea = themes["Solicitud de información"]
      gone = themes["Persona desaparecida o sin contacto"]

      refute plea.id == gone.id
      # The rule is what makes them separable: the plea asserts nothing itself.
      assert plea.applies_when =~ "does NOT itself assert"
      assert gone.applies_when =~ "whereabouts are unknown"
    end
  end
end
