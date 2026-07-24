defmodule Wekui.Judgment.Where do
  @moduledoc """
  Where a Post is about — read, never stored. A Post carries no place of its own;
  its where is resolved from its current judgments, following one chain:

    * a current `Placement` whose Place is `:proposed` or `:active` → `{:place, place}`;
    * a current placement whose Place is `:deprecated` → its replacement, followed
      onwards if that Place was itself deprecated;
    * a current placement whose Place is `:discarded` with no replacement → Unplaced;
    * no placement but a current `NoPlace` → `:no_place`;
    * nothing judged → `{:unplaced, unplaced_place}` — the [[unplaced-place]].

  This is why settling a Place never rewrites a placement (see
  `settling-a-collected-place`): the Post keeps the placement it was given, and
  what it *means* is worked out here, when we read it.
  """

  alias Wekui.Core.{Event, Place}
  alias Wekui.Capture.Post
  alias Wekui.Judgment.{NoPlace, Placement}

  require Ash.Query

  @typedoc "Where a Post is about, resolved from its current judgments."
  @type t :: {:place, Place.t()} | {:unplaced, Place.t()} | :no_place

  @doc "Resolves where a Post is about."
  @spec of(Ash.UUID.t()) :: t()
  def of(post_id) do
    case current(Placement, post_id) do
      %{place_id: place_id, event_id: event_id} -> follow(place_id, event_id, MapSet.new())
      nil -> without_placement(post_id)
    end
  end

  defp without_placement(post_id) do
    case current(NoPlace, post_id) do
      %{} -> :no_place
      nil -> unplaced(event_id_of_post(post_id))
    end
  end

  # A deprecated Place with no replacement, or a chain that loops, resolves to
  # Unplaced rather than looping — deprecation always sets an active replacement,
  # so the guard is defensive.
  defp follow(nil, event_id, _seen), do: unplaced(event_id)

  defp follow(place_id, event_id, seen) do
    if MapSet.member?(seen, place_id) do
      unplaced(event_id)
    else
      place = Ash.get!(Place, place_id, authorize?: false)

      case place.lifecycle do
        live when live in [:proposed, :active] -> {:place, place}
        :deprecated -> follow(place.replaced_by_id, event_id, MapSet.put(seen, place_id))
        :discarded -> unplaced(event_id)
      end
    end
  end

  defp unplaced(event_id) do
    event = Ash.get!(Event, event_id, authorize?: false)
    {:unplaced, Ash.get!(Place, event.unplaced_place_id, authorize?: false)}
  end

  defp event_id_of_post(post_id), do: Ash.get!(Post, post_id, authorize?: false).event_id

  defp current(resource, post_id) do
    resource
    |> Ash.Query.filter(post_id == ^post_id and is_nil(superseded_at))
    |> Ash.read_one!(authorize?: false)
  end
end
