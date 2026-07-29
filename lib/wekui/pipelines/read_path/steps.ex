defmodule Wekui.Pipelines.ReadPath.Steps do
  @moduledoc """
  The work each `Wekui.Pipelines.ReadPath` step does — plain functions over the
  already-built capabilities, so the Reactor holds the *order* and nothing else.

  Two rules run through all of them, both from `docs/orchestration-scenarios.md`:

    * **A stage absorbs its own errors.** Anything a stage can catch — a worker
      that would not answer, output that would not parse — becomes data in the
      summary and the run still finalizes. A completed run with errors in its
      summary is an honest receipt; only preflight refuses, and only a raise
      leaves a receipt stranded `:running`.
    * **Everything a step returns is JSON-shaped**, string-keyed scalars and
      lists. It lands in a `:map` column and must read back identically.
  """

  alias Wekui.Capture
  alias Wekui.Clients.Worker
  alias Wekui.Core
  alias Wekui.Narrative
  alias Wekui.Narrative.BeatRenderer
  alias Wekui.Narrative.PlaceResolver
  alias Wekui.Pipelines
  alias Wekui.Pipelines.Extract
  alias Wekui.Pipelines.Verify

  @flagged [:overstated, :unsupported]

  ## ─────────────────────────── preflight ───────────────────────────

  @doc """
  Refuses before anything is written: the worker must be able to answer, the
  target Place must be this Event's, the Event must have an active gazetteer, and
  there must be posts in scope. A run that never ran is not a record of the system
  acting, so a refusal opens no receipt.

  The seed is deliberately NOT auto-run here: seeding is an explicit act, not a
  side effect of asking for a beat.
  """
  def preflight(%{event: event, place_id: place_id, opts: opts}, _context) do
    with :ok <- worker_ready(),
         {:ok, place} <- target_place(event, place_id),
         {:ok, active} <- active_gazetteer(event),
         {:ok, posts} <- posts_in_scope(event, opts) do
      {:ok, %{place: place, posts: posts, active_places: active}}
    end
  end

  defp worker_ready do
    if Worker.ready?(), do: :ok, else: {:error, {:preflight, :worker_not_ready}}
  end

  defp target_place(event, place_id) do
    case Ash.get(Core.Place, place_id, authorize?: false) do
      {:ok, %{event_id: event_id} = place} when event_id == event.id -> {:ok, place}
      {:ok, _elsewhere} -> {:error, {:preflight, :place_not_in_event}}
      {:error, _not_found} -> {:error, {:preflight, :place_not_found}}
    end
  end

  # Stub-versus-real cannot be told apart from the data; this only catches the
  # forgot-to-seed case, which is task 0's responsibility, not preflight's. The
  # Unplaced Place does not count: every Event is born with one, active, so
  # counting it would make this guard always pass.
  defp active_gazetteer(event) do
    gazetteer =
      event.id
      |> Core.list_active_places!()
      |> Enum.reject(&(&1.id == event.unplaced_place_id))

    case length(gazetteer) do
      0 -> {:error, {:preflight, :no_active_gazetteer}}
      active -> {:ok, active}
    end
  end

  # The whole corpus of the Event, oldest first — the beat's own interval does the
  # scoping, so a claim is never lost because it fell outside a render window.
  # `posts:` overrides it for a scripted run.
  defp posts_in_scope(event, opts) do
    case Keyword.get(opts, :posts) || Capture.list_posts!(event.id) do
      [] -> {:error, {:preflight, :no_posts_in_scope}}
      posts -> {:ok, Enum.sort_by(posts, & &1.posted_at, DateTime)}
    end
  end

  ## ─────────────────────────── the receipt ───────────────────────────

  @doc "Opens the receipt, stamping the exact ask — including which agent was named."
  def start_run(arguments, _context) do
    %{event: event, agent: agent, place_id: place_id, from: from, to: to} = arguments
    %{opts: opts, preflight: preflight} = arguments

    options = %{
      "place_id" => place_id,
      "place_name" => preflight.place.canonical_name,
      "from" => iso(from),
      "to" => iso(to),
      "agent_id" => agent.id,
      "agent_model" => agent.model,
      "posts_in_scope" => length(preflight.posts),
      "extract" => to_string(Keyword.get(opts, :extract, :auto)),
      "verify" => to_string(Keyword.get(opts, :verify, :all))
    }

    {:ok,
     Pipelines.start_run!(%{
       event_id: event.id,
       actor_id: agent.id,
       kind: :read_path,
       options: options
     })}
  end

  ## ─────────────────────────── extract ───────────────────────────

  @doc """
  Posts → claims, through the extractor agent's pinned prompt.

  `Claim.:draft` has no identity, so re-extracting the same posts mints duplicate
  claims — the one hazard on this path (everything else re-passes safely: resolve
  upserts, verify overwrites its verdict). Until the merge-judge lands the rule is
  binary and stated in the receipt: an Event with **no** current claim extracts;
  an Event that already holds one **skips** extract and re-passes the rest, unless
  asked with `extract: :force`. A crash that drafted only part of a batch therefore
  never gets silently patched — recovery is to retract the partials, then force.

  Post-level skipping was considered and rejected: it re-feeds the no-claim posts
  on every run (a non-deterministic-model ratchet toward minting claims from noise
  that v5 correctly dropped), it turns `{{material}}` into partial batches the
  prompt was never proven on, and it resurrects deliberately retracted accounts.
  """
  def extract(%{event: event, agent: agent, opts: opts, preflight: preflight}, _context) do
    posts = preflight.posts
    current = Narrative.current_claims!(event.id)

    if current != [] and Keyword.get(opts, :extract) != :force do
      {:ok,
       %{
         "ran" => false,
         "reason" => "claims_exist",
         "current_claims" => length(current),
         "posts" => length(posts)
       }}
    else
      {:ok, drafted(event, agent, posts, preflight.place, opts)}
    end
  end

  defp drafted(event, agent, posts, place, opts) do
    stamps = Enum.map(posts, & &1.posted_at)

    extract_opts = [
      place_scope: place.canonical_name,
      t_start: Enum.min(stamps, DateTime),
      # The prompt states a half-open interval, so the last post must fall inside it.
      t_end: stamps |> Enum.max(DateTime) |> DateTime.add(1, :second),
      prior: Keyword.get(opts, :prior, "(ninguno)")
    ]

    case Extract.run(event, agent, posts, extract_opts) do
      {:ok, summary} ->
        # EVERY POST ACCOUNTED FOR, IN THE RECEIPT. `Extract` computes the split —
        # cited, routed to a topic, reported unfitted, or read and dropped — and this
        # step used to keep four keys of it and discard the rest. A conservation law
        # that does not reach the receipt is not auditable, which was the whole point
        # of computing it (`docs/mechanisms.md`).
        #
        # `unfitted` matters most: it is the corpus asking for a word the vocabulary
        # does not have, and it is how three themes were proposed without anybody
        # writing them from a desk.
        %{
          "ran" => true,
          "posts" => summary.posts,
          "claims" => summary.claims,
          "drafted" => summary.drafted,
          "skipped" => summary.skipped,
          "skips" => Enum.map(summary.skips, &reason/1),
          "cited" => summary.cited,
          "unread" => summary.unread,
          "topics" => summary.topics,
          # A happening named in the topics list is a claim that got away.
          "misrouted_topics" => summary.misrouted_topics,
          # A topic the model put in "theme" — routed correctly anyway, and counted so
          # the slip stays visible.
          "routed_from_theme" => summary.routed_from_theme,
          "judged" => summary.judged,
          "unfitted" => summary.unfitted
        }

      {:error, error} ->
        %{"ran" => true, "posts" => length(posts), "error" => reason(error)}
    end
  end

  ## ─────────────────────────── resolve ───────────────────────────

  @doc """
  Re-passes every current claim's `place_mention` against the event's active
  gazetteer. Safe to repeat — ClaimPlace upserts and a proposal is reused — and
  this is where the run CAPTURES the resolver counts the extract stage discards.

  Event-wide by design: it is a snapshot of the current claims at run time, not a
  delta of the batch extract just fed.
  """
  def resolve(%{event: event, agent: agent}, _context) do
    claims = Narrative.current_claims!(event.id)

    zero = %{mentions: 0, linked: 0, proposed: 0, unresolved: [], settled: 0}

    counts =
      Enum.reduce(claims, zero, fn claim, acc ->
        {:ok, summary} =
          PlaceResolver.resolve(claim, actor_id: agent.id, post_id: first_post_id(claim))

        %{
          mentions: acc.mentions + summary.mentions,
          linked: acc.linked + summary.linked,
          proposed: acc.proposed + summary.proposed,
          unresolved: acc.unresolved ++ summary.unresolved,
          settled: acc.settled + summary.settled
        }
      end)

    {:ok,
     %{
       "claims" => length(claims),
       "mentions" => counts.mentions,
       "linked" => counts.linked,
       "proposed" => counts.proposed,
       "unresolved" => counts.unresolved,
       # Claims a person placed by hand, which this pass deliberately did not touch.
       # Without this the receipt would read as though the resolver had done the work.
       "settled" => counts.settled
     }}
  end

  # The provenance stamped on any Place the resolver proposes: the claim's first
  # cited post, the same one the extract stage would have passed.
  defp first_post_id(claim) do
    case Narrative.list_claim_citations!(claim.id) do
      [first | _rest] -> first.post_id
      [] -> nil
    end
  end

  ## ─────────────────────────── verify ───────────────────────────

  @doc """
  The support gate over every current claim — flag-only, withholding nothing.
  Safe to repeat: a second pass overwrites the same claim's verdict. `verify:
  :skip_verdicted` spares the already-judged ones for cost and churn; the default
  re-judges all, and the MoE judge may honestly flip a verdict between runs.

  The verdict tally is taken over ALL current claims after the pass — the state as
  it now stands — while `judged` and `skipped` say what this run actually did.
  """
  def verify(%{event: event, opts: opts}, _context) do
    claims = Narrative.current_claims!(event.id)

    {judge, skip} =
      if Keyword.get(opts, :verify) == :skip_verdicted,
        do: Enum.split_with(claims, &(&1.support == :unverified)),
        else: {claims, []}

    errors = judge |> Enum.map(&Verify.run/1) |> Enum.flat_map(&error_reason/1)
    tally = event.id |> Narrative.current_claims!() |> Enum.frequencies_by(& &1.support)

    {:ok,
     %{
       "claims" => length(claims),
       "judged" => length(judge),
       "skipped" => length(skip),
       "supported" => Map.get(tally, :supported, 0),
       "overstated" => Map.get(tally, :overstated, 0),
       "unsupported" => Map.get(tally, :unsupported, 0),
       "unverified" => Map.get(tally, :unverified, 0),
       "errors" => length(errors),
       "error_reasons" => Enum.uniq(errors)
     }}
  end

  defp error_reason({:ok, _claim}), do: []
  defp error_reason({:error, error}), do: [reason(error)]

  ## ─────────────────────────── render ───────────────────────────

  @doc """
  The beat for the asked Place and interval. Read-only and re-derivable: what the
  receipt keeps is a copy for provenance, never the canonical story.
  """
  def render(%{place_id: place_id, from: from, to: to}, _context) do
    beat = BeatRenderer.render(place_id, from, to)

    {:ok,
     %{
       "place_id" => beat.place.id,
       "place_name" => beat.place.canonical_name,
       "clauses" => length(beat.clauses),
       "sources" => length(beat.sources),
       "prose" => beat.prose,
       "citations" =>
         Enum.map(beat.sources, &%{"n" => &1.n, "x_id" => &1.x_id, "post_id" => &1.post_id})
     }}
  end

  ## ─────────────────────────── finalize ───────────────────────────

  @doc """
  Closes the receipt with the per-stage summary, the gate queues it surfaced, and
  the beat it produced. The queues are a snapshot for inspection — the statuses on
  the resources themselves stay the source of truth, and a later review services
  them there.
  """
  def finalize(arguments, _context) do
    %{run: run, event: event, extract: extract, resolve: resolve} = arguments
    %{verify: verify, render: render} = arguments

    summary = %{
      "extract" => extract,
      "resolve" => resolve,
      "verify" => verify,
      "render" => Map.take(render, ["place_id", "place_name", "clauses", "sources"]),
      "gates" => gates(event),
      "beat" => %{"prose" => render["prose"], "sources" => render["citations"]}
    }

    {:ok, Pipelines.finalize_run!(run, %{summary: summary})}
  end

  defp gates(event) do
    persons =
      event.id |> Narrative.list_persons!() |> Enum.filter(&(&1.status == :pending_review))

    places = event.id |> Core.list_places!() |> Enum.filter(&(&1.lifecycle == :proposed))
    claims = event.id |> Narrative.current_claims!() |> Enum.filter(&(&1.support in @flagged))

    %{
      "persons_pending_review" => queue(persons),
      "places_proposed" => queue(places),
      "claims_not_supported" => queue(claims)
    }
  end

  defp queue(records), do: %{"count" => length(records), "ids" => Enum.map(records, & &1.id)}

  ## ─────────────────────────── shared ───────────────────────────

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  # A reason has to survive a JSON round-trip and still be readable in a receipt.
  defp reason(atom) when is_atom(atom), do: to_string(atom)
  defp reason({:rejected, error}), do: "rejected: " <> short(Exception.message(error))
  defp reason({tag, detail}) when is_atom(tag), do: "#{tag}: #{short(inspect(detail))}"
  defp reason(other), do: short(inspect(other))

  defp short(message) do
    message |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 200)
  end
end
