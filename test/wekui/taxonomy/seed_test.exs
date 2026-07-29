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
            "Persona desaparecida o sin contacto",
            "Solicitud de información"
          ] do
        assert MapSet.member?(names, name), "the seed lost #{inspect(name)}"
      end
    end

    # Each of these is a distinction the eight-day corpus could NOT teach, ruled by
    # the operator on 2026-07-28 out of knowledge of how a disaster ages. They are
    # tested by name because losing one is silent otherwise.
    test "a death and a body are two themes", %{event: event} do
      Seed.litoral_central(event.id)
      names = event.id |> Taxonomy.list_themes!() |> MapSet.new(& &1.name)

      # Many will be declared dead with no body ever found. A merged theme could not
      # tell the two apart, and the record would lose the difference forever.
      assert MapSet.member?(names, "Persona fallecida")
      assert MapSet.member?(names, "Cuerpo recuperado o identificado")
      refute MapSet.member?(names, "Persona fallecida o cuerpo recuperado")
    end

    test "asking for rescuers is not asking for fuel", %{event: event} do
      Seed.litoral_central(event.id)
      names = event.id |> Taxonomy.list_themes!() |> MapSet.new(& &1.name)

      assert MapSet.member?(names, "Solicitud de rescate")
      assert MapSet.member?(names, "Solicitud de recursos")
    end

    test "reaching the living is not recovering the dead", %{event: event} do
      Seed.litoral_central(event.id)
      names = event.id |> Taxonomy.list_themes!() |> MapSet.new(& &1.name)

      assert MapSet.member?(names, "Operación de rescate con vida")
      assert MapSet.member?(names, "Operación de recuperación de cuerpos")
    end

    test "the neighbours are in the record beside the international teams", %{event: event} do
      Seed.litoral_central(event.id)
      themes = Map.new(Taxonomy.list_themes!(event.id), &{&1.name, &1})

      # The readers saw international teams (17% of the sample) and missed the
      # neighbours — but the full corpus carries `vecin*` 215 times and `voluntari*`
      # 177. Loudness is not weight.
      assert themes["Apoyo vecinal o voluntario"]
      assert themes["Apoyo nacional desplegado"]

      family = themes["Apoyo desplegado"]
      assert themes["Apoyo internacional desplegado"].parent_id == family.id
    end

    test "aid is a chain, not an event", %{event: event} do
      Seed.litoral_central(event.id)
      themes = Map.new(Taxonomy.list_themes!(event.id), &{&1.name, &1})

      family = themes["Ayuda humanitaria"]
      assert themes["Centro de acopio"].parent_id == family.id
      assert themes["Logística y distribución de ayuda"].parent_id == family.id
      assert themes["Entrega de ayuda humanitaria"].parent_id == family.id
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

  # The loop closing for the first time: the machine proposed, the code measured, and
  # the word waits for a person. These four were not written from a desk — the
  # extractor's `unfitted` list reached for them on real posts, in repeated runs.
  describe "the themes the corpus asked for" do
    test "arrive proposed, like every other, and carry who proposed them", %{event: event} do
      Seed.litoral_central(event.id)
      themes = Map.new(Taxonomy.list_themes!(event.id), &{&1.name, &1})

      for name <- [
            "Saqueo de comercios",
            "Saqueo de viviendas",
            "Estado de los servicios básicos"
          ] do
        assert themes[name], "the seed lost #{inspect(name)}"
        assert themes[name].lifecycle == :proposed
      end
    end

    test "looting of shops and looting of homes are kept apart", %{event: event} do
      Seed.litoral_central(event.id)
      themes = Map.new(Taxonomy.list_themes!(event.id), &{&1.name, &1})

      # The extractor found them separately in every trial: shops emptied by a crowd,
      # and apartments robbed once the rescuers had gone. Two different things.
      assert themes["Saqueo de comercios"].applies_when =~ "business or commercial premises"
      assert themes["Saqueo de viviendas"].applies_when =~ "apartments, homes or vehicles"
      assert themes["Saqueo de comercios"].parent_id == themes["Seguridad y orden público"].id
      assert themes["Saqueo de viviendas"].parent_id == themes["Seguridad y orden público"].id
    end
  end
end
