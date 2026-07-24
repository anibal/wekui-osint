defmodule Wekui.Judgment.SetReplacement do
  @moduledoc """
  The shared body of a judgment's `judge_set`: replace a scope's whole set of
  targets in one step. It retracts the targets no longer present and judges every
  target in the new set from one Actor — a target already current is superseded by
  its fresh row — so the current set always reads as one coherent answer.

      SetReplacement.run(ThemeJudgment,
        scope: {:post_id, post_id},
        target: {:theme_id, theme_ids},
        judge: %{event_id: e, actor_id: a, confidence: c, judged_at: t})

  Wrapped in an explicit `Repo.transaction` because ash_sqlite cannot run
  Ash-managed transactions (`can?(:transact) == false`): any failure rolls the
  partial writes back and re-raises, leaving the scope's answers as they were.
  Each judgment resource's `judge` action carries the supersession and the
  examined-empty exclusion; this only orchestrates the set.
  """

  alias Wekui.Judgment.Slot

  def run(resource, opts) do
    {scope_field, scope_id} = Keyword.fetch!(opts, :scope)
    {target_field, target_ids} = Keyword.fetch!(opts, :target)
    base = Keyword.fetch!(opts, :judge)
    judged_at = base[:judged_at] || DateTime.utc_now()
    # A set: judging the same target twice is one answer.
    target_ids = Enum.uniq(target_ids)
    target = MapSet.new(target_ids)

    Wekui.Repo.transaction(fn ->
      {:ok, existing} =
        Ash.read(Slot.current(resource, [{scope_field, scope_id}]), authorize?: false)

      # Retract the targets no longer present.
      Enum.each(existing, fn judgment ->
        unless MapSet.member?(target, Map.fetch!(judgment, target_field)) do
          judgment |> Ash.Changeset.for_update(:retract) |> Ash.update!(authorize?: false)
        end
      end)

      # Judge every target in the set, from one Actor. The results are exactly the
      # new current set (each is current, the departed were retracted above).
      Enum.map(target_ids, fn target_id ->
        attrs =
          base
          |> Map.put(scope_field, scope_id)
          |> Map.put(target_field, target_id)
          |> Map.put(:judged_at, judged_at)

        resource
        |> Ash.Changeset.for_create(:judge, attrs)
        |> Ash.create!(authorize?: false)
      end)
    end)
  end
end
