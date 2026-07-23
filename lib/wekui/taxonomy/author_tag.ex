defmodule Wekui.Taxonomy.AuthorTag do
  @moduledoc """
  A label in an Event's author-tag vocabulary — the Who axis. An Author Tag
  borrows the shape of a `Wekui.Taxonomy.Theme` but drops the tree: it is flat,
  open and multi-label (behaviour, institution and stance axes coexist, and one
  Author can carry several at once), so it has no `parent_id`. Its `name` is a
  display label, never folded, emitted or matched.

  Lifecycle is the curation gate, mirroring a Theme's. An Author Tag is born
  `:proposed`, a human `promote`s it to `:active` — the vocabulary an Author
  can be judged to carry — and it leaves either `:deprecated` (redirected onto
  a replacement) or `:discarded` (no replacement; a reason is required).
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Taxonomy,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine]

  alias Wekui.Validations.Reference

  sqlite do
    table "author_tags"
    repo Wekui.Repo

    custom_indexes do
      index [:event_id]
      index [:replaced_by_id]
    end

    # An Author Tag is never deleted — it leaves the working vocabulary by
    # moving to :deprecated or :discarded, and its Event and its replacement
    # both outlive it.
    references do
      reference :event, on_delete: :restrict
      reference :replaced_by, on_delete: :restrict
    end
  end

  state_machine do
    state_attribute :lifecycle
    initial_states [:proposed, :active]
    default_initial_state :proposed

    transitions do
      transition :promote, from: :proposed, to: :active
      transition :deprecate, from: :active, to: :deprecated
      transition :discard, from: [:proposed, :active], to: :discarded
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :create do
      primary? true

      description "Adds an Author Tag to an Event's vocabulary. Born :proposed unless created :active."

      accept [:name, :event_id]

      argument :lifecycle, :atom do
        description "Manual curation may skip the proposal step and create a Tag :active."
        default :proposed
        constraints one_of: [:proposed, :active]
      end

      # Routed through the state machine rather than accepted as an attribute:
      # only `initial_states` may be born, and only it decides which those are.
      change fn changeset, _context ->
        AshStateMachine.transition_state(
          changeset,
          Ash.Changeset.get_argument(changeset, :lifecycle)
        )
      end
    end

    read :by_event do
      description "Every Author Tag of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :active do
      description "An Event's :active Author Tags — the vocabulary an Author can be judged to carry."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id) and lifecycle == :active)
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    update :promote do
      description "The human gate: :proposed → :active."
      change transition_state(:active)
    end

    update :deprecate do
      description "Retires the Tag onto an active replacement of the same Event."
      require_atomic? false

      argument :replaced_by_id, :uuid, allow_nil?: false
      argument :note, :string

      validate {Reference,
                resource: __MODULE__,
                argument: :replaced_by_id,
                not_self?: true,
                lifecycle: :active}

      change set_attribute(:replaced_by_id, arg(:replaced_by_id))
      change transition_state(:deprecated)

      change fn changeset, _context ->
        reason =
          Ash.Changeset.get_argument(changeset, :note) ||
            default_reason(Ash.Changeset.get_argument(changeset, :replaced_by_id))

        Ash.Changeset.force_change_attribute(changeset, :status_note, reason)
      end
    end

    update :discard do
      description "Retires the Tag with no replacement. The reason is the record."
      require_atomic? false

      argument :note, :string, allow_nil?: false, constraints: [min_length: 1]

      change set_attribute(:status_note, arg(:note))
      change transition_state(:discarded)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :status_note, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    belongs_to :replaced_by, __MODULE__ do
      public? true
    end
  end

  defp default_reason(replaced_by_id) do
    case Ash.get(__MODULE__, replaced_by_id, authorize?: false) do
      {:ok, replacement} -> "replaced by #{inspect(replacement.name)}"
      {:error, _not_found} -> "replaced by tag #{replaced_by_id}"
    end
  end
end
