defmodule Wekui.Narrative.Handle do
  @moduledoc """
  Deriving a person's DISPLAY HANDLE from the full name a post gave — first name +
  last-name initial ("Aaron Levi Cantillo Vargas" → "Aaron C."), down to the escape
  hatch (no handle; a human assigns one) when a name cannot be read with confidence:
  a lone token, or a compound surname with particles we cannot split ("de la Cruz").
  The handle is what a reader sees; the full name stays protected on the [[person]].

  Heuristic and deliberately fallible — the escape hatch plus human review are the
  backstop (`docs/pages/person.md`), so a wrong guess is a one-glance correction, not
  a leak.
  """

  alias Wekui.Normalize

  # Particles that signal a compound name we cannot split confidently → send to review.
  @particles ~w(de del la las los y e da do dos van von san santa)

  @doc """
  Derives a display handle from a full name. `{:ok, handle}`, or `{:review, reason}`
  when the name needs a human to assign one.
  """
  def derive(full_name) when is_binary(full_name) do
    tokens = String.split(full_name, ~r/\s+/u, trim: true)

    cond do
      length(tokens) < 2 -> {:review, :too_few_tokens}
      Enum.any?(tokens, &(Normalize.fold(&1) in @particles)) -> {:review, :has_particle}
      true -> {:ok, build(tokens)}
    end
  end

  def derive(_not_a_string), do: {:review, :not_a_string}

  # First name = first token. First surname = the second-to-last token for a name of
  # three or more (assume the last two tokens are the surnames, common in Venezuela),
  # else the last token for a two-token name.
  defp build(tokens) do
    first = hd(tokens)
    surname_index = if length(tokens) >= 3, do: length(tokens) - 2, else: length(tokens) - 1
    initial = tokens |> Enum.at(surname_index) |> String.first() |> String.upcase()
    "#{first} #{initial}."
  end
end
