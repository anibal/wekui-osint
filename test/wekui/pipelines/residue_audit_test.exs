defmodule Wekui.Pipelines.ResidueAuditTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Pipelines.ResidueAudit

  setup do
    event = event!()

    theme!(event, %{
      name: "Persona atrapada con vida bajo escombros",
      applies_when: "the post asserts a named person remains alive under rubble",
      nature: :happening
    })

    %{event: event}
  end

  defp stub(audit) do
    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => Jason.encode!(%{"audit" => audit})}}]
      })
    end)
  end

  describe "auditing what the extractor could not name" do
    test "an empty residue costs nothing and calls nobody", ctx do
      assert {:ok, %{real: [], covered: %{}}} = ResidueAudit.run(ctx.event, [])
    end

    test "an entry a theme already answers is taken off the list", ctx do
      # Measured on the record: at least six of 22 residue entries named a happening
      # the vocabulary already held. A false gap asks a person for a word they gave.
      stub([
        %{"n" => 1, "verdict" => "COVERED", "theme" => "Persona atrapada con vida bajo escombros"}
      ])

      entry = "Una madre denuncia que su hijo de 8 años está atrapado bajo escombros del Miramar."

      assert {:ok, %{real: [], covered: covered}} = ResidueAudit.run(ctx.event, [entry])
      assert covered[entry] == "Persona atrapada con vida bajo escombros"
    end

    test "a real gap survives the audit", ctx do
      stub([%{"n" => 1, "verdict" => "NONE"}])

      entry = "Se desmonta un puente de guerra para ser llevado a Caraballeda."

      assert {:ok, %{real: [^entry], covered: %{}}} = ResidueAudit.run(ctx.event, [entry])
    end
  end

  # A gap wrongly confirmed costs one person one glance. A real gap suppressed is a
  # word the record never gets, and nothing announces the loss. So every ambiguity
  # resolves toward keeping the entry.
  describe "what it refuses to suppress on" do
    test "a theme the judge invented covers nothing", ctx do
      stub([%{"n" => 1, "verdict" => "COVERED", "theme" => "Saqueo de comercios"}])

      entry = "Se reportan saqueos en La Guaira."

      # That theme is not in THIS event's vocabulary, so the verdict names nothing.
      assert {:ok, %{real: [^entry], covered: %{}}} = ResidueAudit.run(ctx.event, [entry])
    end

    test "an entry the judge did not rule on stays real, and is named as unaudited", ctx do
      stub([
        %{"n" => 1, "verdict" => "COVERED", "theme" => "Persona atrapada con vida bajo escombros"}
      ])

      first = "Una madre denuncia que su hijo está atrapado bajo escombros."
      second = "Se desmonta un puente de guerra para ser llevado a Caraballeda."

      assert {:ok, result} = ResidueAudit.run(ctx.event, [first, second])

      # Silence is not a verdict.
      assert result.real == [second]
      assert result.unaudited == [second]
    end

    test "an unreadable answer suppresses nothing", ctx do
      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "no soy JSON"}}]})
      end)

      assert {:error, {:invalid_json, _}} = ResidueAudit.run(ctx.event, ["algo"])
    end
  end
end
