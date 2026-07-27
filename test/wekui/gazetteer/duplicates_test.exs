defmodule Wekui.Gazetteer.DuplicatesTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Gazetteer.Duplicates

  setup do
    event = event!()
    parroquia = place!(event, %{canonical_name: "Caraballeda", type: "parroquia"})

    %{event: event, parroquia: parroquia}
  end

  defp under(ctx, parent, name, type \\ "edificio") do
    place!(ctx.event, %{canonical_name: name, type: type, parent_id: parent.id})
  end

  defp found(ctx), do: Duplicates.find(ctx.event.id)

  defp pair?(findings, one, other) do
    Enum.any?(findings, fn f ->
      MapSet.new([f.place.canonical_name, f.other.canonical_name]) == MapSet.new([one, other])
    end)
  end

  describe "a place carrying its own ancestor's name" do
    # The operator's ruling, 2026-07-27: "Caraballeda is the Parish. Sector
    # Caraballeda, Urbanización Caraballeda, and any other combination are just
    # alternatives from the popular speech."
    test "is certain — a place cannot be inside itself", ctx do
      under(ctx, ctx.parroquia, "Caraballeda", "populated_place")

      assert [%{certainty: :certain} = finding] = found(ctx)
      assert finding.place.type == "populated_place"
      assert finding.other.id == ctx.parroquia.id
      assert finding.why =~ "cannot be inside itself"
    end

    test "is found however deep it sits", ctx do
      sector = under(ctx, ctx.parroquia, "Tanaguarena", "sector")
      under(ctx, sector, "Caraballeda", "urbanizacion")

      assert [%{certainty: :certain, other: other}] = found(ctx)
      assert other.id == ctx.parroquia.id
    end

    test "a folded duplicate stops being offered", ctx do
      duplicate = under(ctx, ctx.parroquia, "Caraballeda", "populated_place")
      curator = curator!(ctx.event)

      Wekui.Curation.fold_place_into!(duplicate, ctx.parroquia, curator, "popular speech")

      assert found(ctx) == []
    end
  end

  # The line the operator's ruling does NOT cross, and the reason the type-word
  # reduction is never applied against an ancestor: a building named after the area
  # it stands in is exactly the granularity the recursive model exists to hold.
  describe "a place named after the area it stands in" do
    test "is not a duplicate, however cleanly its type word strips off", ctx do
      under(ctx, ctx.parroquia, "Residencias Caraballeda")

      assert found(ctx) == []
    end

    test "still not a duplicate two levels down", ctx do
      sector = under(ctx, ctx.parroquia, "Los Corales", "sector")
      under(ctx, sector, "Residencias Los Corales")

      assert found(ctx) == []
    end
  end

  describe "two spellings of one name" do
    test "a dropped type word makes them one", ctx do
      under(ctx, ctx.parroquia, "La Costanera", "calle")
      under(ctx, ctx.parroquia, "Avenida La Costanera", "calle")

      assert pair?(found(ctx), "La Costanera", "Avenida La Costanera")
    end

    test "an accent typo makes them one", ctx do
      under(ctx, ctx.parroquia, "Cueva de Uría", "sector")
      under(ctx, ctx.parroquia, "Cueva de Urie", "sector")

      assert pair?(found(ctx), "Cueva de Uría", "Cueva de Urie")
    end

    # Word segmentation is a matter of spelling, not of naming. This pair scores
    # only 0.91 word-for-word — under the bar — and 1.0 once the spaces come out.
    test "a word split in two makes them one", ctx do
      under(ctx, ctx.parroquia, "McDonald's de Caraballeda")
      under(ctx, ctx.parroquia, "Mc Donalds de Caraballeda")

      assert pair?(found(ctx), "McDonald's de Caraballeda", "Mc Donalds de Caraballeda")
    end

    # The duplicate parish put these under different parents in the first place, so
    # a rule that only looked sideways would miss what the older defect created.
    test "they are found under different parents", ctx do
      sector = under(ctx, ctx.parroquia, "Tanaguarena", "sector")
      under(ctx, ctx.parroquia, "opp 27")
      under(ctx, sector, "OPPE 27")

      assert pair?(found(ctx), "opp 27", "OPPE 27")
    end
  end

  # The token that differs is the token that distinguishes. These score as high as
  # the real duplicates above and are not duplicates at all.
  describe "names that differ by what tells them apart" do
    test "a compass direction is never a spelling variant", ctx do
      under(ctx, ctx.parroquia, "El Palmar Este", "sector")
      under(ctx, ctx.parroquia, "El Palmar Oeste", "sector")

      assert found(ctx) == []
    end

    test "a number is never a spelling variant", ctx do
      under(ctx, ctx.parroquia, "Residencias Green 7 Suites")
      under(ctx, ctx.parroquia, "Residencias Green 8 suites")

      assert found(ctx) == []
    end

    test "but the same number written differently still matches", ctx do
      under(ctx, ctx.parroquia, "opp 27")
      under(ctx, ctx.parroquia, "Edificio Opp27")

      assert pair?(found(ctx), "opp 27", "Edificio Opp27")
    end
  end

  # The operator ruled these apart on 2026-07-27, on the two pairs that matched most
  # perfectly of all. What he was saying was not "not these two" but "not this kind".
  describe "a road, an area and a structure are three kinds of thing" do
    test "the avenue named after the strip is not the strip", ctx do
      under(ctx, ctx.parroquia, "La Costanera", "sector")
      under(ctx, ctx.parroquia, "Avenida La Costanera", "calle")

      assert found(ctx) == []
    end

    test "the building named after the sector is not the sector", ctx do
      sector = under(ctx, ctx.parroquia, "Caraballeda 1", "sector")
      under(ctx, sector, "Tanaguarena", "sector")
      under(ctx, ctx.parroquia, "Residencia Caraballeda 1", "edificio")

      assert found(ctx) == []
    end

    test "two places of one kind are still compared", ctx do
      under(ctx, ctx.parroquia, "La Costanera", "calle")
      under(ctx, ctx.parroquia, "Avenida La Costanera", "calle")

      assert pair?(found(ctx), "La Costanera", "Avenida La Costanera")
    end

    # An unknown label is a reason to ask, never a reason to stay quiet.
    test "a type nobody has classified suppresses nothing", ctx do
      under(ctx, ctx.parroquia, "La Costanera", "malecón")
      under(ctx, ctx.parroquia, "Avenida La Costanera", "paseo")

      assert pair?(found(ctx), "La Costanera", "Avenida La Costanera")
    end
  end

  describe "a Roman numeral counts as a number" do
    test "it tells two buildings apart", ctx do
      under(ctx, ctx.parroquia, "Residencias Caraballeda")
      under(ctx, ctx.parroquia, "Residencia Caraballeda I")

      assert found(ctx) == []
    end

    test "and the same number written both ways still matches", ctx do
      under(ctx, ctx.parroquia, "Torre II")
      under(ctx, ctx.parroquia, "Torres 2")

      assert pair?(found(ctx), "Torre II", "Torres 2")
    end

    test "a numeral is only a numeral as a whole word", ctx do
      under(ctx, ctx.parroquia, "Residencias Iris")
      under(ctx, ctx.parroquia, "Residencia Iris")

      assert pair?(found(ctx), "Residencias Iris", "Residencia Iris")
    end
  end

  describe "what it will not find" do
    # Honest limit, worth a failing-in-spirit test so nobody assumes coverage:
    # "ancianato" and "asilo" both mean an old people's home. No string measure
    # reaches that — a person or a model must.
    test "two different words for one thing are invisible to it", ctx do
      under(ctx, ctx.parroquia, "Ancianato de Caraballeda")
      under(ctx, ctx.parroquia, "asilo de Caraballeda")

      assert found(ctx) == []
    end

    test "a deprecated place is not offered — only the working vocabulary is", ctx do
      under(ctx, ctx.parroquia, "La Costanera", "calle")
      other = under(ctx, ctx.parroquia, "Avenida La Costanera", "calle")

      Wekui.Core.discard_place!(other, %{note: "not real"})

      assert found(ctx) == []
    end
  end
end
