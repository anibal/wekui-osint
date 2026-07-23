defmodule Wekui.Acquisition do
  @moduledoc """
  Going and getting posts: what we intend to collect (Search), the exact
  questions that intention becomes (Query), and the record of which names and
  words each question carried.
  """

  use Ash.Domain,
    otp_app: :wekui

  resources do
    resource Wekui.Acquisition.Search do
      define :create_search, action: :create
      define :get_search, action: :read, get_by: [:id]
      define :list_searches, action: :by_event, args: [:event_id]
      define :update_search, action: :update
      define :set_search_note, action: :set_note

      define :freeze_search, action: :freeze
      define :activate_search, action: :activate
      define :pause_search, action: :pause
      define :close_search, action: :close

      define :decompose_search, action: :decompose
      define :extend_search_with_place, action: :extend_with_place
      define :extend_search_with_term, action: :extend_with_term
      define :extend_search_window, action: :extend_window
    end

    resource Wekui.Acquisition.SearchTerm do
      define :get_search_term, action: :read, get_by: [:id]
      define :list_search_terms, action: :by_search, args: [:search_id]
    end

    # Reached through a Search's :places or :search_places, never on its own.
    resource Wekui.Acquisition.SearchPlace

    resource Wekui.Acquisition.Query do
      define :get_query, action: :read, get_by: [:id]
      define :list_queries, action: :by_search, args: [:search_id]
      define :list_runnable_queries, action: :runnable, args: [:search_id]
      define :list_covering_queries, action: :covering, args: [:search_id]
      define :start_query, action: :start
      define :complete_query, action: :complete
      define :discard_query, action: :discard
    end

    resource Wekui.Acquisition.QueryName do
      define :list_query_names, action: :by_query, args: [:query_id]
    end

    resource Wekui.Acquisition.QueryTerm do
      define :list_query_terms, action: :by_query, args: [:query_id]
    end
  end
end
