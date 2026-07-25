defmodule Wekui.Narrative.Validations.NoPrivateName do
  @moduledoc """
  The persons red line on the write path (F54): a Claim's text fields name no
  private individual. Each configured field is checked against the event's name
  vocabulary — gazetteer geography plus the public-figure allowlist — via
  `Wekui.Narrative.PrivateNames`; any unexplained name-like sequence fails the
  write. See `docs/pages/claim.md`.

  Options — `:fields`, a non-empty list of text attributes to check
  (e.g. `[:subject, :nuance]`). A missing Event is the Event reference's error to
  raise, not this one's, so an absent `event_id` passes.
  """

  use Ash.Resource.Validation

  alias Wekui.Narrative.PrivateNames

  @impl true
  def init(opts) do
    case opts[:fields] do
      [_ | _] = fields ->
        if Enum.all?(fields, &is_atom/1),
          do: {:ok, opts},
          else: {:error, ":fields must be a list of attribute atoms"}

      _not_a_list ->
        {:error, "expects a non-empty :fields list"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :event_id) do
      nil ->
        :ok

      event_id ->
        vocabulary = PrivateNames.vocabulary(event_id)

        Enum.find_value(opts[:fields], :ok, fn field ->
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
