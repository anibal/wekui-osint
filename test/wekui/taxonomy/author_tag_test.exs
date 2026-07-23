defmodule Wekui.Taxonomy.AuthorTagTest do
  use Wekui.DataCase, async: false

  alias Wekui.Core
  alias Wekui.Taxonomy

  setup do
    {:ok, event} =
      Core.create_event(%{
        name: "event-#{System.unique_integer([:positive])}",
        t0: ~U[2026-03-07 20:00:00.000000Z],
        goal: "Track the national blackout aftermath"
      })

    {:ok, other_event} =
      Core.create_event(%{
        name: "event-#{System.unique_integer([:positive])}",
        t0: ~U[2026-03-07 20:00:00.000000Z],
        goal: "A different catastrophe entirely"
      })

    %{event: event, other_event: other_event}
  end

  defp tag!(event, attrs \\ %{}) do
    {:ok, tag} =
      Taxonomy.create_author_tag(Map.merge(%{event_id: event.id, name: "journalist"}, attrs))

    tag
  end

  defp active!(event, attrs \\ %{}), do: tag!(event, Map.put(attrs, :lifecycle, :active))

  describe "create" do
    test "is born proposed", %{event: event} do
      tag = tag!(event)

      assert tag.lifecycle == :proposed
      assert tag.event_id == event.id
    end

    test "can be born active for manual curation", %{event: event} do
      assert active!(event).lifecycle == :active
    end

    test "refuses to be born in a non-initial state", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.create_author_tag(%{
                 event_id: event.id,
                 name: "journalist",
                 lifecycle: :deprecated
               })
    end

    test "keeps the name unfolded — case, accents and punctuation all survive", %{event: event} do
      assert tag!(event, %{name: "Pro-Gobierno (Élite)"}).name == "Pro-Gobierno (Élite)"
    end

    for field <- [:event_id, :name] do
      test "requires #{field}", %{event: event} do
        attrs = Map.delete(%{event_id: event.id, name: "journalist"}, unquote(field))

        assert {:error, %Ash.Error.Invalid{}} = Taxonomy.create_author_tag(attrs)
      end
    end
  end

  describe "lifecycle" do
    test "promote moves proposed to active", %{event: event} do
      assert {:ok, promoted} = event |> tag!() |> Taxonomy.promote_author_tag()
      assert promoted.lifecycle == :active
    end

    test "promote refuses anything but proposed", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} = event |> active!() |> Taxonomy.promote_author_tag()
    end

    test "deprecate redirects onto an active replacement", %{event: event} do
      tag = active!(event)
      replacement = active!(event, %{name: "reporter"})

      assert {:ok, deprecated} =
               Taxonomy.deprecate_author_tag(tag, %{
                 replaced_by_id: replacement.id,
                 note: "merged"
               })

      assert deprecated.lifecycle == :deprecated
      assert deprecated.replaced_by_id == replacement.id
      assert deprecated.status_note == "merged"
    end

    test "deprecate writes its own reason when none is given", %{event: event} do
      tag = active!(event)
      replacement = active!(event, %{name: "reporter"})

      {:ok, deprecated} = Taxonomy.deprecate_author_tag(tag, %{replaced_by_id: replacement.id})

      assert deprecated.status_note =~ "reporter"
    end

    test "deprecate refuses a proposed tag", %{event: event} do
      replacement = active!(event, %{name: "reporter"})

      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.deprecate_author_tag(tag!(event), %{replaced_by_id: replacement.id})
    end

    test "deprecate refuses the tag itself as its replacement", %{event: event} do
      tag = active!(event)

      assert {:error, error} = Taxonomy.deprecate_author_tag(tag, %{replaced_by_id: tag.id})
      assert error_on(error, :replaced_by_id) =~ "itself"
    end

    test "deprecate refuses a replacement that is not active", %{event: event} do
      tag = active!(event)
      proposed = tag!(event, %{name: "reporter"})

      assert {:error, error} = Taxonomy.deprecate_author_tag(tag, %{replaced_by_id: proposed.id})
      assert error_on(error, :replaced_by_id) =~ "must be active"
    end

    test "deprecate refuses a replacement from another event", %{event: event, other_event: other} do
      tag = active!(event)
      foreign = active!(other, %{name: "reporter"})

      assert {:error, error} = Taxonomy.deprecate_author_tag(tag, %{replaced_by_id: foreign.id})
      assert error_on(error, :replaced_by_id) =~ "same event"
    end

    test "discard retires proposed and active tags, keeping the reason", %{event: event} do
      for tag <- [tag!(event), active!(event, %{name: "reporter"})] do
        assert {:ok, discarded} = Taxonomy.discard_author_tag(tag, %{note: "not a real tag"})
        assert discarded.lifecycle == :discarded
        assert discarded.status_note == "not a real tag"
        assert is_nil(discarded.replaced_by_id)
      end
    end

    test "discard requires a reason", %{event: event} do
      tag = tag!(event)

      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.discard_author_tag(tag, %{})
      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.discard_author_tag(tag, %{note: ""})
      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.discard_author_tag(tag, %{note: "   "})
    end

    test "discarded is terminal", %{event: event} do
      {:ok, discarded} = Taxonomy.discard_author_tag(tag!(event), %{note: "gone"})

      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.promote_author_tag(discarded)

      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.discard_author_tag(discarded, %{note: "again"})
    end

    test "deprecated is terminal", %{event: event} do
      tag = active!(event)
      replacement = active!(event, %{name: "reporter"})
      {:ok, deprecated} = Taxonomy.deprecate_author_tag(tag, %{replaced_by_id: replacement.id})

      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.promote_author_tag(deprecated)
    end
  end

  describe "reads" do
    test "by_event returns only that event's tags", %{event: event, other_event: other} do
      a = tag!(event, %{name: "journalist"})
      b = tag!(event, %{name: "official"})
      tag!(other, %{name: "activist"})

      {:ok, tags} = Taxonomy.list_author_tags(event.id)
      ids = Enum.map(tags, & &1.id)

      assert Enum.sort(ids) == Enum.sort([a.id, b.id])
    end

    test "active returns only active tags", %{event: event} do
      {:ok, promoted} = event |> tag!() |> Taxonomy.promote_author_tag()
      tag!(event, %{name: "official"})

      {:ok, tags} = Taxonomy.list_active_author_tags(event.id)

      assert Enum.map(tags, & &1.id) == [promoted.id]
    end

    test "a tag loads its event", %{event: event} do
      tag = tag!(event)
      {:ok, loaded} = Taxonomy.get_author_tag(tag.id, load: [:event])

      assert loaded.event.id == event.id
    end

    test "a deprecated tag loads its replacement", %{event: event} do
      tag = active!(event)
      replacement = active!(event, %{name: "reporter"})

      {:ok, deprecated} = Taxonomy.deprecate_author_tag(tag, %{replaced_by_id: replacement.id})
      {:ok, loaded} = Taxonomy.get_author_tag(deprecated.id, load: [:replaced_by])

      assert loaded.replaced_by.id == replacement.id
    end
  end
end
