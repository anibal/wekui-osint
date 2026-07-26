defmodule Wekui.Narrative.Person do
  @moduledoc """
  A human the Event's story is about — whom a [[claim]] is about, never the
  [[actor]] who made it (`docs/pages/person.md`). A Person holds the individual's
  **full name** — the one identifying datum — behind a human gate: it is the key
  that recognizes the same person across [[post]]s and Claims, and it is never shown
  as it stands. A reader sees the **display handle** (first name + last-name
  initial), derived from the name; the name itself never enters a Claim or a Beat.

  A Person is identified by the folded full name within one Event — `identify` is an
  upsert — so the same name recognizes the same Person, and their Claims link into
  one arc.

  **Private or public** sets how the person is shown: a private person is protected
  (handle only), a public one may be named; a human decides, and everyone is private
  and pending review until they say otherwise. A minor is never a Person here — the
  extractor records no minor's name — so a Person is always someone whose name may be
  held.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Narrative, data_layer: AshSqlite.DataLayer

  alias Wekui.Core.Changes.Fold
  alias Wekui.Narrative.Changes.DeriveHandle

  @kinds [:private, :public]
  @statuses [:pending_review, :approved, :withheld]

  @doc "Private (protected) or public (may be named)."
  def kinds, do: @kinds

  @doc "Whether the person may be shown: pending a human's review, approved, or withheld."
  def statuses, do: @statuses

  sqlite do
    table "persons"
    repo Wekui.Repo

    custom_indexes do
      # (event_id, normalized_name) is the unique identity; this covers name lookups.
      index [:normalized_name]
    end

    references do
      reference :event, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :identify do
      primary? true

      description "Recognizes the person of a given name within an Event, or returns the one we already hold."

      accept [:event_id, :full_name]

      upsert? true
      upsert_identity :unique_name_per_event
      upsert_fields []

      change {Fold, from: :full_name, to: :normalized_name}
      change DeriveHandle
    end

    update :set_handle do
      description "A human assigns or corrects the display handle (the escape hatch, or a fix)."
      accept [:display_handle]
    end

    update :set_kind do
      description "A human marks the person private or public."
      accept [:kind]
    end

    update :approve do
      description "A human approves the person for display."
      accept []
      change set_attribute(:status, :approved)
    end

    update :withhold do
      description "A human withholds the person from display; they read by role alone."
      accept []
      change set_attribute(:status, :withheld)
    end

    read :by_event do
      description "Every person of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :full_name, :string do
      description "The individual's name, exactly as a post gave it. Protected — never shown as it stands, never written into a Claim or a Beat."
      allow_nil? false
      public? true
    end

    attribute :normalized_name, :string do
      description "Folded full_name — the match key that recognizes the same person. Derived on write, never caller-supplied."
      allow_nil? false
    end

    attribute :display_handle, :string do
      description "What a reader sees — first name + last-name initial. Derived from the name; absent when the name needs a human to assign one."
      public? true
    end

    attribute :kind, :atom do
      description "Private (protected) or public (may be named). A human's call; private by default."
      allow_nil? false
      public? true
      default :private
      constraints one_of: @kinds
    end

    attribute :status, :atom do
      description "Whether this person may be shown: pending a human's review, approved, or withheld."
      allow_nil? false
      public? true
      default :pending_review
      constraints one_of: @statuses
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_name_per_event, [:event_id, :normalized_name] do
      message "this person is already known for this event"
    end
  end
end
