defmodule Wekui.Acquisition.Query do
  @moduledoc """
  One exact question actually asked of X: one Place, one slice, one exact
  request. It is the atom of collection — every post we hold arrived through
  one of these.

  A Query is both the plan and the record of what happened. Its **state** is
  not a field: it is read from its own timestamps together with its Search's
  step, so there is nothing that could disagree with the facts.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Acquisition,
    data_layer: AshSqlite.DataLayer

  alias Wekui.Acquisition.Calculations.ResultMode
  alias Wekui.Acquisition.Changes.StampOnce
  alias Wekui.Acquisition.QueryText
  alias Wekui.Acquisition.Validations.Askable
  alias Wekui.Acquisition.Validations.SearchAsking

  # Coverage asks the same question `QueryText.result_mode_of/1` answers, but in
  # SQL. Deriving the pattern from the one definition keeps them from drifting.
  @latest_pattern "%" <> QueryText.latest_suffix()

  sqlite do
    table "queries"
    repo Wekui.Repo

    custom_indexes do
      index [:search_id]
      index [:place_id]
    end

    references do
      reference :search, on_delete: :restrict
      reference :place, on_delete: :restrict
    end
  end

  actions do
    default_accept []
    defaults [:read, :destroy]

    create :create do
      primary? true
      description "Records one question worked out from a Search."
      accept [:search_id, :place_id, :query_text, :slice_start, :slice_end, :intent]
    end

    read :by_search do
      description "A Search's Queries, in slice order."
      argument :search_id, :uuid, allow_nil?: false

      filter expr(search_id == ^arg(:search_id))
      prepare build(sort: [slice_start: :asc, query_text: :asc])
    end

    read :runnable do
      description """
      The Queries of an active Search that are still worth asking: neither
      finished nor given up on. A Search that is not active has none.
      """

      argument :search_id, :uuid, allow_nil?: false

      filter expr(
               search_id == ^arg(:search_id) and search.status == :active and
                 is_nil(completed_at) and is_nil(discarded_at)
             )

      prepare build(sort: [slice_start: :asc, query_text: :asc])
    end

    read :covering do
      description """
      The Queries that count toward Coverage: finished, and asked in latest
      mode. A Query asked in top mode, or discarded, or never finished, covers
      nothing — it returned a selection, not the slice.
      """

      argument :search_id, :uuid, allow_nil?: false

      filter expr(
               search_id == ^arg(:search_id) and not is_nil(completed_at) and
                 is_nil(discarded_at) and like(query_text, ^@latest_pattern)
             )

      prepare build(sort: [slice_start: :asc, query_text: :asc])
    end

    update :start do
      description "Marks the moment we began asking. Asking twice does not restart it."
      require_atomic? false

      validate Askable
      validate {SearchAsking, allow: [:active]}

      change {StampOnce, attribute: :started_at}
    end

    update :complete do
      description "Freezes what the Query returned. What it returned is what it returned."
      require_atomic? false

      argument :posts_found, :integer, constraints: [min: 0]
      argument :posts_new, :integer, constraints: [min: 0]

      validate Askable
      validate {SearchAsking, allow: [:active, :paused]}

      change set_attribute(:posts_found, arg(:posts_found))
      change set_attribute(:posts_new, arg(:posts_new))
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :discard do
      description "Gives up on the Query. The status note says why."
      require_atomic? false

      argument :note, :string, allow_nil?: false, constraints: [min_length: 1]

      validate Askable
      validate {SearchAsking, allow: [:active, :paused]}

      change set_attribute(:status_note, arg(:note))
      change set_attribute(:discarded_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :query_text, :string do
      description "The exact request as sent. See Wekui.Acquisition.QueryText."
      allow_nil? false
      public? true
    end

    attribute :slice_start, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :slice_end, :utc_datetime_usec do
      description "Exclusive: consecutive slices touch but never overlap."
      allow_nil? false
      public? true
    end

    attribute :intent, :string do
      description "What this particular question is for."
      public? true
    end

    attribute :status_note, :string do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :discarded_at, :utc_datetime_usec do
      public? true
    end

    attribute :posts_found, :integer do
      description "Absent means nobody counted — never the same thing as zero."
      public? true
    end

    attribute :posts_new, :integer do
      description "Absent means nobody counted — never the same thing as zero."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :search, Wekui.Acquisition.Search do
      allow_nil? false
      public? true
    end

    belongs_to :place, Wekui.Core.Place do
      allow_nil? false
      public? true
    end

    has_many :query_names, Wekui.Acquisition.QueryName do
      public? true
    end

    has_many :query_terms, Wekui.Acquisition.QueryTerm do
      public? true
    end
  end

  calculations do
    calculate :state,
              :atom,
              expr(
                cond do
                  not is_nil(discarded_at) -> :discarded
                  not is_nil(completed_at) -> :completed
                  search.status == :draft -> :in_plan_review
                  not is_nil(started_at) -> :running_or_interrupted
                  true -> :queued
                end
              ) do
      description "Read from the timestamps and the Search's step, never stored."
      public? true
    end

    calculate :result_mode, :atom, ResultMode do
      description "The mode the Query was asked in, read back out of its own text."
      public? true
    end
  end

  identities do
    identity :unique_text_per_search, [:search_id, :query_text] do
      message "this Search already asks that exact question"
    end
  end
end
