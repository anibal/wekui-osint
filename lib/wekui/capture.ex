defmodule Wekui.Capture do
  @moduledoc """
  What came back: the Posts we collected, the Authors that published them, and
  the Appearances that record which Query found which Post.

  Core is what an Event is made of; Acquisition is the intention and the exact
  questions we ask; Capture is the evidence those questions returned.
  """

  use Ash.Domain,
    otp_app: :wekui

  resources do
    resource Wekui.Capture.Author do
      define :record_author, action: :record
      define :get_author, action: :read, get_by: [:id]
      define :list_authors, action: :by_event, args: [:event_id]
    end

    resource Wekui.Capture.Post do
      define :collect_post, action: :collect
      define :get_post, action: :read, get_by: [:id]
      define :list_posts, action: :by_event, args: [:event_id]
    end

    resource Wekui.Capture.Appearance do
      define :record_appearance, action: :record
      define :list_appearances_by_query, action: :by_query, args: [:query_id]
      define :list_appearances_by_post, action: :by_post, args: [:post_id]
    end
  end
end
