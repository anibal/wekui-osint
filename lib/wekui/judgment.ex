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
  end
end
