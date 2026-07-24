defmodule Wekui.Judgment do
  use Ash.Domain,
    otp_app: :wekui

  resources do
    resource Wekui.Judgment.ThemeJudgment do
      define :judge_theme, action: :judge
      define :judge_theme_set, action: :judge_set
      define :retract_theme_judgment, action: :retract
      define :get_theme_judgment, action: :read, get_by: [:id]
      define :current_theme_judgments, action: :current_for_post, args: [:post_id]
      define :list_theme_judgments, action: :by_event, args: [:event_id]
    end

    resource Wekui.Judgment.ThemeNone do
      define :judge_theme_none, action: :judge_none
      define :retract_theme_none, action: :retract
      define :get_theme_none, action: :read, get_by: [:id]
      define :current_theme_none, action: :current_for_post, args: [:post_id]
    end

    resource Wekui.Judgment.AuthorTagJudgment do
      define :judge_author_tag, action: :judge
      define :judge_author_tag_set, action: :judge_set
      define :retract_author_tag_judgment, action: :retract
      define :get_author_tag_judgment, action: :read, get_by: [:id]
      define :current_author_tag_judgments, action: :current_for_author, args: [:author_id]
      define :list_author_tag_judgments, action: :by_event, args: [:event_id]
    end

    resource Wekui.Judgment.AuthorTagNone do
      define :judge_author_tag_none, action: :judge_none
      define :retract_author_tag_none, action: :retract
      define :get_author_tag_none, action: :read, get_by: [:id]
      define :current_author_tag_none, action: :current_for_author, args: [:author_id]
    end

    resource Wekui.Judgment.Placement do
      define :place_post, action: :place
      define :retract_placement, action: :retract
      define :get_placement, action: :read, get_by: [:id]
      define :current_placement, action: :current_for_post, args: [:post_id]
      define :list_placements, action: :by_event, args: [:event_id]
    end

    resource Wekui.Judgment.NoPlace do
      define :judge_no_place, action: :judge_none
      define :retract_no_place, action: :retract
      define :get_no_place, action: :read, get_by: [:id]
      define :current_no_place, action: :current_for_post, args: [:post_id]
    end
  end
end
