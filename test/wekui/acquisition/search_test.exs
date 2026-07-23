defmodule Wekui.Acquisition.SearchTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Acquisition

  setup do
    %{event: event!(), other_event: event!()}
  end

  defp attrs(event, overrides \\ %{}) do
    Map.merge(
      %{
        event_id: event.id,
        name: "search-#{System.unique_integer([:positive])}",
        intent: "Collect what was said in the first hour",
        window_start: ~U[2026-06-24 22:00:00.000000Z],
        window_end: ~U[2026-06-24 23:00:00.000000Z]
      },
      overrides
    )
  end

  describe "create" do
    test "starts as a draft with ten-minute slices in latest mode", %{event: event} do
      search = search!(event)

      assert search.status == :draft
      assert search.slice_seconds == 600
      assert search.result_mode == :latest
      assert is_nil(search.started_at)
      assert is_nil(search.completed_at)
    end

    for field <- [:event_id, :name, :intent, :window_start] do
      test "requires #{field}", %{event: event} do
        assert {:error, %Ash.Error.Invalid{}} =
                 Acquisition.create_search(Map.delete(attrs(event), unquote(field)))
      end
    end

    test "an open window is allowed", %{event: event} do
      assert search!(event, %{window_end: nil}).window_end == nil
    end

    test "the window end must be after the window start", %{event: event} do
      assert {:error, error} =
               Acquisition.create_search(
                 attrs(event, %{window_end: ~U[2026-06-24 21:00:00.000000Z]})
               )

      assert error_on(error, :window_end) =~ "after the window start"
    end

    test "the slice length must be positive", %{event: event} do
      assert {:error, error} = Acquisition.create_search(attrs(event, %{slice_seconds: 0}))
      assert error_on(error, :slice_seconds) =~ "positive"
    end

    test "refuses a result mode outside latest and top", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} =
               Acquisition.create_search(attrs(event, %{result_mode: :trending}))
    end

    test "no two Searches of one Event share a name", %{event: event} do
      taken = attrs(event, %{name: "first-hour"})

      assert {:ok, _} = Acquisition.create_search(taken)
      assert {:error, %Ash.Error.Invalid{}} = Acquisition.create_search(taken)
    end

    test "two Events may each have a Search of the same name", %{
      event: event,
      other_event: other
    } do
      assert {:ok, _} = Acquisition.create_search(attrs(event, %{name: "first-hour"}))
      assert {:ok, _} = Acquisition.create_search(attrs(other, %{name: "first-hour"}))
    end

    test "takes a Scope of Places", %{event: event} do
      place = place!(event)
      search = search!(event, %{place_ids: [place.id]})

      {:ok, loaded} = Acquisition.get_search(search.id, load: [:places])
      assert Enum.map(loaded.places, & &1.id) == [place.id]
    end

    test "refuses a Scope reaching into another Event", %{event: event, other_event: other} do
      foreign = place!(other)

      assert {:error, error} = Acquisition.create_search(attrs(event, %{place_ids: [foreign.id]}))
      assert error_on(error, :place_ids) =~ "same event"
    end

    test "takes Terms", %{event: event} do
      search = search!(event, %{terms: [%{term: "derrumbe", lang: "es"}]})

      {:ok, terms} = Acquisition.list_search_terms(search.id)
      assert Enum.map(terms, & &1.term) == ["derrumbe"]
    end

    test "an empty Scope and no Terms is a base sweep over everything", %{event: event} do
      search = search!(event)

      {:ok, loaded} = Acquisition.get_search(search.id, load: [:places, :search_terms])
      assert loaded.places == []
      assert loaded.search_terms == []
    end
  end

  describe "lifecycle" do
    test "draft to ready to active, remembering when it started", %{event: event} do
      {:ok, ready} = event |> search!() |> Acquisition.freeze_search()
      assert ready.status == :ready

      {:ok, active} = Acquisition.activate_search(ready)
      assert active.status == :active
      refute is_nil(active.started_at)
    end

    test "pausing and resuming keeps the original start", %{event: event} do
      {:ok, active} =
        event |> search!() |> Acquisition.freeze_search!() |> Acquisition.activate_search()

      {:ok, paused} = Acquisition.pause_search(active)
      assert paused.status == :paused

      {:ok, resumed} = Acquisition.activate_search(paused)
      assert resumed.status == :active
      assert resumed.started_at == active.started_at
    end

    test "closing is final and remembers when", %{event: event} do
      {:ok, closed} = event |> search!() |> Acquisition.close_search()

      assert closed.status == :closed
      refute is_nil(closed.completed_at)
      assert {:error, %Ash.Error.Invalid{}} = Acquisition.close_search(closed)
      assert {:error, %Ash.Error.Invalid{}} = Acquisition.freeze_search(closed)
    end

    test "a draft cannot be activated without being approved first", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} = event |> search!() |> Acquisition.activate_search()
    end

    test "only an active Search can be paused", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} = event |> search!() |> Acquisition.pause_search()
    end

    test "every move can carry the sentence explaining it", %{event: event} do
      {:ok, ready} = event |> search!() |> Acquisition.freeze_search(%{note: "scope reviewed"})

      assert ready.status_note == "scope reviewed"
    end

    test "the note can also be set on its own", %{event: event} do
      {:ok, noted} = event |> search!() |> Acquisition.set_search_note(%{status_note: "waiting"})

      assert noted.status_note == "waiting"
    end
  end

  describe "editing" do
    test "a draft can be edited", %{event: event} do
      {:ok, edited} =
        event |> search!() |> Acquisition.update_search(%{intent: "Something else entirely"})

      assert edited.intent == "Something else entirely"
    end

    test "the Scope can be replaced while it is a draft", %{event: event} do
      first = place!(event)
      second = place!(event, %{canonical_name: "Macuto"})
      search = search!(event, %{place_ids: [first.id]})

      {:ok, edited} = Acquisition.update_search(search, %{place_ids: [second.id]})
      {:ok, loaded} = Acquisition.get_search(edited.id, load: [:places])

      assert Enum.map(loaded.places, & &1.id) == [second.id]
    end

    test "a Search that has left draft cannot be edited", %{event: event} do
      {:ok, ready} = event |> search!() |> Acquisition.freeze_search()

      assert {:error, error} = Acquisition.update_search(ready, %{intent: "too late"})
      assert error_on(error, :status) =~ "only a draft"
    end

    test "an edited Scope must still belong to the Event", %{event: event, other_event: other} do
      foreign = place!(other)
      search = search!(event)

      assert {:error, error} = Acquisition.update_search(search, %{place_ids: [foreign.id]})
      assert error_on(error, :place_ids) =~ "same event"
    end

    test "moving the window throws the plan away, so it is never frozen stale", %{event: event} do
      place!(event)
      search = event |> search!() |> Acquisition.decompose_search!()
      {:ok, before} = Acquisition.list_queries(search.id)
      assert before != []

      {:ok, edited} =
        Acquisition.update_search(search, %{window_end: ~U[2026-06-25 00:00:00.000000Z]})

      {:ok, after_edit} = Acquisition.list_queries(edited.id)
      assert after_edit == []

      # The plan is recoverable — a wider window rebuilds to more Queries.
      {:ok, redone} = Acquisition.decompose_search(edited)
      {:ok, rebuilt} = Acquisition.list_queries(redone.id)
      assert length(rebuilt) > length(before)
    end

    test "editing the intent alone leaves the plan standing", %{event: event} do
      place!(event)
      search = event |> search!() |> Acquisition.decompose_search!()
      {:ok, before} = Acquisition.list_queries(search.id)

      {:ok, edited} = Acquisition.update_search(search, %{intent: "Something else entirely"})

      {:ok, after_edit} = Acquisition.list_queries(edited.id)
      assert length(after_edit) == length(before)
    end
  end

  describe "reads" do
    test "by_event returns only that Event's Searches", %{event: event, other_event: other} do
      mine = search!(event)
      search!(other)

      {:ok, searches} = Acquisition.list_searches(event.id)

      assert Enum.map(searches, & &1.id) == [mine.id]
    end

    test "a Search loads its Event, Terms and Scope", %{event: event} do
      place = place!(event)
      search = search!(event, %{place_ids: [place.id], terms: [%{term: "derrumbe", lang: "es"}]})

      {:ok, loaded} =
        Acquisition.get_search(search.id, load: [:event, :places, :search_terms, :search_places])

      assert loaded.event.id == event.id
      assert length(loaded.places) == 1
      assert length(loaded.search_terms) == 1
      assert length(loaded.search_places) == 1
    end
  end
end
