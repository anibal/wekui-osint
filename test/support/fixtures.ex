defmodule Wekui.Fixtures do
  @moduledoc """
  The smallest well-formed world a test can stand on: an Event, Places that can
  actually be collected on, a Search that is ready to be worked out, and the
  Posts, Authors and Appearances a Query brings back.
  """

  alias Wekui.Acquisition
  alias Wekui.Capture
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

  @doc "A draft Search over a one-hour window cut into ten-minute slices."
  def search!(event, attrs \\ %{}) do
    Acquisition.create_search!(
      Map.merge(
        %{
          event_id: event.id,
          name: "search-#{System.unique_integer([:positive])}",
          intent: "Collect what was said in the first hour",
          window_start: ~U[2026-06-24 22:00:00.000000Z],
          window_end: ~U[2026-06-24 23:00:00.000000Z]
        },
        attrs
      )
    )
  end

  @doc "A Search taken all the way to active, so its Queries can be asked."
  def active_search!(event, attrs \\ %{}) do
    event
    |> search!(attrs)
    |> Acquisition.decompose_search!()
    |> Acquisition.freeze_search!()
    |> Acquisition.activate_search!()
  end

  @doc "An Author of one Event, as first seen."
  def author!(event, attrs \\ %{}) do
    Capture.record_author!(
      Map.merge(
        %{
          event_id: event.id,
          x_id: "u#{System.unique_integer([:positive])}",
          handle: "reporteya",
          display_name: "Reporte Ya"
        },
        attrs
      )
    )
  end

  @doc "A collected Post, carrying a minimal well-formed Payload."
  def post!(event, attrs \\ %{}) do
    {author, attrs} = Map.pop_lazy(attrs, :author, fn -> author!(event) end)
    x_id = Map.get(attrs, :x_id, "p#{System.unique_integer([:positive])}")
    text = Map.get(attrs, :text, "temblor sentido en la guaira")

    Capture.collect_post!(
      Map.merge(
        %{
          event_id: event.id,
          author_id: author.id,
          x_id: x_id,
          text: text,
          posted_at: ~U[2026-06-24 22:05:00.000000Z],
          payload: %{"id" => x_id, "text" => text}
        },
        attrs
      )
    )
  end

  @doc "An Appearance: one Query found one Post."
  def appearance!(post, query) do
    Capture.record_appearance!(%{post_id: post.id, query_id: query.id})
  end
end
