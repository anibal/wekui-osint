defmodule Wekui.Capture.Post do
  @moduledoc """
  One message published on X that we have collected — a record of what we found,
  never an opinion about it. A Post is never edited and never deleted.

  The `:collect` action is an upsert on `(event_id, x_id)`: the same message
  found again by another Query does not make a second Post and does not disturb
  the one we hold. It returns the Post either way, so the Query that re-found it
  can record its Appearance.

  A Post carries the whole `payload` X sent — we can never ask for it again — and
  `x_id`, `text` and `posted_at` are read out of it. Those are accepted as their
  own inputs rather than parsed here: which key holds the id or the timestamp is
  X-payload knowledge that belongs to whatever collected the Post, not to this
  network-neutral resource. The Payload stays as the record the three are read
  from.

  A Post does not say where it is about: placement is a judgment, and it arrives
  with the judging vocabulary.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Capture,
    data_layer: AshSqlite.DataLayer

  alias Wekui.Capture.Author
  alias Wekui.Capture.Validations.SameEvent

  sqlite do
    table "posts"
    repo Wekui.Repo

    custom_indexes do
      # (event_id, x_id) is the unique identity; its index covers event_id reads.
      index [:author_id]
    end

    references do
      reference :event, on_delete: :restrict
      reference :author, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :collect do
      primary? true

      description "Records a Post, or returns the one we already hold. A Post is never edited."

      accept [:event_id, :x_id, :text, :posted_at, :payload, :author_id]

      upsert? true
      upsert_identity :unique_x_id_per_event
      # A Post is immutable: re-finding it changes nothing, only returns it.
      upsert_fields []

      validate {SameEvent, references: [{:author_id, Author}]}
    end

    read :by_event do
      description "Every Post of one Event, newest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [posted_at: :desc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :x_id, :string do
      description "The identifier X gives the message. Makes a Post the same Post."
      allow_nil? false
      public? true
    end

    attribute :text, :string do
      description "What the message says, read out of the Payload."
      allow_nil? false
      public? true
    end

    attribute :posted_at, :utc_datetime_usec do
      description "The moment X says the message was published."
      allow_nil? false
      public? true
    end

    attribute :payload, :map do
      description "Everything X told us about the message, kept exactly as it arrived."
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    belongs_to :author, Wekui.Capture.Author do
      allow_nil? false
      public? true
    end

    has_many :appearances, Wekui.Capture.Appearance do
      public? true
    end
  end

  identities do
    identity :unique_x_id_per_event, [:event_id, :x_id] do
      message "this Event already holds that message"
    end
  end
end
