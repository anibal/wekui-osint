defmodule Wekui.Core do
  use Ash.Domain,
    otp_app: :wekui

  resources do
    resource Wekui.Core.Event do
      define :create_event, action: :create
      define :list_events, action: :read
      define :get_event, action: :read, get_by: [:id]
      define :get_event_by_name, action: :read, get_by: [:name]
      define :update_event, action: :update
    end

    resource Wekui.Core.Place do
      define :create_place, action: :create
      define :get_place, action: :read, get_by: [:id]
      define :list_places, action: :by_event, args: [:event_id]
      define :list_active_places, action: :active, args: [:event_id]
      define :place_ancestors, action: :ancestors, args: [:place_id]
      define :place_subtree, action: :subtree, args: [:place_id]
      define :set_place_type, action: :set_type
      define :set_place_parent, action: :set_parent
      define :promote_place, action: :promote
      define :deprecate_place, action: :deprecate
      define :discard_place, action: :discard
    end

    resource Wekui.Core.PlaceName do
      define :create_place_name, action: :create
      define :get_place_name, action: :read, get_by: [:id]
      define :list_place_names, action: :by_place, args: [:place_id]
      define :set_place_name_kind, action: :set_kind
      define :set_place_name_emission, action: :set_emission
    end

    resource Wekui.Core.Actor do
      define :register_agent, action: :register_agent
      define :get_actor, action: :read, get_by: [:id]
      define :list_actors, action: :by_event, args: [:event_id]
    end
  end
end
