defmodule Wekui.Acquisition.QueryTerm do
  @moduledoc """
  One Search Term that one Query carried.

  The other half of attribution: which words a question was asked with, so that
  yield can be read per Term as well as per name.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Acquisition,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "query_terms"
    repo Wekui.Repo

    custom_indexes do
      index [:search_term_id]
    end

    references do
      reference :query, on_delete: :restrict
      reference :search_term, on_delete: :restrict
    end
  end

  actions do
    default_accept [:query_id, :search_term_id]
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

    belongs_to :search_term, Wekui.Acquisition.SearchTerm do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_term_per_query, [:query_id, :search_term_id]
  end
end
