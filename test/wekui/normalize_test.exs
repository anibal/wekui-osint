defmodule Wekui.NormalizeTest do
  use ExUnit.Case, async: true

  doctest Wekui.Normalize

  alias Wekui.Normalize

  test "folds case, accents, and surrounding and repeated whitespace" do
    assert Normalize.fold("Parroquia  CARABALLEDA ") == "parroquia caraballeda"
    assert Normalize.fold("Maiquetía") == Normalize.fold("MAIQUETIA")
  end

  test "keeps everything that distinguishes one name from another" do
    assert Normalize.fold("Las Quince Letras") == "las quince letras"
    assert Normalize.fold("Res. Playa Humboldt III") == "res. playa humboldt iii"
    assert Normalize.fold("Caracas 1050") == "caracas 1050"
  end

  test "is idempotent" do
    folded = Normalize.fold("  El Ávila  ")

    assert Normalize.fold(folded) == folded
  end
end
