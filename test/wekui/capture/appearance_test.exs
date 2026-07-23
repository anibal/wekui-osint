defmodule Wekui.Capture.AppearanceTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Acquisition
  alias Wekui.Capture

  setup do
    event = event!()
    place!(event)
    search = active_search!(event)
    {:ok, queries} = Acquisition.list_queries(search.id)

    %{event: event, queries: queries, query: hd(queries), other_event: event!()}
  end

  describe "record" do
    test "records that a Query found a Post, belonging to both", %{event: event, query: query} do
      post = post!(event)

      appearance = appearance!(post, query)

      assert appearance.post_id == post.id
      assert appearance.query_id == query.id
    end

    for field <- [:post_id, :query_id] do
      test "requires #{field}", %{event: event, query: query} do
        post = post!(event)
        attrs = Map.delete(%{post_id: post.id, query_id: query.id}, unquote(field))

        assert {:error, %Ash.Error.Invalid{}} = Capture.record_appearance(attrs)
      end
    end
  end

  describe "identity" do
    test "one Query never records the same Post twice", %{event: event, query: query} do
      post = post!(event)

      first = appearance!(post, query)
      second = appearance!(post, query)

      assert second.id == first.id
      assert {:ok, [only]} = Capture.list_appearances_by_query(query.id)
      assert only.id == first.id
      assert {:ok, [_one]} = Capture.list_appearances_by_post(post.id)
    end
  end

  describe "many findings" do
    test "a Post may be found by several different Queries", %{event: event, queries: queries} do
      post = post!(event)
      finders = Enum.take(queries, 3)

      for query <- finders, do: appearance!(post, query)

      {:ok, appearances} = Capture.list_appearances_by_post(post.id)
      assert length(appearances) == 3
    end

    test "a Query may find several different Posts", %{event: event, query: query} do
      posts = for _ <- 1..3, do: post!(event)

      for post <- posts, do: appearance!(post, query)

      {:ok, appearances} = Capture.list_appearances_by_query(query.id)
      assert length(appearances) == 3
    end
  end

  describe "belonging to one Event" do
    test "a Post from another Event is rejected", %{query: query, other_event: other} do
      stranger = post!(other)

      assert {:error, error} =
               Capture.record_appearance(%{post_id: stranger.id, query_id: query.id})

      assert Exception.message(error) =~ "same event"
    end
  end
end
