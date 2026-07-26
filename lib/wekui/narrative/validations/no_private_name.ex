defmodule Wekui.Narrative.Validations.NoPrivateName do
  @moduledoc """
  The persons red line on the write path (F54): a Claim's text fields name no private
  individual. Two strictnesses, because a subject and a nuance differ:

    * `:strict` fields — the subject — allow NO person name at all: not a private one,
      not even an allowlisted public figure. A subject is a role; a public figure
      invoked to point at a private person ("el padre de la pianista Gabriela Montero")
      is the exact leak this closes. Only places and institutions (a rescue brigade, a
      ministry) may appear there.
    * `:lenient` fields — a nuance — additionally allow the public-figure allowlist, so
      a public official acting publicly may be named.

  Checked against the event's gazetteer (plus the allowlist, for lenient fields) via
  `Wekui.Narrative.PrivateNames`; any unexplained name-like sequence fails the write.
  """

  use Ash.Resource.Validation

  alias Wekui.Narrative.PrivateNames

  @impl true
  def init(opts) do
    fields = List.wrap(opts[:strict]) ++ List.wrap(opts[:lenient])

    cond do
      fields == [] -> {:error, "expects a non-empty :strict and/or :lenient field list"}
      not Enum.all?(fields, &is_atom/1) -> {:error, ":strict/:lenient entries must be atoms"}
      true -> {:ok, opts}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :event_id) do
      nil ->
        :ok

      event_id ->
        gazetteer = PrivateNames.gazetteer_names(event_id)
        lenient = gazetteer ++ PrivateNames.public_figures()

        checks =
          Enum.map(List.wrap(opts[:strict]), &{&1, gazetteer}) ++
            Enum.map(List.wrap(opts[:lenient]), &{&1, lenient})

        Enum.find_value(checks, :ok, fn {field, vocabulary} ->
          case PrivateNames.unexplained(Ash.Changeset.get_attribute(changeset, field), vocabulary) do
            [] ->
              nil

            names ->
              {:error,
               field: field,
               message: "must not name a private individual: #{Enum.join(names, ", ")}"}
          end
        end)
    end
  end
end
