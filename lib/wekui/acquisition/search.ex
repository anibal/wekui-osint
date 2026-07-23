defmodule Wekui.Acquisition.Search do
  @moduledoc """
  One Actor's stated intention to go and collect posts: these Places, over this
  stretch of time, optionally about these words.

  A Search is not itself a request to X. It is the plan from which many small,
  exact requests — Queries — are worked out. `decompose` does that working out,
  and it runs only while the Search is a draft, because that is the one step in
  which Queries have never been asked and can be thrown away.

  Once a Search has left draft its plan is fixed but the world is not, so it
  grows by extending: one dimension at a time, only ever adding Queries, never
  rewriting the ones already asked.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Acquisition,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine]

  alias Wekui.Acquisition.Changes.Decompose
  alias Wekui.Acquisition.Changes.StampOnce
  alias Wekui.Acquisition.Changes.WipePlan
  alias Wekui.Acquisition.Validations.Extendable
  alias Wekui.Core.Validations.PlaceReference

  @default_slice_seconds 600

  sqlite do
    table "searches"
    repo Wekui.Repo

    custom_indexes do
      index [:event_id]
    end

    references do
      reference :event, on_delete: :restrict
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :freeze, from: :draft, to: :ready
      transition :activate, from: [:ready, :paused], to: :active
      transition :pause, from: :active, to: :paused
      transition :close, from: [:draft, :ready, :active, :paused], to: :closed
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :create do
      primary? true
      description "States an intention to collect. Born a draft."

      accept [:event_id, :name, :intent, :window_start, :window_end, :slice_seconds, :result_mode]

      argument :place_ids, {:array, :uuid} do
        description "The Scope. Empty means every active Place of the Event."
        default []
      end

      argument :terms, {:array, :map} do
        description "Search Terms as %{term: , lang: }. Empty means a base sweep."
        default []
      end

      validate {PlaceReference, argument: :place_ids}

      change manage_relationship(:place_ids, :places, type: :append_and_remove)
      change manage_relationship(:terms, :search_terms, type: :create)
    end

    read :by_event do
      description "Every Search of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    update :update do
      primary? true
      description "Edits a draft. Replacing the Scope or the Terms throws the plan away."
      require_atomic? false
      transaction? true

      accept [:intent, :window_start, :window_end, :slice_seconds, :result_mode]

      argument :place_ids, {:array, :uuid}
      argument :terms, {:array, :map}

      validate attribute_equals(:status, :draft) do
        message "only a draft Search can be edited"
      end

      validate {PlaceReference, argument: :place_ids}

      # The bridges point at the very Terms being replaced, so the plan has to
      # go first. In a draft that costs nothing — decompose rebuilds it.
      change {WipePlan, only_with_arguments: [:place_ids, :terms]}

      change manage_relationship(:place_ids, :places, type: :append_and_remove)
      change manage_relationship(:terms, :search_terms, type: :direct_control)
    end

    update :set_note do
      description "Records why the Search is where it is right now."
      accept [:status_note]
    end

    update :freeze do
      description "Draft to ready: an Actor approves the plan, fixing it."
      require_atomic? false

      argument :note, :string

      change transition_state(:ready)
      change set_attribute(:status_note, arg(:note), set_when_nil?: false)
    end

    update :activate do
      description "Ready or paused to active: the only step in which Queries are asked."
      require_atomic? false

      argument :note, :string

      change transition_state(:active)
      change set_attribute(:status_note, arg(:note), set_when_nil?: false)
      change {StampOnce, attribute: :started_at}
    end

    update :pause do
      description "Active to paused: deliberately held, and resumable."
      require_atomic? false

      argument :note, :string

      change transition_state(:paused)
      change set_attribute(:status_note, arg(:note), set_when_nil?: false)
    end

    update :close do
      description "Anything not already closed becomes closed. This is final."
      require_atomic? false

      argument :note, :string

      change transition_state(:closed)
      change set_attribute(:status_note, arg(:note), set_when_nil?: false)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :decompose do
      description "Works the draft out into its Queries, from scratch."
      require_atomic? false
      transaction? true

      argument :now, :utc_datetime_usec do
        description "The reference point an open window is cut up to."
      end

      validate attribute_equals(:status, :draft) do
        message "only a draft Search's plan can be worked out again"
      end

      change {Decompose, wipe_first?: true}
    end

    update :extend_with_place do
      description "Adds a Place to the Scope, and the Queries it brings. Nothing else moves."
      require_atomic? false
      transaction? true

      argument :place_id, :uuid, allow_nil?: false
      argument :now, :utc_datetime_usec

      validate Extendable
      validate {PlaceReference, argument: :place_id}

      change manage_relationship(:place_id, :places, type: :append)
      change {Decompose, wipe_first?: false}
    end

    update :extend_with_term do
      description "Adds a Search Term, and the Queries it brings. Nothing else moves."
      require_atomic? false
      transaction? true

      argument :term, :map, allow_nil?: false
      argument :now, :utc_datetime_usec

      validate Extendable

      change manage_relationship(:term, :search_terms, type: :create)
      change {Decompose, wipe_first?: false}
    end

    update :extend_window do
      description "Pushes the window end further out, and adds the Queries for the new slices."
      require_atomic? false
      transaction? true

      accept [:window_end]
      argument :now, :utc_datetime_usec

      validate Extendable

      validate fn changeset, _context ->
        new_end = Ash.Changeset.get_attribute(changeset, :window_end)
        current_end = changeset.data.window_end

        if current_end && new_end && DateTime.compare(new_end, current_end) != :gt do
          {:error, field: :window_end, message: "must be further out than the current window end"}
        else
          :ok
        end
      end

      change {Decompose, wipe_first?: false}
    end
  end

  validations do
    validate compare(:slice_seconds, greater_than: 0) do
      message "must be a positive number of seconds"
    end

    validate compare(:window_end, greater_than: :window_start) do
      where present(:window_end)
      message "must be after the window start"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :intent, :string do
      description "What we mean to collect and why, to hold up against what came back."
      allow_nil? false
      public? true
    end

    attribute :window_start, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :window_end, :utc_datetime_usec do
      description "Absent means an open window: it keeps covering time as time passes."
      public? true
    end

    attribute :slice_seconds, :integer do
      description "How long each slice of the window is. Ten minutes unless said otherwise."
      allow_nil? false
      public? true
      default @default_slice_seconds
    end

    attribute :result_mode, :atom do
      allow_nil? false
      public? true
      default :latest
      constraints one_of: [:latest, :top]
    end

    attribute :status_note, :string do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      description "When the Search first became active."
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      description "When the Search was closed."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    has_many :search_terms, Wekui.Acquisition.SearchTerm do
      public? true
    end

    has_many :search_places, Wekui.Acquisition.SearchPlace do
      public? true
    end

    has_many :queries, Wekui.Acquisition.Query do
      public? true
    end

    many_to_many :places, Wekui.Core.Place do
      through Wekui.Acquisition.SearchPlace
      source_attribute_on_join_resource :search_id
      destination_attribute_on_join_resource :place_id
      public? true
    end
  end

  identities do
    identity :unique_name_per_event, [:event_id, :name] do
      message "a Search of this Event already has that name"
    end
  end
end
