defmodule Wekui.Capture.Author do
  @moduledoc """
  The account that published a Post, as it was the first time we saw it.

  We record an Author once and do not chase renames: the `:record` action is an
  upsert that keeps the first-seen `handle` and `display_name`, so Posts we
  already hold keep saying what the account was called when they were published.
  How many followers it has and whether it is verified are deliberately absent —
  both move, and a number that moves is a fact about a moment, kept in the Post's
  Payload, not about the account.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Capture,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "authors"
    repo Wekui.Repo

    # (event_id, x_id) is the unique identity; its index covers event_id reads.
    references do
      reference :event, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :record do
      primary? true

      description """
      Records the Author of a Post, or returns the one we already hold. Re-seeing
      an account keeps the handle and display name we first saw — we do not chase
      renames.
      """

      accept [:event_id, :x_id, :handle, :display_name]

      upsert? true
      upsert_identity :unique_x_id_per_event
      # Change nothing on re-find: the first sighting is the record we keep.
      upsert_fields []
    end

    read :by_event do
      description "Every Author of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :x_id, :string do
      description "The identifier X gives the account. Makes an Author the same Author."
      allow_nil? false
      public? true
    end

    attribute :handle, :string do
      description "The name people type to reach the account, the one starting with an @."
      allow_nil? false
      public? true
    end

    attribute :display_name, :string do
      description "The name the account shows."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    has_many :posts, Wekui.Capture.Post do
      public? true
    end
  end

  identities do
    identity :unique_x_id_per_event, [:event_id, :x_id] do
      message "this Event already holds that account"
    end
  end
end
