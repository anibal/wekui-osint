defmodule Wekui.Capture.Appearance do
  @moduledoc """
  A record that one Query found one Post — how a Query's results land, and our
  only account of which question brought us what.

  Most Posts are found once; many are found again by a later or neighbouring
  Query. A re-finding is not a second Post, it is a second Appearance. The
  `:record` action is an upsert on `(post_id, query_id)`: one Query never records
  the same Post twice, so asking it again changes nothing.

  A Post's first Appearance is the Query that first found it — that is the whole
  answer, written nowhere else. An Appearance carries no engagement of its own:
  what a Query re-found almost never differed from what the Post already showed.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Capture,
    data_layer: AshSqlite.DataLayer

  alias Wekui.Capture.Post
  alias Wekui.Capture.Validations.SameEvent

  sqlite do
    table "appearances"
    repo Wekui.Repo

    custom_indexes do
      # (post_id, query_id) is the unique identity; its index covers post_id reads.
      index [:query_id]
    end

    references do
      reference :post, on_delete: :restrict
      reference :query, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :record do
      primary? true

      description "Records that a Query found a Post, or returns the Appearance we already hold."

      accept [:post_id, :query_id]

      upsert? true
      upsert_identity :unique_post_per_query
      # One Query never records the same Post twice: re-finding changes nothing.
      upsert_fields []

      # A Query has no event_id of its own; its Event is its Search's.
      validate {SameEvent,
                references: [
                  {:post_id, Post},
                  {:query_id, Wekui.Acquisition.Query, [:search, :event_id]}
                ]}
    end

    read :by_query do
      description "Every Appearance one Query recorded."
      argument :query_id, :uuid, allow_nil?: false

      filter expr(query_id == ^arg(:query_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :by_post do
      description "Every Appearance of one Post, in the order they were recorded."
      argument :post_id, :uuid, allow_nil?: false

      filter expr(post_id == ^arg(:post_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :post, Wekui.Capture.Post do
      allow_nil? false
      public? true
    end

    belongs_to :query, Wekui.Acquisition.Query do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_post_per_query, [:post_id, :query_id] do
      message "this Query already found that Post"
    end
  end
end
