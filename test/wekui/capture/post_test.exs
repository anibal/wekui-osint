defmodule Wekui.Capture.PostTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Capture

  setup do
    event = event!()

    %{event: event, author: author!(event), other_event: event!()}
  end

  describe "collect" do
    test "collects a Post that belongs to its Event and its Author", %{
      event: event,
      author: author
    } do
      post =
        post!(event, %{
          author: author,
          x_id: "p42",
          text: "temblor sentido en la guaira",
          posted_at: ~U[2026-06-24 22:05:00.000000Z],
          payload: %{"id" => "p42", "text" => "temblor sentido en la guaira"}
        })

      assert post.event_id == event.id
      assert post.author_id == author.id
      assert post.x_id == "p42"
      assert post.text == "temblor sentido en la guaira"
      assert post.posted_at == ~U[2026-06-24 22:05:00.000000Z]
      assert post.payload == %{"id" => "p42", "text" => "temblor sentido en la guaira"}

      {:ok, loaded} = Capture.get_post(post.id, load: [:event, :author])
      assert loaded.event.id == event.id
      assert loaded.author.id == author.id
    end

    test "every Post has an Author — collecting without one fails", %{event: event} do
      attrs = %{
        event_id: event.id,
        x_id: "p1",
        text: "hola",
        posted_at: ~U[2026-06-24 22:05:00.000000Z],
        payload: %{"id" => "p1"}
      }

      assert {:error, %Ash.Error.Invalid{}} = Capture.collect_post(attrs)
    end

    for field <- [:event_id, :x_id, :text, :posted_at, :payload] do
      test "requires #{field}", %{event: event, author: author} do
        attrs =
          Map.delete(
            %{
              event_id: event.id,
              author_id: author.id,
              x_id: "p1",
              text: "hola",
              posted_at: ~U[2026-06-24 22:05:00.000000Z],
              payload: %{"id" => "p1"}
            },
            unquote(field)
          )

        assert {:error, %Ash.Error.Invalid{}} = Capture.collect_post(attrs)
      end
    end
  end

  describe "belonging to one Event" do
    test "an Author from another Event is rejected", %{event: event, other_event: other} do
      stranger = author!(other)

      assert {:error, error} =
               Capture.collect_post(%{
                 event_id: event.id,
                 author_id: stranger.id,
                 x_id: "p9",
                 text: "hola",
                 posted_at: ~U[2026-06-24 22:05:00.000000Z],
                 payload: %{"id" => "p9"}
               })

      assert error_on(error, :author_id) =~ "same event"
    end
  end

  describe "identity" do
    test "re-collecting the same message returns the one we already hold, id populated", %{
      event: event,
      author: author
    } do
      first = post!(event, %{author: author, x_id: "p1"})
      second = post!(event, %{author: author, x_id: "p1"})

      assert second.id == first.id
      refute is_nil(second.id)
      assert {:ok, [only]} = Capture.list_posts(event.id)
      assert only.id == first.id
    end

    test "a Post is never edited — re-collecting leaves the stored text and payload untouched", %{
      event: event,
      author: author
    } do
      first =
        post!(event, %{
          author: author,
          x_id: "p1",
          text: "temblor sentido en la guaira",
          payload: %{"n" => 1}
        })

      second =
        post!(event, %{
          author: author,
          x_id: "p1",
          text: "otra cosa completamente distinta",
          payload: %{"n" => 2}
        })

      assert second.id == first.id
      assert second.text == "temblor sentido en la guaira"
      assert second.payload == %{"n" => 1}

      {:ok, reread} = Capture.get_post(first.id)
      assert reread.text == "temblor sentido en la guaira"
      assert reread.payload == %{"n" => 1}
    end

    test "the same X id in two Events is two distinct Posts", %{
      event: event,
      other_event: other
    } do
      here = post!(event, %{x_id: "p1"})
      there = post!(other, %{x_id: "p1"})

      refute here.id == there.id
      assert here.event_id == event.id
      assert there.event_id == other.id
    end
  end

  describe "reads" do
    test "by_event returns an Event's Posts newest first, by posted_at", %{
      event: event,
      author: author
    } do
      older =
        post!(event, %{author: author, x_id: "p1", posted_at: ~U[2026-06-24 22:05:00.000000Z]})

      newer =
        post!(event, %{author: author, x_id: "p2", posted_at: ~U[2026-06-24 22:40:00.000000Z]})

      middle =
        post!(event, %{author: author, x_id: "p3", posted_at: ~U[2026-06-24 22:20:00.000000Z]})

      {:ok, posts} = Capture.list_posts(event.id)

      assert Enum.map(posts, & &1.id) == [newer.id, middle.id, older.id]
    end

    test "by_event excludes another Event's Posts", %{event: event, other_event: other} do
      here = post!(event, %{x_id: "p1"})
      _there = post!(other, %{x_id: "p1"})

      {:ok, posts} = Capture.list_posts(event.id)

      assert Enum.map(posts, & &1.id) == [here.id]
    end
  end
end
