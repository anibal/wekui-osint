defmodule Wekui.Acquisition.SearchPlace do
  @moduledoc """
  One Place in one Search's Scope.

  A Search with no rows here has an empty Scope, which does not mean *nowhere*
  — it means *every active Place of the Event*, decided at the moment the plan
  is worked out.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Acquisition,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "search_places"
    repo Wekui.Repo

    custom_indexes do
      index [:place_id]
    end

    references do
      reference :search, on_delete: :restrict
      reference :place, on_delete: :restrict
    end
  end

  actions do
    default_accept [:search_id, :place_id]
    defaults [:read, :create, :destroy]
  end

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :search, Wekui.Acquisition.Search do
      allow_nil? false
      public? true
    end

    belongs_to :place, Wekui.Core.Place do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_place_per_search, [:search_id, :place_id] do
      message "that Place is already in this Search's Scope"
    end
  end
end
