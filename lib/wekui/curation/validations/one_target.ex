defmodule Wekui.Curation.Validations.OneTarget do
  @moduledoc """
  An act is about exactly one thing: the thing whose state changed.

  The alternative — a polymorphic `{target_type, target_id}` pair — buys any number of
  targets and gives up the foreign key, which SQLite cannot enforce over a pair. The
  targets are all real tables, and `on_delete: :restrict` keeps the trail leading
  somewhere. So each gets a nullable column, and this holds the "exactly one" the
  columns cannot say by themselves. The list grows only when a genuinely new kind of
  thing becomes curatable — a [[theme]] was the fourth, when the vocabulary of
  happenings stopped being a free string and became a record a person ratifies.

  Two targets is as wrong as none: an act that reparents a Place is about that Place,
  and an act that relinks a Claim onto a Place is about the *Claim* — the claim's set
  of places is what moved, and the place it moved to is named in `after`. Two targets
  would mean the act could not say which thing it changed.
  """

  use Ash.Resource.Validation

  @targets [:place_id, :person_id, :claim_id, :theme_id]

  @doc "The target columns, exactly one of which every act carries."
  def targets, do: @targets

  @impl true
  def validate(changeset, _opts, _context) do
    case Enum.filter(@targets, &Ash.Changeset.get_attribute(changeset, &1)) do
      [_one] ->
        :ok

      [] ->
        {:error,
         field: :place_id,
         message: "an act is about something: give it a place, a person, a claim or a theme"}

      many ->
        {:error,
         field: hd(many),
         message:
           "an act is about exactly one thing, and this one names #{length(many)}: #{Enum.map_join(many, ", ", &to_string/1)}"}
    end
  end
end
