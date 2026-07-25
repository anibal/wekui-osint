defmodule Wekui.Narrative.PrivateNamesTest do
  use ExUnit.Case, async: true

  alias Wekui.Narrative.PrivateNames

  describe "unexplained/2 — the persons red line, mechanically" do
    test "a role descriptor names no one" do
      assert PrivateNames.unexplained("un hombre de 21 años", []) == []
      assert PrivateNames.unexplained("una mujer de 60 años y sus dos hijos", []) == []
    end

    test "nil text is clean" do
      assert PrivateNames.unexplained(nil, []) == []
    end

    test "a private full name is flagged, even against an empty vocabulary" do
      assert PrivateNames.unexplained("Belkys Josefina Barreto García", []) ==
               ["Belkys Josefina Barreto García"]
    end

    test "a building is a place, not a person (institution word)" do
      assert PrivateNames.unexplained("rescatada del Edificio Breogán", []) == []
    end

    test "a rescue brigade is an institution, not a person" do
      assert PrivateNames.unexplained("USAR de El Salvador", []) == []
      assert PrivateNames.unexplained("Topos de México", []) == []
    end

    test "a public figure is flagged without the allowlist, clean with it" do
      assert PrivateNames.unexplained("Nicolás Maduro", []) == ["Nicolás Maduro"]
      assert PrivateNames.unexplained("Nicolás Maduro", ["nicolas maduro"]) == []
    end

    test "a gazetteer name explains a place the institution words would miss" do
      assert PrivateNames.unexplained("colapsó Roca Park", []) == ["Roca Park"]
      assert PrivateNames.unexplained("colapsó Roca Park", ["roca park"]) == []
    end
  end
end
