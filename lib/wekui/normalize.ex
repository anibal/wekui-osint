defmodule Wekui.Normalize do
  @moduledoc """
  The one shared normalization: lowercase, accent-fold, collapse whitespace, trim.

  Conservative on purpose — it never strips articles, punctuation, digits, or
  inner spaces ("Las Quince Letras" has fifteen letters). Fuzzy tolerance
  belongs to the matching technique, never to the stored key.

  Used for `Wekui.Core.PlaceName`'s `normalized` match key and for folding
  `Wekui.Core.Place`'s free-form `type` label on write.
  """

  @doc """
  Folds a string: lowercase, Unicode NFD accent-fold (strip combining marks),
  collapse consecutive whitespace to a single space, trim.

      iex> Wekui.Normalize.fold("  La   Guaira ")
      "la guaira"

      iex> Wekui.Normalize.fold("Maiquetía")
      "maiquetia"
  """
  @spec fold(String.t()) :: String.t()
  def fold(string) when is_binary(string) do
    string
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
