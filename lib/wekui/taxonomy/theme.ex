defmodule Wekui.Taxonomy.Theme do
  @moduledoc """
  A node in an Event's theme taxonomy — the What axis. A Theme borrows the
  shape of a `Wekui.Core.Place`: one node in its Event's tree (adjacency list
  through `parent_id`; a Theme with no parent is a root), with the same
  curation lifecycle. It drops the name layer and the Type — a Theme's `name`
  is only ever a display label, never folded, emitted or matched — so it is a
  plainer resource than a Place.

  Lifecycle is the curation gate. A Theme is born `:proposed`, a human
  `promote`s it to `:active` — the classification targets a Post can be judged
  against — and it leaves the working vocabulary either `:deprecated`
  (redirected onto a replacement) or `:discarded` (no replacement; a reason is
  required).
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Taxonomy,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine]

  alias Wekui.Tree
  alias Wekui.Validations.Reference

  require Ash.Query

  sqlite do
    table "themes"
    repo Wekui.Repo

    custom_indexes do
      index [:event_id]
      # The tree walks in `Wekui.Tree` descend on this one.
      index [:parent_id]
      index [:replaced_by_id]
    end

    # A Theme is never deleted — it leaves the working vocabulary by moving to
    # :deprecated or :discarded, and its Event, its parent and its replacement
    # all outlive it.
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
      description "Adds a Theme to an Event's tree. Born :proposed unless created :active."
      accept [:name, :event_id, :parent_id]

      argument :lifecycle, :atom do
        description "Manual curation may skip the proposal step and create a Theme :active."
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

      validate {Reference, resource: __MODULE__, attribute: :parent_id}
    end

    read :by_event do
      description "Every Theme of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :active do
      description "An Event's :active Themes — the classification targets a Post can be judged against."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id) and lifecycle == :active)
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :ancestors do
      description "The Theme's ancestor chain, nearest-first, excluding itself."
      argument :theme_id, :uuid, allow_nil?: false

      prepare fn query, _context ->
        ids = Tree.ancestor_ids(__MODULE__, query.arguments.theme_id)

        query
        |> Ash.Query.filter(id in ^ids)
        |> Ash.Query.after_action(fn _query, themes ->
          {:ok, Tree.order_by_ids(themes, ids)}
        end)
      end
    end

    read :subtree do
      description "The Theme and every descendant of it."
      argument :theme_id, :uuid, allow_nil?: false

      prepare fn query, _context ->
        Ash.Query.filter(query, id in ^Tree.subtree_ids(__MODULE__, query.arguments.theme_id))
      end
    end

    update :set_parent do
      description "Reparents the Theme, refusing any move that would create a cycle."
      accept [:parent_id]
      require_atomic? false

      validate {Reference, resource: __MODULE__, attribute: :parent_id, outside_subtree?: true}
    end

    update :promote do
      description "The human gate: :proposed → :active."
      change transition_state(:active)
    end

    update :deprecate do
      description "Retires the Theme onto an active replacement of the same Event."
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
      description "Retires the Theme with no replacement. The reason is the record."
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
  end

  defp default_reason(replaced_by_id) do
    case Ash.get(__MODULE__, replaced_by_id, authorize?: false) do
      {:ok, replacement} -> "replaced by #{inspect(replacement.name)}"
      {:error, _not_found} -> "replaced by theme #{replaced_by_id}"
    end
  end
end
