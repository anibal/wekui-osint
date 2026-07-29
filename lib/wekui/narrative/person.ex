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

  ## One human being, several rows

  The upsert holds only for a name written the **same way twice**. It does not hold for
  the way people actually write: measured on the pilot event, **668 Person rows carried
  zero exact name collisions** while one woman held four of them — `Belkys Josefina
  Barreto García`, `Belkis Josefina Barreto García`, `Belkys Barreto`, `Belkis Barreto`.
  A person counted twice is counted twice in everything the record later says.

  So a Person can be **merged into** another. It is a deprecation and never a rewrite
  ([[decision-2026-07-24-merge-is-deprecation]], [[principle-never-rewrite-the-record]]):
  the row survives, carries `merged_into_id`, and every Claim that named it also names
  the survivor. Nothing is deleted and the merge reads back — which is what makes it safe
  for a machine to do (`Wekui.Narrative.PersonDuplicates`).
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Narrative, data_layer: AshSqlite.DataLayer

  alias Wekui.Core.Changes.Fold
  alias Wekui.Narrative.Changes.DeriveHandle
  alias Wekui.Validations.Reference

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
      # Nothing here is ever deleted: the survivor outlives the row it absorbed.
      reference :merged_into, on_delete: :restrict
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

    update :merge_into do
      description """
      Folds this Person into another: the same human being, written down twice. The row
      is NOT removed — it keeps its name, carries `merged_into_id` and the reason, and
      stops being current. Carrying the Claims across is the caller's half, in one
      transaction (`Wekui.Narrative.PersonMerge`).
      """

      accept [:merged_into_id, :merge_note]
      require_atomic? false

      validate present(:merged_into_id)
      validate {Reference, resource: __MODULE__, attribute: :merged_into_id}

      # A row already folded away cannot be folded again — the survivor of the first
      # merge is where the second belongs, or the chain says two things about one person.
      validate fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :merged_into_id) do
          {:error, field: :merged_into_id, message: "has already been merged away"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        if Ash.Changeset.get_argument_or_attribute(changeset, :merged_into_id) ==
             Ash.Changeset.get_data(changeset, :id) do
          {:error, field: :merged_into_id, message: "cannot be merged into itself"}
        else
          :ok
        end
      end

      change set_attribute(:merged_at, &DateTime.utc_now/0)
    end

    read :by_event do
      description "Every person of one Event, oldest first — merged rows included."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :current_for_event do
      description "Every person of one Event that has not been merged away."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id) and is_nil(merged_into_id))
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

    attribute :merged_at, :utc_datetime_usec do
      description "When this row was folded into another. Set with merged_into_id; nil while the row is current."
      public? true
    end

    attribute :merge_note, :string do
      description "Why the two rows were judged one human being — the half a later reader cannot reconstruct."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    # The row this one turned out to be. A merged Person keeps its name and its place in
    # the record; it simply stops being current.
    belongs_to :merged_into, __MODULE__ do
      public? true
    end
  end

  identities do
    identity :unique_name_per_event, [:event_id, :normalized_name] do
      message "this person is already known for this event"
    end
  end
end
