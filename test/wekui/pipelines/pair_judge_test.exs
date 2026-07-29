defmodule Wekui.Pipelines.PairJudgeTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.Duplicates
  alias Wekui.Pipelines.PairJudge

  setup do
    event = event!()

    %{
      event: event,
      agent: agent!(event),
      caribe: place!(event, %{canonical_name: "Residencias Caribe", type: "edificio"}),
      corales: place!(event, %{canonical_name: "Los Corales", type: "barrio"})
    }
  end

  defp claim!(ctx, attrs, place) do
    claim =
      Narrative.draft_claim!(
        Map.merge(
          %{
            event_id: ctx.event.id,
            kind: "rescate",
            first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
            actor_id: ctx.agent.id,
            confidence: 0.9
          },
          attrs
        )
      )

    if place do
      Narrative.link_place!(%{
        claim_id: claim.id,
        place_id: place.id,
        how_resolved: :mention_exact,
        confidence: 0.9
      })
    end

    claim
  end

  # Each reading gets its own answer, in order: the straight pass, then the swapped
  # one. The two are meant to be able to disagree — that is the whole mechanism — so a
  # stub that answers both alike could not test it.
  defp stub(readings) do
    {:ok, queue} = Agent.start_link(fn -> readings end)

    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      reading =
        Agent.get_and_update(queue, fn
          [head | rest] -> {head, rest}
          [] -> {:exhausted, []}
        end)

      case reading do
        :exhausted -> Req.Test.json(conn, %{"choices" => []})
        :unreadable -> reply(conn, "no soy JSON")
        verdicts -> reply(conn, Jason.encode!(%{"verdicts" => verdicts}))
      end
    end)
  end

  defp reply(conn, content) do
    Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
  end

  defp one_pair(ctx) do
    claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.caribe)
    claim!(ctx, %{subject: "un hombre de 21 años"}, ctx.corales)
    Duplicates.find(ctx.event.id)
  end

  describe "what the two readings decide together" do
    test "no pairs costs nothing and calls nobody" do
      assert {:ok, %{same: [], different: [], split: []}} = PairJudge.run([])
    end

    test "both readings say one happening, and the pair is upheld", ctx do
      stub([
        [%{"n" => 1, "verdict" => "SAME", "why" => "same man, same age"}],
        [%{"n" => 1, "verdict" => "SAME", "why" => "same man, same age"}]
      ])

      assert {:ok, %{same: [entry], different: [], split: []}} = PairJudge.run(one_pair(ctx))
      assert entry.verdicts == ["SAME", "SAME"]
    end

    test "both readings refuse, and the finder's proposal is withdrawn", ctx do
      stub([
        [%{"n" => 1, "verdict" => "DIFFERENT", "why" => "two buildings"}],
        [%{"n" => 1, "verdict" => "DIFFERENT", "why" => "two buildings"}]
      ])

      assert {:ok, %{same: [], different: [_entry], split: []}} = PairJudge.run(one_pair(ctx))
    end

    # A disagreement between two sceptics is the pair most worth a person's minute, so
    # it is neither upheld nor withdrawn — it stays, marked.
    test "the readings disagree, and the pair stays for a person", ctx do
      stub([
        [%{"n" => 1, "verdict" => "SAME", "why" => "same man"}],
        [%{"n" => 1, "verdict" => "DIFFERENT", "why" => "two buildings"}]
      ])

      assert {:ok, %{same: [], different: [], split: [entry]}} = PairJudge.run(one_pair(ctx))
      assert entry.verdicts == ["SAME", "DIFFERENT"]
    end

    test "the second reading sees the pair the other way round", ctx do
      {:ok, seen} = Agent.start_link(fn -> [] end)

      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Agent.update(seen, &[body | &1])
        reply(conn, Jason.encode!(%{"verdicts" => [%{"n" => 1, "verdict" => "DIFFERENT"}]}))
      end)

      pairs = one_pair(ctx)
      assert {:ok, _judged} = PairJudge.run(pairs)

      [straight, swapped] = seen |> Agent.get(& &1) |> Enum.reverse()

      # A is the earlier account in one reading and the later one in the other.
      assert straight =~ "A: rescate · un hombre de 21 años · Residencias Caribe (edificio)"
      assert swapped =~ "A: rescate · un hombre de 21 años · Los Corales (barrio)"
    end
  end

  # Two accounts of one happening left apart is a redundancy a reader can see through.
  # Two happenings merged is a person erased from the record. Every silence therefore
  # resolves toward DIFFERENT.
  describe "what silence means" do
    test "a reading that answers nothing withdraws the pair rather than upholding it", ctx do
      stub([
        [%{"n" => 1, "verdict" => "SAME", "why" => "same man"}],
        []
      ])

      assert {:ok, %{same: [], different: [], split: [entry]}} = PairJudge.run(one_pair(ctx))
      assert entry.verdicts == ["SAME", nil]
    end

    test "an unreadable answer is not an error, and upholds nothing", ctx do
      stub([:unreadable, :unreadable])

      assert {:ok, %{same: [], different: [_entry], split: []}} = PairJudge.run(one_pair(ctx))
    end

    test "with no key it does not guess", ctx do
      pairs = one_pair(ctx)
      key = Application.get_env(:wekui, :deepinfra)
      Application.put_env(:wekui, :deepinfra, Keyword.put(key || [], :api_key, nil))
      on_exit(fn -> Application.put_env(:wekui, :deepinfra, key) end)

      assert {:error, {:state_gate, :worker_not_ready}} = PairJudge.run(pairs)
    end
  end

  describe "the receipt a sweep leaves" do
    test "records what it withheld, and what it upheld", ctx do
      stub([
        [%{"n" => 1, "verdict" => "DIFFERENT", "why" => "two buildings"}],
        [%{"n" => 1, "verdict" => "DIFFERENT", "why" => "two buildings"}]
      ])

      [pair] = one_pair(ctx)

      assert {:ok, run} = PairJudge.sweep(ctx.event, ctx.agent)
      assert run.kind == :pair_judge
      assert run.status == :completed
      assert run.summary["counts"] == %{"same" => 0, "different" => 1, "split" => 0}

      two = MapSet.new([pair.claim.id, pair.other.id])
      assert MapSet.member?(PairJudge.withdrawn(ctx.event.id), two)
      refute MapSet.member?(PairJudge.upheld(ctx.event.id), two)

      # The receipt says why the queue is shorter than the finder made it.
      assert run.summary["why"]["#{pair.other.id}:#{pair.claim.id}"] =~ "two buildings"
    end

    # A machine may withdraw a machine's proposal. It may never merge — that is a
    # curation act, and Wekui.Curation refuses an agent as curator outright.
    test "it moves no claim", ctx do
      stub([
        [%{"n" => 1, "verdict" => "SAME", "why" => "same man"}],
        [%{"n" => 1, "verdict" => "SAME", "why" => "same man"}]
      ])

      [pair] = one_pair(ctx)
      assert {:ok, _run} = PairJudge.sweep(ctx.event, ctx.agent)

      assert {:ok, claim} = Narrative.get_claim(pair.claim.id)
      assert is_nil(claim.superseded_by_id)
      assert length(Narrative.current_claims!(ctx.event.id)) == 2
    end
  end
end
