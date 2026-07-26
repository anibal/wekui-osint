defmodule Wekui.Narrative.HandleTest do
  use ExUnit.Case, async: true

  alias Wekui.Narrative.Handle

  describe "derive/1 — a display handle from a full name" do
    test "first name + first-surname initial" do
      assert Handle.derive("Aaron Levi Cantillo Vargas") == {:ok, "Aaron C."}
      assert Handle.derive("Julio Josué Freitas Rodríguez") == {:ok, "Julio F."}
      assert Handle.derive("Antonio José Cabrera Meneses") == {:ok, "Antonio C."}
    end

    test "a two-token name uses the single surname" do
      assert Handle.derive("Yaneth Tejera") == {:ok, "Yaneth T."}
      assert Handle.derive("Damarys Melo") == {:ok, "Damarys M."}
    end

    test "a lone token has no handle — the escape hatch" do
      assert {:review, :too_few_tokens} = Handle.derive("Aaron")
    end

    test "a compound surname with particles goes to review" do
      assert {:review, :has_particle} = Handle.derive("María de la Cruz")
    end

    test "a non-string goes to review" do
      assert {:review, :not_a_string} = Handle.derive(nil)
    end
  end
end
