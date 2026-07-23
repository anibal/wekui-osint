defmodule Wekui.Taxonomy.ThemeTest do
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

  defp theme!(event, attrs \\ %{}) do
    {:ok, theme} =
      Taxonomy.create_theme(Map.merge(%{event_id: event.id, name: "Power grid"}, attrs))

    theme
  end

  defp active!(event, attrs \\ %{}), do: theme!(event, Map.put(attrs, :lifecycle, :active))

  describe "create" do
    test "is born proposed", %{event: event} do
      theme = theme!(event)

      assert theme.lifecycle == :proposed
      assert theme.event_id == event.id
      assert is_nil(theme.parent_id)
    end

    test "can be born active for manual curation", %{event: event} do
      assert active!(event).lifecycle == :active
    end

    test "refuses to be born in a non-initial state", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.create_theme(%{
                 event_id: event.id,
                 name: "Power grid",
                 lifecycle: :deprecated
               })
    end

    test "keeps the name unfolded — case, accents and punctuation all survive", %{event: event} do
      assert theme!(event, %{name: "Água & Poder (ES)"}).name == "Água & Poder (ES)"
    end

    for field <- [:event_id, :name] do
      test "requires #{field}", %{event: event} do
        attrs = Map.delete(%{event_id: event.id, name: "Power grid"}, unquote(field))

        assert {:error, %Ash.Error.Invalid{}} = Taxonomy.create_theme(attrs)
      end
    end

    test "accepts a parent from the same event", %{event: event} do
      parent = theme!(event, %{name: "Infrastructure"})
      child = theme!(event, %{parent_id: parent.id})

      assert child.parent_id == parent.id
    end

    test "refuses a parent from another event", %{event: event, other_event: other} do
      foreign = theme!(other, %{name: "Politics"})

      assert {:error, error} =
               Taxonomy.create_theme(%{
                 event_id: event.id,
                 name: "Power grid",
                 parent_id: foreign.id
               })

      assert error_on(error, :parent_id) =~ "same event"
    end

    test "refuses a parent that does not exist", %{event: event} do
      assert {:error, error} =
               Taxonomy.create_theme(%{
                 event_id: event.id,
                 name: "Power grid",
                 parent_id: Ash.UUID.generate()
               })

      assert error_on(error, :parent_id) =~ "does not exist"
    end
  end

  describe "lifecycle" do
    test "promote moves proposed to active", %{event: event} do
      assert {:ok, promoted} = event |> theme!() |> Taxonomy.promote_theme()
      assert promoted.lifecycle == :active
    end

    test "promote refuses anything but proposed", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} = event |> active!() |> Taxonomy.promote_theme()
    end

    test "deprecate redirects onto an active replacement", %{event: event} do
      theme = active!(event)
      replacement = active!(event, %{name: "Electricity"})

      assert {:ok, deprecated} =
               Taxonomy.deprecate_theme(theme, %{replaced_by_id: replacement.id, note: "merged"})

      assert deprecated.lifecycle == :deprecated
      assert deprecated.replaced_by_id == replacement.id
      assert deprecated.status_note == "merged"
    end

    test "deprecate writes its own reason when none is given", %{event: event} do
      theme = active!(event)
      replacement = active!(event, %{name: "Electricity"})

      {:ok, deprecated} = Taxonomy.deprecate_theme(theme, %{replaced_by_id: replacement.id})

      assert deprecated.status_note =~ "Electricity"
    end

    test "deprecate refuses a proposed theme", %{event: event} do
      replacement = active!(event, %{name: "Electricity"})

      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.deprecate_theme(theme!(event), %{replaced_by_id: replacement.id})
    end

    test "deprecate refuses the theme itself as its replacement", %{event: event} do
      theme = active!(event)

      assert {:error, error} = Taxonomy.deprecate_theme(theme, %{replaced_by_id: theme.id})
      assert error_on(error, :replaced_by_id) =~ "itself"
    end

    test "deprecate refuses a replacement that is not active", %{event: event} do
      theme = active!(event)
      proposed = theme!(event, %{name: "Electricity"})

      assert {:error, error} = Taxonomy.deprecate_theme(theme, %{replaced_by_id: proposed.id})
      assert error_on(error, :replaced_by_id) =~ "must be active"
    end

    test "deprecate refuses a replacement from another event", %{event: event, other_event: other} do
      theme = active!(event)
      foreign = active!(other, %{name: "Electricity"})

      assert {:error, error} = Taxonomy.deprecate_theme(theme, %{replaced_by_id: foreign.id})
      assert error_on(error, :replaced_by_id) =~ "same event"
    end

    test "discard retires proposed and active themes, keeping the reason", %{event: event} do
      for theme <- [theme!(event), active!(event, %{name: "Electricity"})] do
        assert {:ok, discarded} = Taxonomy.discard_theme(theme, %{note: "not a real theme"})
        assert discarded.lifecycle == :discarded
        assert discarded.status_note == "not a real theme"
        assert is_nil(discarded.replaced_by_id)
      end
    end

    test "discard requires a reason", %{event: event} do
      theme = theme!(event)

      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.discard_theme(theme, %{})
      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.discard_theme(theme, %{note: ""})
      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.discard_theme(theme, %{note: "   "})
    end

    test "discarded is terminal", %{event: event} do
      {:ok, discarded} = Taxonomy.discard_theme(theme!(event), %{note: "gone"})

      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.promote_theme(discarded)
      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.discard_theme(discarded, %{note: "again"})
    end

    test "deprecated is terminal", %{event: event} do
      theme = active!(event)
      replacement = active!(event, %{name: "Electricity"})
      {:ok, deprecated} = Taxonomy.deprecate_theme(theme, %{replaced_by_id: replacement.id})

      assert {:error, %Ash.Error.Invalid{}} = Taxonomy.promote_theme(deprecated)

      another = active!(event, %{name: "Grid"})

      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.deprecate_theme(deprecated, %{replaced_by_id: another.id})
    end
  end

  describe "curation" do
    test "set_parent reparents within the event", %{event: event} do
      theme = theme!(event)
      new_parent = theme!(event, %{name: "Infrastructure"})

      assert {:ok, moved} = Taxonomy.set_theme_parent(theme, %{parent_id: new_parent.id})
      assert moved.parent_id == new_parent.id
    end

    test "set_parent to nil lifts the theme to a root", %{event: event} do
      parent = theme!(event, %{name: "Infrastructure"})
      child = theme!(event, %{parent_id: parent.id})

      assert {:ok, lifted} = Taxonomy.set_theme_parent(child, %{parent_id: nil})
      assert is_nil(lifted.parent_id)
    end

    test "set_parent refuses to make a theme its own parent", %{event: event} do
      theme = theme!(event)

      assert {:error, error} = Taxonomy.set_theme_parent(theme, %{parent_id: theme.id})
      assert error_on(error, :parent_id) =~ "cycle"
    end

    test "set_parent refuses to make a theme a child of its own descendant", %{event: event} do
      root = theme!(event, %{name: "Infrastructure"})
      mid = theme!(event, %{name: "Power grid", parent_id: root.id})
      leaf = theme!(event, %{name: "Substations", parent_id: mid.id})

      assert {:error, error} = Taxonomy.set_theme_parent(root, %{parent_id: leaf.id})
      assert error_on(error, :parent_id) =~ "cycle"
    end

    test "set_parent refuses a parent from another event", %{event: event, other_event: other} do
      theme = theme!(event)
      foreign = theme!(other, %{name: "Politics"})

      assert {:error, error} = Taxonomy.set_theme_parent(theme, %{parent_id: foreign.id})
      assert error_on(error, :parent_id) =~ "same event"
    end
  end

  describe "reads" do
    setup %{event: event} do
      root = theme!(event, %{name: "Infrastructure"})
      mid = theme!(event, %{name: "Power grid", parent_id: root.id})
      leaf = theme!(event, %{name: "Substations", parent_id: mid.id})

      %{root: root, mid: mid, leaf: leaf}
    end

    test "by_event returns only that event's themes", %{
      event: event,
      other_event: other,
      root: root
    } do
      theme!(other, %{name: "Politics"})

      {:ok, themes} = Taxonomy.list_themes(event.id)
      ids = Enum.map(themes, & &1.id)

      assert length(themes) == 3
      assert root.id in ids
    end

    test "active returns only active themes", %{event: event, root: root} do
      {:ok, promoted} = Taxonomy.promote_theme(root)
      {:ok, themes} = Taxonomy.list_active_themes(event.id)

      assert Enum.map(themes, & &1.id) == [promoted.id]
    end

    test "ancestors walks nearest-first, excluding the theme itself", %{
      root: root,
      mid: mid,
      leaf: leaf
    } do
      {:ok, ancestors} = Taxonomy.theme_ancestors(leaf.id)

      assert Enum.map(ancestors, & &1.id) == [mid.id, root.id]
    end

    test "ancestors of a root is empty", %{root: root} do
      assert {:ok, []} = Taxonomy.theme_ancestors(root.id)
    end

    test "subtree includes the theme and every descendant", %{root: root, mid: mid, leaf: leaf} do
      {:ok, subtree} = Taxonomy.theme_subtree(root.id)

      assert Enum.sort(Enum.map(subtree, & &1.id)) == Enum.sort([root.id, mid.id, leaf.id])
    end

    test "subtree of a leaf is just the leaf", %{leaf: leaf} do
      {:ok, subtree} = Taxonomy.theme_subtree(leaf.id)

      assert Enum.map(subtree, & &1.id) == [leaf.id]
    end

    test "a theme loads its event, parent and children", %{
      event: event,
      root: root,
      mid: mid,
      leaf: leaf
    } do
      {:ok, loaded} = Taxonomy.get_theme(mid.id, load: [:event, :parent, :children])

      assert loaded.event.id == event.id
      assert loaded.parent.id == root.id
      assert Enum.map(loaded.children, & &1.id) == [leaf.id]
    end

    test "a deprecated theme loads its replacement", %{event: event} do
      {:ok, theme} = event |> theme!(%{name: "Blackout"}) |> Taxonomy.promote_theme()
      replacement = active!(event, %{name: "Power outage"})

      {:ok, deprecated} = Taxonomy.deprecate_theme(theme, %{replaced_by_id: replacement.id})
      {:ok, loaded} = Taxonomy.get_theme(deprecated.id, load: [:replaced_by])

      assert loaded.replaced_by.id == replacement.id
    end
  end
end
