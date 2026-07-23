defmodule Wekui.Core.Event do
  use Ash.Resource, otp_app: :wekui, domain: Wekui.Core, data_layer: AshSqlite.DataLayer

  sqlite do
    table "events"
    repo Wekui.Repo
  end

  actions do
    default_accept [:name, :t0, :goal, :timezone]
    defaults [:read, :update]

    create :create do
      primary? true
      description "Starts an Event, together with the Unplaced Place it will need."
      transaction? true

      change Wekui.Core.Changes.CreateUnplacedPlace
    end

    update :set_unplaced_place do
      description "Points the Event at the Unplaced Place created alongside it."
      accept [:unplaced_place_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :t0, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :goal, :string do
      allow_nil? false
      public? true
    end

    attribute :timezone, :string do
      allow_nil? false
      public? true
      default "America/Caracas"
    end

    timestamps()
  end

  relationships do
    has_many :places, Wekui.Core.Place do
      public? true
    end

    belongs_to :unplaced_place, Wekui.Core.Place do
      description "Where a Post waits while we do not know where it is about."
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
