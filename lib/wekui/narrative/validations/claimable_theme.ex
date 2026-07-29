defmodule Wekui.Narrative.Validations.ClaimableTheme do
  @moduledoc """
  A [[claim]] may only carry a [[theme]] that is **active** and whose nature is
  **happening**.

  Both halves are the point of having a vocabulary at all:

    * **Active** — a theme nobody has ratified does not exist yet. The extractor may
      propose one; only a person's `promote_theme!` makes it something a claim can
      assert, and that act is the record's answer to *who decided the record could say
      this*.
    * **A happening** — something that occurred at a moment. A **topic** is something a
      post is *about* that no claim follows from: a plea, an opinion, the standing
      condition of being trapped. Three independent readers of the same corpus drew
      that line identically on sixteen of their seventeen shared themes, so it is the
      corpus's line and not ours
      (`docs/pages/research-2026-07-27-three-readers-one-taxonomy.md`).

  A claim filed under *solicitud de información* would assert that asking is a thing
  that happened to somebody. That is precisely the error this whole layer exists to
  stop: the extractor read *"¿alguien tiene información sobre residencias Albatros?"*
  as *a person is missing*, twenty-three times, because it had no word for a family
  asking and no rule that could refuse one.
  """

  use Ash.Resource.Validation

  alias Wekui.Taxonomy

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :theme_id) do
      nil -> :ok
      theme_id -> claimable(theme_id)
    end
  end

  defp claimable(theme_id) do
    case Taxonomy.get_theme(theme_id) do
      # A theme that does not exist is `Reference`'s error to report, not ours.
      {:error, _not_found} ->
        :ok

      {:ok, %{lifecycle: lifecycle}} when lifecycle != :active ->
        {:error,
         field: :theme_id,
         message:
           "is #{lifecycle} — a claim may only carry a theme a person has taken into the vocabulary"}

      {:ok, %{nature: :topic, name: name}} ->
        {:error,
         field: :theme_id,
         message:
           "#{inspect(name)} is a topic, not a happening — a post can be about it, but nothing occurred that a claim could assert"}

      {:ok, _active_happening} ->
        :ok
    end
  end
end
