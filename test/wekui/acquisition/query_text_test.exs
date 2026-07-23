defmodule Wekui.Acquisition.QueryTextTest do
  use ExUnit.Case, async: true

  alias Wekui.Acquisition.QueryText

  @since ~U[2026-06-24 22:00:00.000000Z]
  @until ~U[2026-06-24 22:10:00.000000Z]

  defp render(overrides) do
    QueryText.render(
      Map.merge(
        %{
          location: {:raw, ["Caraballeda"]},
          terms: [],
          since: @since,
          until: @until,
          mode: :latest
        },
        overrides
      )
    )
  end

  describe "render/1" do
    test "a lone name is not parenthesised — one member is no group" do
      assert render(%{}) =~ ~r/^Caraballeda since_time:/
    end

    test "two or more names become a parenthesised OR group" do
      text = render(%{location: {:raw, ["Caraballeda", "Tanaguarena"]}})

      assert text =~ "(Caraballeda OR Tanaguarena)"
    end

    test "members containing whitespace are quoted" do
      assert render(%{location: {:raw, ["La Guaira", "Macuto"]}}) =~ ~s|("La Guaira" OR Macuto)|
    end

    test "an anchored name sits next to its qualifiers" do
      text = render(%{location: {:anchored, "Palmar", ["Caraballeda", "La Guaira"]}})

      assert text =~ ~s|Palmar (Caraballeda OR "La Guaira")|
    end

    test "terms ride as a second group" do
      assert render(%{terms: ["derrumbe", "damnificados"]}) =~ "(derrumbe OR damnificados)"
    end

    test "a base sweep has no event group at all" do
      refute render(%{}) =~ "()"

      assert render(%{}) ==
               "Caraballeda since_time:1782338400 until_time:1782339000 queryType=Latest"
    end

    test "the slice is written as epoch seconds" do
      text = render(%{})

      assert text =~ "since_time:#{DateTime.to_unix(@since)}"
      assert text =~ "until_time:#{DateTime.to_unix(@until)}"
    end

    test "the mode rides at the end" do
      assert String.ends_with?(render(%{mode: :latest}), " queryType=Latest")
      assert String.ends_with?(render(%{mode: :top}), " queryType=Top")
    end

    test "the same coordinates always produce the same characters" do
      coordinates = %{location: {:raw, ["Caraballeda", "Tanaguarena"]}, terms: ["derrumbe"]}

      assert render(coordinates) == render(coordinates)
    end
  end

  describe "result_mode_of/1" do
    test "reads the mode back out of the text" do
      assert QueryText.result_mode_of(render(%{mode: :latest})) == :latest
      assert QueryText.result_mode_of(render(%{mode: :top})) == :top
    end

    test "is nil when the text carries no recognisable mode" do
      assert QueryText.result_mode_of("Caraballeda since_time:1 until_time:2") == nil
    end
  end

  describe "decode/1" do
    test "splits the text back into what a runner sends" do
      assert %{
               query: query,
               result_mode: :latest,
               since_time: since,
               until_time: until_
             } = QueryText.decode(render(%{}))

      refute query =~ "queryType"
      assert since == DateTime.to_unix(@since)
      assert until_ == DateTime.to_unix(@until)
    end

    test "round-trips every rendered text" do
      for mode <- [:latest, :top] do
        text =
          render(%{location: {:raw, ["La Guaira", "Macuto"]}, terms: ["derrumbe"], mode: mode})

        decoded = QueryText.decode(text)

        assert decoded.query <> " queryType=#{if mode == :latest, do: "Latest", else: "Top"}" ==
                 text

        assert decoded.result_mode == mode
      end
    end
  end

  describe "operator_count/1" do
    test "counts words, ORs and both slice bounds, but not parentheses" do
      # (Caraballeda OR Tanaguarena) since_time: until_time: => 2 names + 1 OR + 2 bounds
      assert QueryText.operator_count(render(%{location: {:raw, ["Caraballeda", "Tanaguarena"]}})) ==
               5
    end

    test "a quoted phrase counts once, however many words it holds" do
      assert QueryText.operator_count(render(%{location: {:raw, ["La Guaira"]}})) == 3
    end

    test "the mode suffix is never counted — it is not part of the question" do
      assert QueryText.operator_count(render(%{mode: :latest})) ==
               QueryText.operator_count(render(%{mode: :top}))
    end
  end

  describe "token/1" do
    test "quotes only what contains whitespace" do
      assert QueryText.token("Macuto") == "Macuto"
      assert QueryText.token("La Guaira") == ~s("La Guaira")
    end
  end
end
