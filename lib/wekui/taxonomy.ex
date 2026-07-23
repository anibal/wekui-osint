defmodule Wekui.Taxonomy do
  use Ash.Domain,
    otp_app: :wekui

  resources do
    resource Wekui.Taxonomy.Theme do
      define :create_theme, action: :create
      define :get_theme, action: :read, get_by: [:id]
      define :list_themes, action: :by_event, args: [:event_id]
      define :list_active_themes, action: :active, args: [:event_id]
      define :theme_ancestors, action: :ancestors, args: [:theme_id]
      define :theme_subtree, action: :subtree, args: [:theme_id]
      define :set_theme_parent, action: :set_parent
      define :promote_theme, action: :promote
      define :deprecate_theme, action: :deprecate
      define :discard_theme, action: :discard
    end

    resource Wekui.Taxonomy.AuthorTag do
      define :create_author_tag, action: :create
      define :get_author_tag, action: :read, get_by: [:id]
      define :list_author_tags, action: :by_event, args: [:event_id]
      define :list_active_author_tags, action: :active, args: [:event_id]
      define :promote_author_tag, action: :promote
      define :deprecate_author_tag, action: :deprecate
      define :discard_author_tag, action: :discard
    end
  end
end
