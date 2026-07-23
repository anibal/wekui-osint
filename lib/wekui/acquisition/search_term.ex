defmodule Wekui.Acquisition.SearchTerm do
  @moduledoc """
  One word or phrase a Search asks about, and the language it is written in.

  Terms narrow a Search from *everything said about these Places* to *what was
  said about these Places concerning these words*. A Search carrying no Terms
  is a base sweep.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Acquisition,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "search_terms"
    repo Wekui.Repo

    custom_indexes do
      index [:search_id]
    end

    references do
      reference :search, on_delete: :restrict
    end
  end

  actions do
    default_accept [:term, :lang, :search_id]
    defaults [:read, :create, :update, :destroy]

    read :by_search do
      description "Every Term of one Search, oldest first."
      argument :search_id, :uuid, allow_nil?: false

      filter expr(search_id == ^arg(:search_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :term, :string do
      allow_nil? false
      public? true
    end

    attribute :lang, :string do
      description "The language the term is written in, so one Search can ask in several."
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :search, Wekui.Acquisition.Search do
      allow_nil? false
      public? true
    end

    has_many :query_terms, Wekui.Acquisition.QueryTerm do
      public? true
    end
  end
end
