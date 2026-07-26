defmodule Wekui.Narrative.PersonTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative

  setup do
    %{event: event!()}
  end

  describe "identify — recognizing a person by name" do
    test "creates a person: name held, handle derived, private and pending", ctx do
      p =
        Narrative.identify_person!(%{
          event_id: ctx.event.id,
          full_name: "Aaron Levi Cantillo Vargas"
        })

      assert p.full_name == "Aaron Levi Cantillo Vargas"
      assert p.display_handle == "Aaron C."
      assert p.kind == :private
      assert p.status == :pending_review
    end

    test "the same name is the same person, however cased or spaced", ctx do
      a = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Damarys Melo"})
      b = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "DAMARYS  MELO"})

      assert a.id == b.id
      assert length(Narrative.list_persons!(ctx.event.id)) == 1
    end

    test "different names are different people", ctx do
      a = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Yaneth Tejera"})
      b = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Shaznay Mirabal"})
      refute a.id == b.id
    end

    test "the same name in another Event is another person", ctx do
      other = event!()
      a = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "Damarys Melo"})
      b = Narrative.identify_person!(%{event_id: other.id, full_name: "Damarys Melo"})
      refute a.id == b.id
    end

    test "a name that cannot be read leaves the handle for a human", ctx do
      p = Narrative.identify_person!(%{event_id: ctx.event.id, full_name: "María de la Cruz"})
      assert p.display_handle == nil
      assert p.status == :pending_review
    end
  end

  describe "the human gate" do
    setup ctx do
      %{
        person:
          Narrative.identify_person!(%{
            event_id: ctx.event.id,
            full_name: "Aaron Levi Cantillo Vargas"
          })
      }
    end

    test "approve marks the person shown", ctx do
      assert Narrative.approve_person!(ctx.person).status == :approved
    end

    test "withhold holds the person back", ctx do
      assert Narrative.withhold_person!(ctx.person).status == :withheld
    end

    test "a human can assign a handle and mark the person public", ctx do
      assert Narrative.set_person_handle!(ctx.person, %{display_handle: "Aaron C.V."}).display_handle ==
               "Aaron C.V."

      assert Narrative.set_person_kind!(ctx.person, %{kind: :public}).kind == :public
    end
  end
end
