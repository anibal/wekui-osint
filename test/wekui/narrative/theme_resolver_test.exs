defmodule Wekui.Narrative.ThemeResolverTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative.ThemeResolver

  setup do
    event = event!()

    themes =
      Map.new(
        [
          {"Colapso estructural", :happening},
          {"Persona rescatada con vida", :happening},
          {"Cuerpo recuperado o identificado", :happening},
          {"Solicitud de información", :topic}
        ],
        fn {name, nature} ->
          {name,
           theme!(event, %{
             name: name,
             applies_when: "the post states that #{name} happened",
             nature: nature
           })}
        end
      )

    %{event: event, themes: themes}
  end

  defp resolve(ctx, kind), do: ThemeResolver.resolve(ctx.event.id, kind)

  describe "filing the extractor's own words under the vocabulary" do
    test "an exact name lands on itself", ctx do
      assert {:ok, theme} = resolve(ctx, "Colapso estructural")
      assert theme.id == ctx.themes["Colapso estructural"].id
    end

    test "a kind that answers every word of the name lands on it", ctx do
      for kind <- [
            "colapso estructural",
            "COLAPSO ESTRUCTURAL",
            "colapso estructural de un edificio"
          ] do
        assert {:ok, theme} = resolve(ctx, kind)
        assert theme.id == ctx.themes["Colapso estructural"].id, "#{kind} went elsewhere"
      end
    end

    test "a kind that answers every word lands even when reordered", ctx do
      assert {:ok, theme} = resolve(ctx, "rescatada con vida una persona")
      assert theme.id == ctx.themes["Persona rescatada con vida"].id
    end
  end

  # Measured on the record, and the reason this module refuses so much. An earlier,
  # eager version scored on the LEADING WORD — a rule that works between two extractor
  # outputs and does not travel to a curated name, where the rest of the name is the
  # whole point.
  describe "the mis-filings that set the bar" do
    test "a bare “rescate” is not a rescued ANIMAL", ctx do
      # It filed five rescued people under `Rescate de animal`. `animal` is exactly
      # what distinguishes that theme, and "rescate" does not answer it.
      assert :no_theme = resolve(ctx, "rescate")
      assert :no_theme = resolve(ctx, "rescate en curso")
    end

    test "a bare “colapso” is refused too, and that is the right trade", ctx do
      # We lose a filing we could probably have made. A claim left unfiled is silent
      # and honest; a claim filed wrongly says something nobody wrote.
      assert :no_theme = resolve(ctx, "colapso")
    end
  end

  describe "what it refuses" do
    test "a topic is never a claim's theme, however exactly it reads", ctx do
      # The post may be about a plea; nothing occurred that a claim could assert.
      assert :no_theme = resolve(ctx, "Solicitud de información")
    end

    test "a kind the vocabulary has no word for is left unfiled", ctx do
      assert :no_theme = resolve(ctx, "saqueo")
      assert :no_theme = resolve(ctx, "vigilia por las víctimas")
    end

    test "a theme nobody ratified cannot be filed under", ctx do
      Wekui.Taxonomy.create_theme!(%{
        event_id: ctx.event.id,
        name: "saqueo",
        applies_when: "the post states that looting occurred",
        nature: :happening
      })

      assert :no_theme = resolve(ctx, "saqueo")
    end

    test "nothing, and noise, resolve to nothing", ctx do
      assert :no_theme = resolve(ctx, "")
      assert :no_theme = resolve(ctx, "de la")
      assert :no_theme = resolve(ctx, nil)
    end

    test "an event with no vocabulary files nothing", %{event: _} do
      assert :no_theme = ThemeResolver.resolve(event!().id, "colapso")
    end
  end
end
