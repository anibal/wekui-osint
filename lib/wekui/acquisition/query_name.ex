defmodule Wekui.Acquisition.QueryName do
  @moduledoc """
  One Place Name that one Query emitted.

  This is what lets us say later *this name variant brought in those posts,
  that one brought in none*, and curate the gazetteer on evidence rather than
  opinion.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Acquisition,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "query_names"
    repo Wekui.Repo

    custom_indexes do
      index [:place_name_id]
    end

    references do
      reference :query, on_delete: :restrict
      reference :place_name, on_delete: :restrict
    end
  end

  actions do
    default_accept [:query_id, :place_name_id]
    defaults [:read, :create, :destroy]

    read :by_query do
      argument :query_id, :uuid, allow_nil?: false

      filter expr(query_id == ^arg(:query_id))
    end
  end

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :query, Wekui.Acquisition.Query do
      allow_nil? false
      public? true
    end

    belongs_to :place_name, Wekui.Core.PlaceName do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_name_per_query, [:query_id, :place_name_id]
  end
end
