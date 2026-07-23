defmodule Wekui.Core.PlaceName do
  @moduledoc """
  A string people actually use for a Place, on two independent axes:

    * `kind` — what the string *is* (official, colloquial, alias, acronym, …);
    * `emission` — how it may be *emitted* into a query: `:raw` on its own,
      `:anchored` only alongside its ancestors' names, or `:recognition_only`
      (understood when read, never emitted).

  The axes do not predict each other: an official name can be too generic to
  emit bare, and a colloquial one can be the most distinctive string there is.

  `normalized` is the input-side match key, always derived from `name` and
  never accepted from the caller.

  One Place may hold the same string more than once — the same words are often
  both the official and the colloquial name — and the two rows stay distinct so
  that yield can be attributed per variant.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Core,
    data_layer: AshSqlite.DataLayer

  alias Wekui.Core.Changes.Fold

  @kinds [
    :official,
    :colloquial,
    :alias,
    :acronym,
    :abbreviation,
    :spelling_variant,
    :historical,
    :error
  ]

  @emissions [:raw, :anchored, :recognition_only]

  @doc "The `kind` axis — what the string is."
  def kinds, do: @kinds

  @doc "The `emission` axis — how the string may be emitted into a query."
  def emissions, do: @emissions

  sqlite do
    table "place_names"
    repo Wekui.Repo

    custom_indexes do
      index [:place_id]
      # The input-side match key: "which place did someone just name?"
      index [:normalized]
    end

    references do
      reference :place, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :create do
      primary? true
      description "Attaches a string to a Place on both axes."
      accept [:name, :kind, :emission, :place_id]

      change {Fold, from: :name, to: :normalized}
    end

    read :by_place do
      description "Every name of one Place, oldest first."
      argument :place_id, :uuid, allow_nil?: false

      filter expr(place_id == ^arg(:place_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    update :set_kind do
      description "Curates the kind axis."
      accept [:kind]
    end

    update :set_emission do
      description "Curates the emission axis."
      accept [:emission]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :normalized, :string do
      allow_nil? false
      description "Derived from name via Wekui.Normalize.fold/1; never caller-supplied."
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: @kinds
    end

    attribute :emission, :atom do
      allow_nil? false
      public? true
      constraints one_of: @emissions
    end

    timestamps()
  end

  relationships do
    belongs_to :place, Wekui.Core.Place do
      allow_nil? false
      public? true
    end
  end
end
