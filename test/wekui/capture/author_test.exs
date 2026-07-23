defmodule Wekui.Capture.AuthorTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Capture

  setup do
    %{event: event!(), other_event: event!()}
  end

  describe "record" do
    test "records an Author that belongs to its Event, as first seen", %{event: event} do
      author = author!(event, %{x_id: "u42", handle: "reporteya", display_name: "Reporte Ya"})

      assert author.event_id == event.id
      assert author.x_id == "u42"
      assert author.handle == "reporteya"
      assert author.display_name == "Reporte Ya"

      {:ok, loaded} = Capture.get_author(author.id, load: [:event])
      assert loaded.event.id == event.id
    end

    test "a display name is optional", %{event: event} do
      author = author!(event, %{display_name: nil})

      assert is_nil(author.display_name)
    end

    for field <- [:event_id, :x_id, :handle] do
      test "requires #{field}", %{event: event} do
        attrs =
          Map.delete(
            %{event_id: event.id, x_id: "u1", handle: "reporteya", display_name: "Reporte Ya"},
            unquote(field)
          )

        assert {:error, %Ash.Error.Invalid{}} = Capture.record_author(attrs)
      end
    end
  end

  describe "identity" do
    test "re-seeing the same account returns the one we already hold, and only that one", %{
      event: event
    } do
      first = author!(event, %{x_id: "u1"})
      second = author!(event, %{x_id: "u1"})

      assert second.id == first.id
      assert {:ok, [only]} = Capture.list_authors(event.id)
      assert only.id == first.id
    end

    test "re-seeing keeps the first-seen handle and display name — we do not chase renames", %{
      event: event
    } do
      first = author!(event, %{x_id: "u1", handle: "old_handle", display_name: "Old Name"})
      second = author!(event, %{x_id: "u1", handle: "new_handle", display_name: "New Name"})

      assert second.id == first.id
      assert second.handle == "old_handle"
      assert second.display_name == "Old Name"

      {:ok, reread} = Capture.get_author(first.id)
      assert reread.handle == "old_handle"
      assert reread.display_name == "Old Name"
    end

    test "the same X id in two Events is two distinct Authors", %{
      event: event,
      other_event: other
    } do
      here = author!(event, %{x_id: "u1"})
      there = author!(other, %{x_id: "u1"})

      refute here.id == there.id
      assert here.event_id == event.id
      assert there.event_id == other.id
    end
  end

  describe "reads" do
    test "by_event returns an Event's Authors oldest first", %{event: event} do
      first = author!(event, %{x_id: "u1"})
      second = author!(event, %{x_id: "u2"})
      third = author!(event, %{x_id: "u3"})

      {:ok, authors} = Capture.list_authors(event.id)

      assert Enum.map(authors, & &1.id) == [first.id, second.id, third.id]
    end

    test "by_event excludes another Event's Authors", %{event: event, other_event: other} do
      here = author!(event, %{x_id: "u1"})
      _there = author!(other, %{x_id: "u1"})

      {:ok, authors} = Capture.list_authors(event.id)

      assert Enum.map(authors, & &1.id) == [here.id]
    end
  end
end
