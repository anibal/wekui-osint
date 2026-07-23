defmodule Wekui.Core.Place do
  @moduledoc """
  A gazetteer node — a location as people actually name it, and one node in
  its Event's tree (adjacency list through `parent_id`; a Place with no parent
  is a root).

  `type` is a free-form label (`pais`, `estado`, `parroquia`, `edificio`, …),
  folded on write so curation cannot introduce case or accent variants of the
  same label. It is deliberately not an enum: curating the tree means being
  able to name a new kind of node.

  Lifecycle is the curation gate. A Place is born `:proposed`, a human
  `promote`s it to `:active` — the only lifecycle that drives collection — and
  it leaves the working vocabulary either `:deprecated` (redirected onto a
  replacement) or `:discarded` (no replacement; a reason is required).
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Core,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine]

  alias Wekui.Core.Changes.Fold
  alias Wekui.Tree
  alias Wekui.Validations.Reference

  require Ash.Query

  sqlite do
    table "places"
    repo Wekui.Repo

    custom_indexes do
      index [:event_id]
      # The tree walks in `Wekui.Tree` descend on this one.
      index [:parent_id]
      index [:replaced_by_id]
    end

    # Nothing in this model is ever deleted — a Place leaves the working
    # vocabulary by moving to :deprecated or :discarded, and its Event, its
    # parent and its replacement all outlive it.
    references do
      reference :event, on_delete: :restrict
      reference :parent, on_delete: :restrict
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
      description "Adds a Place to an Event's tree. Born :proposed unless created :active."
      accept [:type, :canonical_name, :event_id, :parent_id]

      argument :lifecycle, :atom do
        description "Manual curation may skip the proposal step and create a Place :active."
        default :proposed
        constraints one_of: [:proposed, :active]
      end

      change {Fold, from: :type, to: :type}

      # Routed through the state machine rather than accepted as an attribute:
      # only `initial_states` may be born, and only it decides which those are.
      change fn changeset, _context ->
        AshStateMachine.transition_state(
          changeset,
          Ash.Changeset.get_argument(changeset, :lifecycle)
        )
      end

      validate {Reference, resource: __MODULE__, attribute: :parent_id}
    end

    read :by_event do
      description "Every Place of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :active do
      description "An Event's :active Places — the only lifecycle that drives collection."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id) and lifecycle == :active)
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :ancestors do
      description "The Place's ancestor chain, nearest-first, excluding itself."
      argument :place_id, :uuid, allow_nil?: false

      prepare fn query, _context ->
        ids = Tree.ancestor_ids(__MODULE__, query.arguments.place_id)

        query
        |> Ash.Query.filter(id in ^ids)
        |> Ash.Query.after_action(fn _query, places ->
          {:ok, Tree.order_by_ids(places, ids)}
        end)
      end
    end

    read :subtree do
      description "The Place and every descendant of it."
      argument :place_id, :uuid, allow_nil?: false

      prepare fn query, _context ->
        Ash.Query.filter(query, id in ^Tree.subtree_ids(__MODULE__, query.arguments.place_id))
      end
    end

    update :set_type do
      description "Curates the free-form type label."
      accept [:type]
      require_atomic? false

      change {Fold, from: :type, to: :type}
    end

    update :set_parent do
      description "Reparents the Place, refusing any move that would create a cycle."
      accept [:parent_id]
      require_atomic? false

      validate {Reference, resource: __MODULE__, attribute: :parent_id, outside_subtree?: true}
    end

    update :promote do
      description "The human gate: :proposed → :active."
      change transition_state(:active)
    end

    update :deprecate do
      description "Retires the Place onto an active replacement of the same Event."
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
      description "Retires the Place with no replacement. The reason is the record."
      require_atomic? false

      argument :note, :string, allow_nil?: false, constraints: [min_length: 1]

      change set_attribute(:status_note, arg(:note))
      change transition_state(:discarded)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :string do
      allow_nil? false
      public? true
    end

    attribute :canonical_name, :string do
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

    belongs_to :parent, __MODULE__ do
      public? true
    end

    belongs_to :replaced_by, __MODULE__ do
      public? true
    end

    has_many :children, __MODULE__ do
      destination_attribute :parent_id
      public? true
    end

    has_many :place_names, Wekui.Core.PlaceName do
      public? true
    end
  end

  defp default_reason(replaced_by_id) do
    case Ash.get(__MODULE__, replaced_by_id, authorize?: false) do
      {:ok, replacement} -> "replaced by #{inspect(replacement.canonical_name)}"
      {:error, _not_found} -> "replaced by place #{replaced_by_id}"
    end
  end
end
