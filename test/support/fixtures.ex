defmodule Wekui.Fixtures do
  @moduledoc """
  The smallest well-formed world a test can stand on: an Event and Places that
  can actually be collected on.
  """

  alias Wekui.Core

  def event!(attrs \\ %{}) do
    Core.create_event!(
      Map.merge(
        %{
          name: "event-#{System.unique_integer([:positive])}",
          t0: ~U[2026-06-24 22:00:00.000000Z],
          goal: "Track the aftermath"
        },
        attrs
      )
    )
  end

  @doc "An active Place carrying one raw name — the minimum that will be swept."
  def place!(event, attrs \\ %{}) do
    {names, attrs} = Map.pop(attrs, :names)

    place =
      Core.create_place!(
        Map.merge(
          %{
            event_id: event.id,
            type: "parroquia",
            canonical_name: "Caraballeda",
            lifecycle: :active
          },
          attrs
        )
      )

    for name <- names || [{place.canonical_name, :raw}] do
      name!(place, name)
    end

    place
  end

  def name!(place, {string, emission}) do
    Core.create_place_name!(%{
      place_id: place.id,
      name: string,
      kind: :official,
      emission: emission
    })
  end
end
