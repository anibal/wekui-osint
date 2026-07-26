defmodule Wekui.Pipelines.Extract do
  @moduledoc """
  The claim-extraction pipeline: a batch of accepted [[post]]s (a place × window) in,
  structured [[claim]]s out. It renders the extractor Actor(agent)'s pinned prompt for
  the batch, calls the inference `Wekui.Clients.Worker`, parses the claims JSON, and
  writes each claim with its evidence and the [[person]]s it names — the agent authors
  every claim, and the person red line gates every write.

  Posts are cited by their `x_id` (the id shown to the model); a claim that cites
  nothing in the batch, or whose subject slips a private name past the gate, is skipped
  and counted. Best-effort per claim — a first end-to-end wiring, not yet a Run receipt.
  """

  alias Wekui.Clients.Worker
  alias Wekui.Narrative

  @doc """
  Extracts claims from `posts` (a batch of Posts) using `agent` (the extractor,
  whose `prompt` is the pinned template and whose `model` drives the worker), and
  writes them for `event`. `opts`: `:place_scope`, `:t_start`, `:t_end`, `:prior`.

  Returns `{:ok, %{claims:, drafted:, skipped:, skips:}}`, or `{:error, reason}` when
  the worker is unready, unreachable, or its output does not parse.
  """
  def run(event, agent, posts, opts \\ []) do
    if Worker.ready?() do
      with rendered <- render(event, agent, posts, opts),
           {:ok, %{content: content}} <- Worker.complete(rendered, model: agent.model),
           {:ok, claims} <- parse(content) do
        by_xid = Map.new(posts, &{to_string(&1.x_id), &1})
        {:ok, summarize(Enum.map(claims, &write_claim(event, agent, &1, by_xid)))}
      end
    else
      {:error, {:state_gate, :worker_not_ready}}
    end
  end

  defp render(event, agent, posts, opts) do
    material =
      Enum.map_join(posts, "\n", fn p ->
        "[id #{p.x_id}] #{DateTime.to_iso8601(p.posted_at)} — #{p.text}"
      end)

    agent.prompt
    |> String.replace("{{event_name}}", event.name)
    |> String.replace("{{t0}}", DateTime.to_iso8601(event.t0))
    |> String.replace("{{place_scope}}", Keyword.get(opts, :place_scope, "the event"))
    |> String.replace("{{t_start}}", iso(Keyword.get(opts, :t_start)))
    |> String.replace("{{t_end}}", iso(Keyword.get(opts, :t_end)))
    |> String.replace("{{prior}}", Keyword.get(opts, :prior, "(ninguno)"))
    |> String.replace("{{material}}", material)
  end

  defp iso(nil), do: ""
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse(content) do
    case content |> strip_fence() |> Jason.decode() do
      {:ok, %{"claims" => claims}} when is_list(claims) -> {:ok, claims}
      {:ok, _no_claims_key} -> {:error, :no_claims}
      {:error, error} -> {:error, {:invalid_json, error}}
    end
  end

  # Models sometimes wrap the JSON in a ```json fence despite the instruction not to.
  defp strip_fence(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
  end

  defp write_claim(event, agent, claim, by_xid) do
    posts =
      (claim["citations"] || [])
      |> Enum.map(&Map.get(by_xid, to_string(&1)))
      |> Enum.reject(&is_nil/1)

    case posts do
      [] ->
        {:skip, :no_valid_citations}

      [first | _rest] ->
        attrs = %{
          event_id: event.id,
          kind: to_string(claim["kind"] || "otro"),
          subject: claim["subject_role"],
          magnitude: claim["magnitude"],
          place_mention: claim["place_mention"],
          status: claim["status"],
          first_seen_at: first.posted_at,
          actor_id: agent.id,
          confidence: confidence(claim["confidence"])
        }

        case Narrative.draft_claim(attrs) do
          {:ok, drafted} ->
            Enum.each(posts, &Narrative.cite_post!(%{claim_id: drafted.id, post_id: &1.id}))
            link_persons(event, drafted, claim["names"] || [])
            {:ok, drafted}

          {:error, error} ->
            {:skip, {:rejected, error}}
        end
    end
  end

  defp link_persons(event, claim, names) do
    for name <- names, is_binary(name) and String.trim(name) != "" do
      person = Narrative.identify_person!(%{event_id: event.id, full_name: name})
      Narrative.link_person!(%{claim_id: claim.id, person_id: person.id})
    end
  end

  defp confidence(n) when is_number(n), do: n * 1.0

  defp confidence(s) when is_binary(s) do
    case Float.parse(s) do
      {float, _rest} -> float
      :error -> nil
    end
  end

  defp confidence(_absent), do: nil

  defp summarize(results) do
    %{
      claims: length(results),
      drafted: Enum.count(results, &match?({:ok, _}, &1)),
      skipped: Enum.count(results, &match?({:skip, _}, &1)),
      skips: for({:skip, reason} <- results, do: reason)
    }
  end
end
