defmodule Wekui.Narrative.PersonMerge do
  @moduledoc """
  Folding two rows that turned out to be one human being into a single [[person]]
  (`docs/pages/person.md`).

  The upsert on `identify` holds a name written the same way twice and nothing more.
  Measured on the pilot event, **668 Person rows carried zero exact name collisions**
  while one woman held four of them: `Belkys Josefina Barreto García`, `Belkis Josefina
  Barreto García`, `Belkys Barreto`, `Belkis Barreto`. A `y` for an `i`, and two middle
  names she had no time to type.

  ## Which row survives

  **The fullest name**, and this differs from `Wekui.Narrative.Merge` on purpose. A
  [[claim]] lives at its FIRST evidence, so the earlier account is canonical there. A
  person does not live at their first mention: the name with the most parts identifies
  them best and makes the better handle, so `Belkys Josefina Barreto García` survives
  `Belkis Barreto`. Ties fall to the earlier row, so the result never depends on the
  order two rows are handed over in.

  ## What it is, and why a machine may do it

  It is a **deprecation, never a rewrite** ([[decision-2026-07-24-merge-is-deprecation]]).
  The folded row keeps its name and its place in the record, carries `merged_into_id`
  and the reason it was folded, and stops being current. Every Claim that named it also
  names the survivor afterwards. Nothing is deleted, so a wrong merge is legible and
  reversible — which is what makes it safe to delegate without a person's signature in
  front of it.

  Wrapped in an explicit `Wekui.Repo.transaction` because ash_sqlite cannot run
  Ash-managed ones: a partial fold — the links moved but the row still current, or the
  reverse — would leave one human being half in two places.
  """

  alias Wekui.Narrative
  alias Wekui.Narrative.Person
  alias Wekui.Repo

  @doc """
  Folds two current Persons of one Event into one (order-independent), recording `note`
  as the reason. The fuller name survives and takes on the other's Claims; the other is
  closed and linked to it. Returns `{:ok, survivor}` reloaded.

  `{:error, :same_person}` for a row merged with itself, `{:error, :different_events}`
  across Events, `{:error, :already_merged}` if either has been folded away already.
  """
  def merge(%Person{} = a, %Person{} = b, note) do
    # Re-read both: a caller may hold a struct from before an earlier fold, and the
    # refusals below must not be fooled by a stale one.
    a = Narrative.get_person!(a.id)
    b = Narrative.get_person!(b.id)

    cond do
      a.id == b.id -> {:error, :same_person}
      a.event_id != b.event_id -> {:error, :different_events}
      a.merged_into_id || b.merged_into_id -> {:error, :already_merged}
      true -> do_merge(order(a, b), note)
    end
  end

  # The fullest name survives: more parts identify better and make the better handle. A
  # tie falls to the earlier row so the answer does not depend on argument order.
  defp order(a, b) do
    key = fn person ->
      {-length(String.split(person.full_name || "", " ", trim: true)),
       -String.length(person.full_name || ""), person.inserted_at, person.id}
    end

    if key.(a) <= key.(b), do: {a, b}, else: {b, a}
  end

  defp do_merge({survivor, folded}, note) do
    Repo.transaction(fn ->
      # Every claim that named the folded row now ALSO names the survivor. The old link
      # is left exactly where it is: `ClaimPerson` is an immutable upsert, and deleting
      # it would erase the true fact that this post said "Belkis Barreto". The folded
      # row is no longer current, so nothing reading current persons sees her twice.
      for link <- Narrative.person_arc!(folded.id) do
        Narrative.link_person!(%{claim_id: link.claim_id, person_id: survivor.id})
      end

      Narrative.merge_person!(folded, %{merged_into_id: survivor.id, merge_note: note})

      Narrative.get_person!(survivor.id)
    end)
  end

  @doc """
  The current row for `person` — itself, or whatever it was merged into, following a
  chain to its end. What every consumer of a Claim's persons should read through, since
  a claim keeps its link to the name the post actually used.
  """
  def current(%Person{merged_into_id: nil} = person), do: person

  def current(%Person{} = person),
    do: person.merged_into_id |> Narrative.get_person!() |> current()
end
