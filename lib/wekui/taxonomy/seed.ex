defmodule Wekui.Taxonomy.Seed do
  @moduledoc """
  Seeds an [[event]]'s [[theme]] tree from a committed data file
  (`priv/taxonomy/*.json`) — the vocabulary of happenings, proposed for a person to
  ratify.

  **Every node is born `:proposed`.** That is the whole difference from
  `Wekui.Gazetteer.Seed`, whose places arrive `:active` because they were already
  vetted in the source project. These themes were read out of the corpus by machines,
  and a vocabulary nobody signed is precisely the unattributed decision
  `Wekui.Curation` exists to abolish. The operator promotes what he blesses, renames
  what reads wrong, and discards the rest — and the record says he did
  (`docs/pages/curation.md`).

  **The data is not invented.** Three independent readers were given an identical
  brief and an identical 302-post sample — a deterministic 1-in-23 slice of the 6,982
  Caraballeda posts, exact duplicates removed, across all eight days — and each
  proposed a tree and classified every post. The comparison was deterministic: themes
  were matched by *which posts each covers*, not by the words each reader chose. Ten
  themes were reached by all three, seven more by two of three, and every node here
  carries which readers reached it, with what post overlap, and what each of them
  called it (`docs/pages/research-2026-07-27-three-readers-one-taxonomy.md`).

  Four nodes are **structural**: they group the themes below them and nothing is ever
  classified against them directly. They exist because a tree that puts *solicitud de
  información* beside *colapso estructural* has lost the shape the readers found.

  Seeding is top-down (a parent before its children) and idempotent: a theme already
  in the event — matched on name — is left exactly as it is, whatever its lifecycle.
  Re-running never un-promotes what a person has ratified, and never re-proposes what
  they discarded.
  """

  alias Wekui.Taxonomy

  @doc """
  Seeds the litoral-central vocabulary into `event_id`. `opts[:themes]` overrides the
  data (for tests). Returns `%{created:, reused:}`.
  """
  def litoral_central(event_id, opts \\ []) do
    seed(event_id, opts[:themes] || load("litoral-central-2026.json"))
  end

  defp load(file) do
    :wekui
    |> :code.priv_dir()
    |> Path.join("taxonomy/#{file}")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("themes")
  end

  defp seed(event_id, themes) do
    held = event_id |> Taxonomy.list_themes!() |> Map.new(&{&1.name, &1})

    # Parents first, so a child always finds the node it hangs from. The file is
    # already in that order; sorting by depth makes the guarantee the code's, not
    # the file's.
    themes
    |> Enum.sort_by(&depth(&1, themes))
    |> Enum.reduce({held, %{created: 0, reused: 0}}, fn theme, {known, counts} ->
      case Map.fetch(known, theme["name"]) do
        {:ok, _already} ->
          {known, Map.update!(counts, :reused, &(&1 + 1))}

        :error ->
          created =
            Taxonomy.create_theme!(%{
              event_id: event_id,
              name: theme["name"],
              definition: theme["definition"],
              applies_when: applies_when(theme),
              nature: String.to_existing_atom(theme["nature"]),
              parent_id: theme["parent"] && known[theme["parent"]].id
            })

          {Map.put(known, created.name, created), Map.update!(counts, :created, &(&1 + 1))}
      end
    end)
    |> elem(1)
  end

  # The boundary a reader had to draw belongs IN the rule, not beside it: the sentence
  # that separates two look-alike themes is the operational half, and a consumer that
  # reads `applies_when` alone must not lose it.
  defp applies_when(theme) do
    case theme["not_to_be_confused_with"] do
      nil -> theme["applies_when"]
      line -> theme["applies_when"] <> " Not to be confused with: " <> line
    end
  end

  defp depth(theme, themes, seen \\ 0)
  defp depth(%{"parent" => nil}, _themes, seen), do: seen

  defp depth(%{"parent" => parent}, themes, seen) do
    case Enum.find(themes, &(&1["name"] == parent)) do
      nil -> seen
      found -> depth(found, themes, seen + 1)
    end
  end
end
