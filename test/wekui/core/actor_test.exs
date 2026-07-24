defmodule Wekui.Core.ActorTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core

  setup do
    %{event: event!(), other_event: event!()}
  end

  defp sha256(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  describe "register_agent" do
    test "records an agent that belongs to its Event, driven by a model and a prompt", %{
      event: event
    } do
      agent =
        agent!(event, %{model: "deepseek-ai/DeepSeek-V4", prompt: "¿de qué trata el mensaje?"})

      assert agent.kind == :agent
      assert agent.event_id == event.id
      assert agent.model == "deepseek-ai/DeepSeek-V4"
      assert agent.prompt == "¿de qué trata el mensaje?"

      {:ok, loaded} = Core.get_actor(agent.id, load: [:event])
      assert loaded.event.id == event.id
    end

    test "content_hash is the SHA-256 of the prompt, derived on write", %{event: event} do
      agent = agent!(event, %{prompt: "clasifica el lugar"})

      assert agent.content_hash == sha256("clasifica el lugar")
    end

    test "a caller cannot supply content_hash — it is derived, not an input", %{event: event} do
      assert_raise Ash.Error.Invalid, fn ->
        Core.register_agent!(%{
          event_id: event.id,
          model: "m",
          prompt: "p",
          content_hash: "deadbeef"
        })
      end
    end
  end

  describe "identity — same model and prompt are the same agent" do
    test "re-registering returns the one we already hold, and only that one", %{event: event} do
      first = agent!(event, %{model: "m", prompt: "p"})
      second = agent!(event, %{model: "m", prompt: "p"})

      assert second.id == first.id
      assert second.inserted_at == first.inserted_at

      assert {:ok, [only]} = Core.list_actors(event.id)
      assert only.id == first.id
    end

    test "a different prompt, same model, is a different agent", %{event: event} do
      one = agent!(event, %{model: "m", prompt: "p1"})
      two = agent!(event, %{model: "m", prompt: "p2"})

      refute one.id == two.id
      assert {:ok, actors} = Core.list_actors(event.id)
      assert length(actors) == 2
    end

    test "the same prompt under a different model is a different agent", %{event: event} do
      flash = agent!(event, %{model: "deepseek-ai/DeepSeek-V4-Flash", prompt: "p"})
      full = agent!(event, %{model: "deepseek-ai/DeepSeek-V4", prompt: "p"})

      refute flash.id == full.id
      assert flash.content_hash == full.content_hash
      assert {:ok, actors} = Core.list_actors(event.id)
      assert length(actors) == 2
    end
  end

  describe "event scope" do
    test "the same model and prompt in two Events are two distinct Actors", %{
      event: event,
      other_event: other
    } do
      here = agent!(event, %{model: "m", prompt: "p"})
      there = agent!(other, %{model: "m", prompt: "p"})

      refute here.id == there.id
      assert here.event_id == event.id
      assert there.event_id == other.id
    end
  end

  describe "requirements" do
    for field <- [:event_id, :model, :prompt] do
      test "requires #{field}", %{event: event} do
        attrs =
          Map.delete(%{event_id: event.id, model: "m", prompt: "p"}, unquote(field))

        assert {:error, %Ash.Error.Invalid{}} = Core.register_agent(attrs)
      end
    end
  end

  describe "reads" do
    test "by_event returns an Event's Actors oldest first", %{event: event} do
      first = agent!(event, %{prompt: "p1"})
      second = agent!(event, %{prompt: "p2"})
      third = agent!(event, %{prompt: "p3"})

      {:ok, actors} = Core.list_actors(event.id)

      assert Enum.map(actors, & &1.id) == [first.id, second.id, third.id]
    end

    test "by_event excludes another Event's Actors", %{event: event, other_event: other} do
      here = agent!(event, %{prompt: "p"})
      _there = agent!(other, %{prompt: "p"})

      {:ok, actors} = Core.list_actors(event.id)

      assert Enum.map(actors, & &1.id) == [here.id]
    end
  end
end
