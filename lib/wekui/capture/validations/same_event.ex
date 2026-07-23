defmodule Wekui.Capture.Validations.SameEvent do
  @moduledoc """
  Everything a Post or an Appearance points at must belong to one Event. An
  Event's context is never shared, so a Post whose Author sits in another Event,
  or an Appearance whose Post and Query disagree about their Event, is not a
  smaller mistake than a missing reference — it is the same one.

  Options — `:references`, a non-empty list of `{field, resource}` or
  `{field, resource, event_path}`:

    * `field` — the attribute holding the referenced id.
    * `resource` — the resource it points at.
    * `event_path` — how to reach that resource's `event_id`. Defaults to
      `[:event_id]`; use e.g. `[:search, :event_id]` when the Event is only
      reachable through a relationship (a Query has no `event_id` of its own).

  The referenced records must all share one Event — together with the
  changeset's own `event_id`, when it has one. A nil reference passes:
  `allow_nil?` is the right place to forbid an absent reference.
  """

  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def init(opts) do
    case opts[:references] do
      [_ | _] = references ->
        if Enum.all?(references, &valid_reference?/1) do
          {:ok, opts}
        else
          {:error, "each reference must be {field, resource} or {field, resource, event_path}"}
        end

      _not_a_list ->
        {:error, "expects a non-empty :references list"}
    end
  end

  defp valid_reference?({field, resource}) when is_atom(field) and is_atom(resource), do: true

  defp valid_reference?({field, resource, [_ | _] = path})
       when is_atom(field) and is_atom(resource),
       do: Enum.all?(path, &is_atom/1)

  defp valid_reference?(_other), do: false

  @impl true
  def validate(changeset, opts, _context) do
    resolved = Enum.map(opts[:references], &resolve(changeset, &1))

    case Enum.find(resolved, &match?({_field, :not_found}, &1)) do
      {field, :not_found} ->
        {:error, field: field, message: "does not exist"}

      nil ->
        agree(changeset, for({field, {:ok, event_id}} <- resolved, do: {field, event_id}))
    end
  end

  # Every present reference's Event, plus the changeset's own when it has one,
  # must be a single Event. The offending field is the first that disagrees.
  defp agree(_changeset, [] = _no_present_references), do: :ok

  defp agree(changeset, present) do
    anchor = Ash.Changeset.get_attribute(changeset, :event_id)
    event_ids = Enum.map(present, &elem(&1, 1))

    case Enum.uniq(List.wrap(anchor) ++ event_ids) do
      [_one_event] ->
        :ok

      _many ->
        reference = anchor || hd(event_ids)

        {offender, _event_id} =
          Enum.find(present, fn {_field, event_id} -> event_id != reference end)

        {:error, field: offender, message: "must belong to the same event"}
    end
  end

  defp resolve(changeset, reference) do
    {field, resource, path} = normalize(reference)

    case Ash.Changeset.get_attribute(changeset, field) do
      nil -> {field, :absent}
      value -> {field, event_id_of(resource, value, path)}
    end
  end

  defp normalize({field, resource}), do: {field, resource, [:event_id]}
  defp normalize({field, resource, path}), do: {field, resource, path}

  # `path` reaches an event_id through at most one relationship: `[:event_id]`
  # reads it directly, `[:search, :event_id]` loads the one relationship first.
  defp event_id_of(resource, value, path) do
    {loads, [attribute]} = Enum.split(path, -1)

    query =
      resource
      |> Ash.Query.filter(id == ^value)
      |> Ash.Query.load(loads)

    case Ash.read_one(query, authorize?: false) do
      {:ok, nil} -> :not_found
      {:ok, record} -> {:ok, traverse(record, loads, attribute)}
      {:error, _error} -> :not_found
    end
  end

  defp traverse(record, loads, attribute) do
    loads
    |> Enum.reduce(record, fn relationship, acc -> Map.get(acc, relationship) end)
    |> Map.get(attribute)
  end
end
