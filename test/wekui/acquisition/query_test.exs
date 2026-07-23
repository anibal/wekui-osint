defmodule Wekui.Acquisition.QueryTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Acquisition

  setup do
    event = event!()
    place!(event)

    %{event: event}
  end

  defp first_query(search) do
    {:ok, [query | _]} = Acquisition.list_queries(search.id)
    query
  end

  defp state(query) do
    {:ok, loaded} = Acquisition.get_query(query.id, load: [:state])
    loaded.state
  end

  describe "state" do
    test "a draft's Queries are proposals, not questions we mean to ask", %{event: event} do
      search = event |> search!() |> Acquisition.decompose_search!()

      assert state(first_query(search)) == :in_plan_review
    end

    test "once the plan is approved they are queued", %{event: event} do
      search =
        event |> search!() |> Acquisition.decompose_search!() |> Acquisition.freeze_search!()

      assert state(first_query(search)) == :queued
    end

    test "starting one makes it running", %{event: event} do
      query = event |> active_search!() |> first_query()

      {:ok, started} = Acquisition.start_query(query)

      refute is_nil(started.started_at)
      assert state(started) == :running_or_interrupted
    end

    test "completing one settles it", %{event: event} do
      query = event |> active_search!() |> first_query()

      {:ok, _} = Acquisition.start_query(query)
      {:ok, completed} = Acquisition.complete_query(query, %{posts_found: 12, posts_new: 9})

      assert completed.posts_found == 12
      assert completed.posts_new == 9
      assert state(completed) == :completed
    end

    test "discarding one settles it too, and says why", %{event: event} do
      query = event |> active_search!() |> first_query()

      {:ok, discarded} = Acquisition.discard_query(query, %{note: "X returned nothing usable"})

      assert discarded.status_note == "X returned nothing usable"
      assert state(discarded) == :discarded
    end

    test "discarding wins over having been started", %{event: event} do
      query = event |> active_search!() |> first_query()

      {:ok, started} = Acquisition.start_query(query)
      {:ok, discarded} = Acquisition.discard_query(started, %{note: "gave up"})

      assert state(discarded) == :discarded
    end
  end

  describe "asking" do
    setup %{event: event} do
      %{query: event |> active_search!() |> first_query()}
    end

    test "starting twice does not restart the clock", %{query: query} do
      {:ok, first} = Acquisition.start_query(query)
      {:ok, again} = Acquisition.start_query(first)

      assert again.started_at == first.started_at
    end

    test "counts are absent until somebody counts — never zero by default", %{query: query} do
      assert is_nil(query.posts_found)
      assert is_nil(query.posts_new)

      {:ok, completed} = Acquisition.complete_query(query, %{})

      assert is_nil(completed.posts_found)
      refute is_nil(completed.completed_at)
    end

    test "a completed Query is settled and never reopened", %{query: query} do
      {:ok, completed} = Acquisition.complete_query(query, %{posts_found: 1, posts_new: 1})

      assert {:error, %Ash.Error.Invalid{}} = Acquisition.start_query(completed)
      assert {:error, %Ash.Error.Invalid{}} = Acquisition.complete_query(completed, %{})

      assert {:error, %Ash.Error.Invalid{}} =
               Acquisition.discard_query(completed, %{note: "no"})
    end

    test "a discarded Query is settled and never reopened", %{query: query} do
      {:ok, discarded} = Acquisition.discard_query(query, %{note: "gave up"})

      assert {:error, %Ash.Error.Invalid{}} = Acquisition.start_query(discarded)
      assert {:error, %Ash.Error.Invalid{}} = Acquisition.complete_query(discarded, %{})
    end

    test "discarding demands a reason", %{query: query} do
      assert {:error, %Ash.Error.Invalid{}} = Acquisition.discard_query(query, %{})
      assert {:error, %Ash.Error.Invalid{}} = Acquisition.discard_query(query, %{note: "  "})
    end

    test "counts cannot be negative", %{query: query} do
      assert {:error, %Ash.Error.Invalid{}} =
               Acquisition.complete_query(query, %{posts_found: -1, posts_new: 0})
    end
  end

  describe "runnable" do
    test "an active Search offers everything not yet settled", %{event: event} do
      search = active_search!(event)
      {:ok, all} = Acquisition.list_queries(search.id)

      {:ok, runnable} = Acquisition.list_runnable_queries(search.id)
      assert length(runnable) == length(all)

      {:ok, _} = Acquisition.complete_query(hd(all), %{})
      {:ok, _} = Acquisition.discard_query(Enum.at(all, 1), %{note: "gave up"})

      {:ok, runnable} = Acquisition.list_runnable_queries(search.id)
      assert length(runnable) == length(all) - 2
    end

    test "a Search that is not active offers none of them", %{event: event} do
      draft = event |> search!() |> Acquisition.decompose_search!()
      assert {:ok, []} = Acquisition.list_runnable_queries(draft.id)

      {:ok, ready} = Acquisition.freeze_search(draft)
      assert {:ok, []} = Acquisition.list_runnable_queries(ready.id)

      {:ok, active} = Acquisition.activate_search(ready)
      {:ok, runnable} = Acquisition.list_runnable_queries(active.id)
      refute runnable == []

      {:ok, paused} = Acquisition.pause_search(active)
      assert {:ok, []} = Acquisition.list_runnable_queries(paused.id)
    end
  end

  describe "coverage" do
    test "only a finished latest-mode Query covers its slice", %{event: event} do
      search = active_search!(event)
      {:ok, [first, second | _]} = Acquisition.list_queries(search.id)

      assert {:ok, []} = Acquisition.list_covering_queries(search.id)

      {:ok, _} = Acquisition.complete_query(first, %{posts_found: 3, posts_new: 3})
      {:ok, covering} = Acquisition.list_covering_queries(search.id)
      assert Enum.map(covering, & &1.id) == [first.id]

      {:ok, _} = Acquisition.discard_query(second, %{note: "gave up"})
      {:ok, covering} = Acquisition.list_covering_queries(search.id)
      assert Enum.map(covering, & &1.id) == [first.id]
    end

    test "a top-mode Query covers nothing, however complete it is", %{event: event} do
      search = active_search!(event, %{result_mode: :top})
      {:ok, queries} = Acquisition.list_queries(search.id)

      for query <- queries, do: {:ok, _} = Acquisition.complete_query(query, %{posts_found: 5})

      assert {:ok, []} = Acquisition.list_covering_queries(search.id)
    end
  end

  describe "identity" do
    test "a Search never asks the same question twice", %{event: event} do
      query = event |> search!() |> Acquisition.decompose_search!() |> first_query()

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(Acquisition.Query, %{
                 search_id: query.search_id,
                 place_id: query.place_id,
                 query_text: query.query_text,
                 slice_start: query.slice_start,
                 slice_end: query.slice_end
               })
    end

    test "two Places sharing a name ask the question once", %{event: event} do
      # A second Place carrying the identical name would render the identical
      # request; the Search asks it once rather than twice.
      place!(event, %{canonical_name: "Caraballeda", type: "municipio"})

      search = event |> search!() |> Acquisition.decompose_search!()
      {:ok, queries} = Acquisition.list_queries(search.id)

      assert length(queries) == length(Enum.uniq_by(queries, & &1.query_text))
    end
  end

  describe "asking only while the Search is collecting" do
    test "a draft's Query cannot be started — its questions are not yet real", %{event: event} do
      query = event |> search!() |> Acquisition.decompose_search!() |> first_query()

      assert {:error, error} = Acquisition.start_query(query)
      assert Exception.message(error) =~ "must be active"
    end

    test "a ready Search's Query cannot be started until it is active", %{event: event} do
      query =
        event
        |> search!()
        |> Acquisition.decompose_search!()
        |> Acquisition.freeze_search!()
        |> first_query()

      assert {:error, error} = Acquisition.start_query(query)
      assert Exception.message(error) =~ "must be active"
    end

    test "an active Search's Query can be started", %{event: event} do
      query = event |> active_search!() |> first_query()

      assert {:ok, started} = Acquisition.start_query(query)
      refute is_nil(started.started_at)
    end

    test "a Query running when the Search is paused can still be completed", %{event: event} do
      search = active_search!(event)
      query = first_query(search)
      {:ok, _} = Acquisition.start_query(query)
      {:ok, _} = Acquisition.pause_search(search)

      assert {:ok, completed} = Acquisition.complete_query(query, %{posts_found: 3, posts_new: 2})
      assert completed.posts_found == 3
    end

    test "a paused Search's Query can be discarded", %{event: event} do
      search = active_search!(event)
      query = first_query(search)
      {:ok, _} = Acquisition.pause_search(search)

      assert {:ok, discarded} = Acquisition.discard_query(query, %{note: "no longer needed"})
      refute is_nil(discarded.discarded_at)
    end

    test "a closed Search's Query cannot be completed — closed is final", %{event: event} do
      search = active_search!(event)
      query = first_query(search)
      {:ok, _} = Acquisition.close_search(search)

      assert {:error, error} = Acquisition.complete_query(query, %{posts_found: 1, posts_new: 1})
      assert Exception.message(error) =~ "must be active or paused"
    end
  end
end
