defmodule Wekui.Acquisition.DecomposeTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Acquisition
  alias Wekui.Core

  # 22:00 to 23:00 in ten-minute slices is six slices.
  @slices 6

  setup do
    %{event: event!()}
  end

  defp query_texts(search) do
    {:ok, queries} = Acquisition.list_queries(search.id)
    Enum.map(queries, & &1.query_text)
  end

  describe "decompose" do
    test "asks one question per Place per slice", %{event: event} do
      place!(event)
      search = event |> search!() |> Acquisition.decompose_search!()

      {:ok, queries} = Acquisition.list_queries(search.id)

      assert length(queries) == @slices
      assert Enum.all?(queries, &(&1.query_text =~ "Caraballeda"))
    end

    test "the slices tile the window without gaps or overlaps", %{event: event} do
      place!(event)
      search = event |> search!() |> Acquisition.decompose_search!()

      {:ok, queries} = Acquisition.list_queries(search.id)

      assert List.first(queries).slice_start == ~U[2026-06-24 22:00:00.000000Z]
      assert List.last(queries).slice_end == ~U[2026-06-24 23:00:00.000000Z]

      queries
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [earlier, later] -> assert earlier.slice_end == later.slice_start end)
    end

    test "credits the Place Names each question emitted", %{event: event} do
      place!(event, %{names: [{"Caraballeda", :raw}, {"Tanaguarena", :raw}]})
      search = event |> search!() |> Acquisition.decompose_search!()

      {:ok, [query | _]} = Acquisition.list_queries(search.id)
      {:ok, names} = Acquisition.list_query_names(query.id)

      assert query.query_text =~ "(Caraballeda OR Tanaguarena)"
      assert length(names) == 2
    end

    test "credits the Terms each question carried", %{event: event} do
      place!(event)

      search =
        event
        |> search!(%{terms: [%{term: "derrumbe", lang: "es"}]})
        |> Acquisition.decompose_search!()

      {:ok, [query | _]} = Acquisition.list_queries(search.id)
      {:ok, terms} = Acquisition.list_query_terms(query.id)

      assert query.query_text =~ "derrumbe"
      assert length(terms) == 1
    end

    test "an empty Scope sweeps every active Place", %{event: event} do
      place!(event)
      place!(event, %{canonical_name: "Macuto"})

      search = event |> search!() |> Acquisition.decompose_search!()

      assert length(query_texts(search)) == 2 * @slices
    end

    test "an explicit Scope sweeps only what it names", %{event: event} do
      only = place!(event)
      place!(event, %{canonical_name: "Macuto"})

      search =
        event |> search!(%{place_ids: [only.id]}) |> Acquisition.decompose_search!()

      assert length(query_texts(search)) == @slices
      assert Enum.all?(query_texts(search), &(&1 =~ "Caraballeda"))
    end

    test "a Place that is not active is never swept", %{event: event} do
      place!(event, %{lifecycle: :proposed})

      search = event |> search!() |> Acquisition.decompose_search!()

      assert query_texts(search) == []
    end

    test "the Unplaced Place is never swept, even carrying an emittable name", %{event: event} do
      place!(event)

      Core.create_place_name!(%{
        place_id: event.unplaced_place_id,
        name: "Unplaced",
        kind: :official,
        emission: :raw
      })

      search = event |> search!() |> Acquisition.decompose_search!()

      # It is excluded because the Event points at it, not because of anything
      # about its name or its Type.
      refute Enum.any?(query_texts(search), &(&1 =~ "Unplaced"))
      assert length(query_texts(search)) == @slices
    end

    test "naming a proposed Place explicitly collects on it", %{event: event} do
      proposed = place!(event, %{lifecycle: :proposed, canonical_name: "Palmar"})

      search =
        event |> search!(%{place_ids: [proposed.id]}) |> Acquisition.decompose_search!()

      assert length(query_texts(search)) == @slices
      assert Enum.all?(query_texts(search), &(&1 =~ "Palmar"))
    end

    test "an empty Scope leaves proposed Places alone", %{event: event} do
      place!(event)
      place!(event, %{lifecycle: :proposed, canonical_name: "Palmar"})

      search = event |> search!() |> Acquisition.decompose_search!()

      assert length(query_texts(search)) == @slices
      refute Enum.any?(query_texts(search), &(&1 =~ "Palmar"))
    end

    test "a deprecated or discarded Place is never swept, even when named", %{event: event} do
      retired = place!(event, %{canonical_name: "Palmar"})
      replacement = place!(event, %{canonical_name: "Macuto"})
      {:ok, retired} = Core.deprecate_place(retired, %{replaced_by_id: replacement.id})

      search =
        event |> search!(%{place_ids: [retired.id]}) |> Acquisition.decompose_search!()

      assert query_texts(search) == []
    end

    test "an anchored name is qualified by its ancestors", %{event: event} do
      parish = place!(event, %{canonical_name: "Caraballeda"})

      place!(event, %{
        type: "edificio",
        canonical_name: "Palmar",
        parent_id: parish.id,
        names: [{"Palmar", :anchored}]
      })

      search = event |> search!() |> Acquisition.decompose_search!()

      assert Enum.any?(query_texts(search), &(&1 =~ "Palmar Caraballeda"))
    end

    test "the mode is written into every question and readable back", %{event: event} do
      place!(event)
      search = event |> search!(%{result_mode: :top}) |> Acquisition.decompose_search!()

      {:ok, [query | _]} = Acquisition.list_queries(search.id, load: [:result_mode])

      assert query.query_text =~ "queryType=Top"
      assert query.result_mode == :top
    end

    test "an open window is cut up to the moment given", %{event: event} do
      place!(event)

      search =
        event
        |> search!(%{window_end: nil})
        |> Acquisition.decompose_search!(%{now: ~U[2026-06-24 22:30:00.000000Z]})

      assert length(query_texts(search)) == 3
    end

    test "working it out again produces exactly the same plan", %{event: event} do
      place!(event)
      search = event |> search!() |> Acquisition.decompose_search!()
      first = query_texts(search)

      search = Acquisition.decompose_search!(search)

      assert query_texts(search) == first
    end

    test "the plan is thrown away and rebuilt, not appended to", %{event: event} do
      place = place!(event)
      search = event |> search!() |> Acquisition.decompose_search!()
      assert length(query_texts(search)) == @slices

      {:ok, _} = Core.discard_place(place, %{note: "not a real place"})
      search = Acquisition.decompose_search!(search)

      assert query_texts(search) == []
    end

    test "only a draft's plan can be worked out again", %{event: event} do
      place!(event)
      {:ok, ready} = event |> search!() |> Acquisition.freeze_search()

      assert {:error, error} = Acquisition.decompose_search(ready)
      assert error_on(error, :status) =~ "only a draft"
    end

    test "editing a draft's Scope throws its plan away", %{event: event} do
      place = place!(event)
      search = event |> search!(%{place_ids: [place.id]}) |> Acquisition.decompose_search!()
      assert length(query_texts(search)) == @slices

      {:ok, edited} = Acquisition.update_search(search, %{place_ids: []})

      assert query_texts(edited) == []
    end

    test "editing only the intent leaves the plan standing", %{event: event} do
      place!(event)
      search = event |> search!() |> Acquisition.decompose_search!()

      {:ok, edited} = Acquisition.update_search(search, %{intent: "Reworded, same plan"})

      assert length(query_texts(edited)) == @slices
    end
  end

  describe "extending" do
    setup %{event: event} do
      place!(event)

      search =
        event |> search!() |> Acquisition.decompose_search!() |> Acquisition.freeze_search!()

      %{search: search, before: query_texts(search)}
    end

    test "adding a Place adds its questions and touches nothing else", %{
      event: event,
      search: search,
      before: before
    } do
      added = place!(event, %{canonical_name: "Macuto"})

      {:ok, extended} = Acquisition.extend_search_with_place(search, %{place_id: added.id})
      texts = query_texts(extended)

      assert length(texts) == length(before) + @slices
      assert Enum.all?(before, &(&1 in texts))
      assert Enum.any?(texts, &(&1 =~ "Macuto"))
    end

    test "adding a Term adds the questions carrying it", %{search: search, before: before} do
      {:ok, extended} =
        Acquisition.extend_search_with_term(search, %{term: %{term: "derrumbe", lang: "es"}})

      texts = query_texts(extended)

      assert length(texts) == length(before) + @slices
      assert Enum.all?(before, &(&1 in texts))
      assert Enum.any?(texts, &(&1 =~ "derrumbe"))
    end

    test "pushing the window out adds only the new slices", %{search: search, before: before} do
      {:ok, extended} =
        Acquisition.extend_search_window(search, %{window_end: ~U[2026-06-24 23:30:00.000000Z]})

      texts = query_texts(extended)

      assert length(texts) == length(before) + 3
      assert Enum.all?(before, &(&1 in texts))
    end

    test "a window that is not a whole number of slices long still never overlaps", %{
      event: event
    } do
      # 22:00 to 22:25 is two and a half slices. Push it out to 22:45 and the
      # stretch around 22:20 must be asked about once, not twice.
      search =
        event
        |> search!(%{window_end: ~U[2026-06-24 22:25:00.000000Z]})
        |> Acquisition.decompose_search!()
        |> Acquisition.freeze_search!()

      {:ok, extended} =
        Acquisition.extend_search_window(search, %{window_end: ~U[2026-06-24 22:45:00.000000Z]})

      {:ok, queries} = Acquisition.list_queries(extended.id)

      queries
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [earlier, later] -> assert earlier.slice_end == later.slice_start end)
    end

    test "the window can only be pushed out, never pulled in", %{search: search} do
      assert {:error, error} =
               Acquisition.extend_search_window(search, %{
                 window_end: ~U[2026-06-24 22:30:00.000000Z]
               })

      assert error_on(error, :window_end) =~ "further out"
    end

    test "extending refuses a Search whose Scope reaches another Event", %{search: search} do
      foreign = place!(event!())

      assert {:error, error} =
               Acquisition.extend_search_with_place(search, %{place_id: foreign.id})

      assert error_on(error, :place_id) =~ "same event"
    end

    test "a draft is edited and worked out again, not extended", %{event: event} do
      draft = search!(event)
      added = place!(event, %{canonical_name: "Macuto"})

      assert {:error, error} = Acquisition.extend_search_with_place(draft, %{place_id: added.id})
      assert error_on(error, :status) =~ "not extended"
    end

    test "a closed Search is finished", %{event: event, search: search} do
      {:ok, closed} = Acquisition.close_search(search)
      added = place!(event, %{canonical_name: "Macuto"})

      assert {:error, error} = Acquisition.extend_search_with_place(closed, %{place_id: added.id})
      assert error_on(error, :status) =~ "finished"
    end

    test "an active Search can still grow", %{event: event, search: search, before: before} do
      {:ok, active} = Acquisition.activate_search(search)
      added = place!(event, %{canonical_name: "Macuto"})

      {:ok, extended} = Acquisition.extend_search_with_place(active, %{place_id: added.id})

      assert length(query_texts(extended)) == length(before) + @slices
      assert extended.status == :active
    end
  end
end
