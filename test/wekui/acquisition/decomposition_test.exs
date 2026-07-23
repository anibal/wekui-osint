defmodule Wekui.Acquisition.DecompositionTest do
  use ExUnit.Case, async: true

  alias Wekui.Acquisition.Decomposition

  @start ~U[2026-06-24 22:00:00.000000Z]
  @cap 22

  defp name(id, string, emission), do: %{id: id, name: string, emission: emission}

  defp place(id, type, names), do: %{id: id, type: type, place_names: names}

  defp term(id, string), do: %{id: id, term: string}

  describe "tile/4 with a closed window" do
    test "cuts the window into whole slices" do
      window_end = DateTime.add(@start, 1800, :second)

      assert Decomposition.tile(@start, window_end, 600, @start) == [
               {@start, DateTime.add(@start, 600, :second)},
               {DateTime.add(@start, 600, :second), DateTime.add(@start, 1200, :second)},
               {DateTime.add(@start, 1200, :second), window_end}
             ]
    end

    test "slices stay whole, so the last one may reach past the window end" do
      window_end = DateTime.add(@start, 1500, :second)
      slices = Decomposition.tile(@start, window_end, 600, @start)

      assert length(slices) == 3

      assert List.last(slices) ==
               {DateTime.add(@start, 1200, :second), DateTime.add(@start, 1800, :second)}
    end

    test "the grid never moves, so pushing the end out only appends" do
      shorter = Decomposition.tile(@start, DateTime.add(@start, 1500, :second), 600, @start)
      longer = Decomposition.tile(@start, DateTime.add(@start, 2700, :second), 600, @start)

      assert Enum.take(longer, length(shorter)) == shorter
    end

    test "slices are half-open and touch exactly, so nothing is counted twice" do
      window_end = DateTime.add(@start, 1800, :second)
      slices = Decomposition.tile(@start, window_end, 600, @start)

      slices
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [{_, first_end}, {second_start, _}] ->
        assert first_end == second_start
      end)
    end

    test "an empty or backwards window yields nothing" do
      assert Decomposition.tile(@start, @start, 600, @start) == []
      assert Decomposition.tile(@start, DateTime.add(@start, -600, :second), 600, @start) == []
    end
  end

  describe "tile/4 with an open window" do
    test "cuts up to now, truncated to the slice grid" do
      now = DateTime.add(@start, 1500, :second)
      slices = Decomposition.tile(@start, nil, 600, now)

      assert length(slices) == 2

      assert List.last(slices) ==
               {DateTime.add(@start, 600, :second), DateTime.add(@start, 1200, :second)}
    end

    test "leaves the ragged tail alone — a slice still filling up is never asked about" do
      now = DateTime.add(@start, 599, :second)

      assert Decomposition.tile(@start, nil, 600, now) == []
    end
  end

  describe "place_specs/6" do
    setup do
      slices = [{@start, DateTime.add(@start, 600, :second)}]
      %{slices: slices}
    end

    test "one spec per raw-name group per slice", %{slices: slices} do
      place = place("p1", "parroquia", [name("n1", "Caraballeda", :raw)])

      assert [spec] = Decomposition.place_specs(place, [], [], slices, :latest, @cap)
      assert spec.place_id == "p1"
      assert spec.place_name_ids == ["n1"]
      assert spec.slice_start == @start
      assert spec.query_text =~ "Caraballeda"
    end

    test "raw names batch into one group", %{slices: slices} do
      place =
        place("p1", "parroquia", [
          name("n1", "Caraballeda", :raw),
          name("n2", "Tanaguarena", :raw)
        ])

      assert [spec] = Decomposition.place_specs(place, [], [], slices, :latest, @cap)
      assert spec.query_text =~ "(Caraballeda OR Tanaguarena)"
      assert Enum.sort(spec.place_name_ids) == ["n1", "n2"]
    end

    test "recognition-only names are never emitted", %{slices: slices} do
      place = place("p1", "parroquia", [name("n1", "Caraballeda", :recognition_only)])

      assert Decomposition.place_specs(place, [], [], slices, :latest, @cap) == []
    end

    test "an anchored name gets its own group, qualified by its ancestors", %{slices: slices} do
      place = place("p1", "edificio", [name("n1", "Palmar", :anchored)])
      parish = place("p2", "parroquia", [name("n2", "Caraballeda", :raw)])

      assert [spec] = Decomposition.place_specs(place, [parish], [], slices, :latest, @cap)
      assert spec.query_text =~ "Palmar Caraballeda"
      assert spec.place_name_ids == ["n1"]
    end

    test "an anchored name with no qualifiers emits nothing rather than emitting bare", %{
      slices: slices
    } do
      place = place("p1", "edificio", [name("n1", "Palmar", :anchored)])

      assert Decomposition.place_specs(place, [], [], slices, :latest, @cap) == []
    end

    test "country names never qualify — they would match almost anything", %{slices: slices} do
      place = place("p1", "edificio", [name("n1", "Palmar", :anchored)])
      country = place("p2", "pais", [name("n2", "Venezuela", :raw)])

      assert Decomposition.place_specs(place, [country], [], slices, :latest, @cap) == []
    end

    test "terms ride in every group and are credited", %{slices: slices} do
      place = place("p1", "parroquia", [name("n1", "Caraballeda", :raw)])
      terms = [term("t1", "derrumbe")]

      assert [spec] = Decomposition.place_specs(place, [], terms, slices, :latest, @cap)
      assert spec.query_text =~ "derrumbe"
      assert spec.search_term_ids == ["t1"]
    end

    test "names split across several groups rather than being dropped", %{slices: slices} do
      names = for i <- 1..20, do: name("n#{i}", "Name#{String.pad_leading("#{i}", 2, "0")}", :raw)
      place = place("p1", "parroquia", names)

      specs = Decomposition.place_specs(place, [], [], slices, :latest, @cap)

      assert length(specs) > 1
      # every name is carried by exactly one group, none silently lost
      assert specs |> Enum.flat_map(& &1.place_name_ids) |> Enum.sort() ==
               names |> Enum.map(& &1.id) |> Enum.sort()
    end

    test "every emitted group stays within the cap", %{slices: slices} do
      names = for i <- 1..20, do: name("n#{i}", "Name#{String.pad_leading("#{i}", 2, "0")}", :raw)
      place = place("p1", "parroquia", names)
      terms = [term("t1", "derrumbe"), term("t2", "damnificados")]

      for spec <- Decomposition.place_specs(place, [], terms, slices, :latest, @cap) do
        assert Wekui.Acquisition.QueryText.operator_count(spec.query_text) <= @cap
      end
    end

    test "two names spelled identically share a group but both stay credited", %{slices: slices} do
      place =
        place("p1", "parroquia", [
          name("n1", "Caraballeda", :raw),
          name("n2", "Caraballeda", :raw)
        ])

      assert [spec] = Decomposition.place_specs(place, [], [], slices, :latest, @cap)
      refute spec.query_text =~ "OR"
      assert Enum.sort(spec.place_name_ids) == ["n1", "n2"]
    end

    test "groups are crossed with every slice" do
      slices = [
        {@start, DateTime.add(@start, 600, :second)},
        {DateTime.add(@start, 600, :second), DateTime.add(@start, 1200, :second)}
      ]

      place = place("p1", "parroquia", [name("n1", "Caraballeda", :raw)])
      specs = Decomposition.place_specs(place, [], [], slices, :latest, @cap)

      assert length(specs) == 2
      assert specs |> Enum.map(& &1.query_text) |> Enum.uniq() |> length() == 2
    end

    test "the same place always produces the same specs", %{slices: slices} do
      place =
        place("p1", "parroquia", [
          name("n2", "Tanaguarena", :raw),
          name("n1", "Caraballeda", :raw)
        ])

      assert Decomposition.place_specs(place, [], [], slices, :latest, @cap) ==
               Decomposition.place_specs(place, [], [], slices, :latest, @cap)
    end
  end
end
