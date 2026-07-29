defmodule Wekui.Pipelines.Extract do
  @moduledoc """
  The claim-extraction pipeline: a batch of accepted [[post]]s (a place × window) in,
  structured [[claim]]s out. It renders the extractor Actor(agent)'s pinned prompt for
  the batch, calls the inference `Wekui.Clients.Worker`, parses the claims JSON, and
  writes each claim with its evidence, the [[person]]s it names, and the gazetteer
  [[place]]s its `place_mention` resolves to (`Wekui.Narrative.PlaceResolver`) — the
  agent authors every claim, and the person red line gates every write.

  Posts are cited by their `x_id` (the id shown to the model); a claim that cites
  nothing in the batch, or whose subject slips a private name past the gate, is skipped
  and counted. Best-effort per claim — a first end-to-end wiring, not yet a Run receipt.
  """

  alias Wekui.Clients.Worker
  alias Wekui.Judgment
  alias Wekui.Narrative
  alias Wekui.Narrative.PlaceResolver
  alias Wekui.Narrative.ThemeResolver
  alias Wekui.Normalize
  alias Wekui.Taxonomy

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
           {:ok, claims, unfitted, topics} <- parse(content) do
        by_xid = Map.new(posts, &{to_string(&1.x_id), &1})
        written = Enum.map(claims, &write_claim(event, agent, &1, by_xid))
        judged = judge_topics(event, agent, written, topics, by_xid)
        silent = judge_silence(event, agent, written, topics, posts, by_xid)
        {:ok, summarize(written, unfitted, topics, posts, by_xid, judged + silent)}
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
    |> String.replace("{{vocabulary}}", vocabulary(event))
    |> String.replace("{{material}}", material)
  end

  # The ratified vocabulary, rendered for the model: what it may say happened, and what
  # it may NOT turn into a claim. The rule matters more than the name — a name alone
  # does not stop a reader stretching it over evidence that does not bear it — so each
  # theme carries its `applies_when` verbatim.
  #
  # The TOPICS are here for the refusal they make possible — naming a plea AS a plea is
  # what stops the model reaching for the nearest happening. They are rendered as a
  # SEPARATE, explicitly unselectable list: v8 showed them in the same shape as the
  # happenings and the model duly filed ten claims under `Solicitud de información`,
  # which the write path then refused. An answer list must not contain answers that are
  # not allowed.
  @doc """
  The ratified vocabulary as the model receives it — grouped by family, happenings
  and topics apart. Public because the residue audit must judge against EXACTLY the
  list the extractor was given; two renderings of one vocabulary is two vocabularies.
  """
  def vocabulary(event) do
    active = Taxonomy.list_active_themes!(event.id)
    {happenings, topics} = Enum.split_with(active, &(&1.nature == :happening))

    """
    HAPPENINGS — the ONLY names that may appear in a claim's "theme":
    #{grouped(happenings, active)}

    TOPICS — these are NOT claims and must never appear in "theme". A post that is only
    doing one of these belongs in "topics", where naming it is a complete answer:
    #{grouped(topics, active)}
    """
  end

  # GROUPED BY FAMILY, not a flat list. At 17 themes a flat list was fine; at 40 the
  # model stopped finding words that were plainly there — "Rescatistas confirmaron que
  # no había sobrevivientes" went to `unfitted` while «Búsqueda sin señales de vida»
  # sat in the list, and about ten of twenty-six residue entries were that shape.
  #
  # A residue entry the vocabulary can already answer is worse than a gap: it asks a
  # person for a word that exists. So the tree the operator insisted on is used to
  # break the list into families a reader can scan, with the hub as the heading it was
  # always meant to be.
  defp grouped(themes, active) do
    by_id = Map.new(active, &{&1.id, &1})

    themes
    |> Enum.group_by(&(&1.parent_id && by_id[&1.parent_id] && by_id[&1.parent_id].name))
    |> Enum.sort_by(fn {family, _} -> {is_nil(family), family} end)
    |> Enum.map_join("\n\n", fn
      {nil, loose} -> lines(loose)
      {family, kin} -> "  #{String.upcase(family)}\n#{lines(kin)}"
    end)
  end

  defp lines(themes) do
    themes
    |> Enum.sort_by(& &1.name)
    |> Enum.map_join("\n", fn theme ->
      "- «#{theme.name}» — applies when: #{theme.applies_when}"
    end)
  end

  defp iso(nil), do: ""
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse(content) do
    case content |> strip_fence() |> Jason.decode() do
      {:ok, %{"claims" => claims} = answer} when is_list(claims) ->
        {:ok, claims, List.wrap(answer["unfitted"]), List.wrap(answer["topics"])}

      {:ok, _no_claims_key} ->
        {:error, :no_claims}

      {:error, error} ->
        {:error, {:invalid_json, error}}
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
      |> Enum.map(&cited_post(by_xid, &1))
      |> Enum.reject(&is_nil/1)

    case posts do
      [] ->
        # WHAT it cited, not just that nothing matched. Seen twice: a whole batch of
        # 21 claims refused this way, and the reason column could only say
        # `:no_valid_citations` — true, useless, and the same shape as a model that
        # has stopped reading the material at all.
        {:skip, {:no_valid_citations, Enum.map(List.wrap(claim["citations"]), &to_string/1)}}

      [first | _rest] ->
        write_filed(event, agent, claim, posts, first)
    end
  end

  # A NAME THE MODEL ITSELF DECLARED IS REMOVED FROM THE ROLE, not left to refuse the
  # claim. The F54 gate refuses a `subject` naming a private individual, correctly and
  # absolutely — and that was costing 2–3% of every batch: the whole happening left the
  # record because one field carried a word that belonged in the next field along.
  #
  # This only removes what the model put in "names" itself. It is not a scrub of
  # anything that looks like a name; it is a repair of a field the model filled twice.
  # Nothing is lost to a reader: names live on the [[person]] behind the handle gate,
  # and the beat renders the handle. What is left is the role — "un hombre de 21 años"
  # — which is what the field was always for.
  #
  # If nothing survives, the subject is simply absent, which the record allows and
  # which is far better than losing the happening.
  defp without_declared_names(claim) do
    names = claim["names"] |> List.wrap() |> Enum.filter(&is_binary/1)

    case claim["subject_role"] do
      role when is_binary(role) and names != [] ->
        names
        |> Enum.sort_by(&(-String.length(&1)))
        |> Enum.reduce(role, &String.replace(&2, &1, ""))
        |> String.replace(~r/\s*[,;]\s*[,;]+/u, ",")
        |> String.trim()
        |> String.trim(",")
        |> String.trim()
        |> case do
          "" -> nil
          cleaned -> cleaned
        end

      role ->
        role
    end
  end

  # The material renders a post as `[id 2071059613336949047] …`, and the model copies
  # the id WITH ITS LABEL: "id 2071059613336949047". An exact lookup misses, the claim
  # cites nothing, and it is dropped — two whole batches went that way, about fifty
  # claims, before the skip reason said what had actually been cited.
  #
  # "Spell out output hygiene and don't trust it — the parser must be lenient
  # regardless" (`.claude/skills/prompt-craft`). So the label is stripped, and a last
  # resort keeps only the digits.
  defp cited_post(by_xid, id) do
    raw = id |> to_string() |> String.trim()

    [raw, String.replace(raw, ~r/^#?\s*id[:\s]+/i, ""), String.replace(raw, ~r/\D/, "")]
    |> Enum.find_value(&Map.get(by_xid, &1))
  end

  # NO THEME, NO CLAIM. A happening the vocabulary cannot name does not become a claim
  # that says nothing and reaches nobody — it belongs in `unfitted`, where a person
  # decides whether the vocabulary should grow.
  #
  # This also closes a leak by construction: an unfiled claim was still storing the
  # model's free prose, and free prose about this corpus contains private names.
  defp write_filed(event, agent, claim, posts, first) do
    case classify(event, claim) do
      # A TOPIC name in "theme" is not a mistake worth losing a post over. The model
      # recognised the post as that topic and put the answer in the wrong field —
      # unambiguous intent, so route it rather than refuse it.
      #
      # Measured: on 2026-06-28, a batch dominated by resource requests, the model put
      # a topic in "theme" eight times out of twenty-four. v9's rule holds on a mixed
      # batch and slips on a lopsided one, so the pipeline has to be forgiving of a
      # known, unambiguous error — and count it, or the slip is invisible.
      # The posts come with it. An earlier version returned only the name and threw
      # the citations away, so a topic that arrived through the wrong field left no
      # judgment and no accounting — and the sweep read those posts again on the next
      # pass, and the one after that.
      {:topic, name} ->
        {:routed, name, posts}

      :none ->
        {:skip, {:no_theme, to_string(claim["theme"] || "")}}

      {:happening, theme_id} ->
        attrs = %{
          event_id: event.id,
          theme_id: theme_id,
          kind: to_string(claim["kind"] || "otro"),
          subject: without_declared_names(claim),
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
            PlaceResolver.resolve(drafted, actor_id: agent.id, post_id: first.id)
            {:ok, drafted}

          {:error, error} ->
            {:skip, {:rejected, error}}
        end
    end
  end

  # The model chose from a CLOSED list, so the name is matched exactly (folded). The
  # fuzzy resolver is the fallback for a model that answered off-list or for a legacy
  # claim, and it refuses far more than it accepts — by design
  # (`Wekui.Narrative.ThemeResolver`).
  defp classify(event, claim) do
    named = Normalize.fold(to_string(claim["theme"] || ""))
    active = Taxonomy.list_active_themes!(event.id)

    case Enum.find(active, &(Normalize.fold(&1.name) == named)) do
      %{nature: :happening} = theme -> {:happening, theme.id}
      %{nature: :topic} = theme -> {:topic, theme.name}
      nil -> fallback(event, claim["kind"])
    end
  end

  defp fallback(event, kind) do
    case ThemeResolver.resolve(event.id, to_string(kind || "")) do
      {:ok, theme} -> {:happening, theme.id}
      :no_theme -> :none
    end
  end

  # A POST ROUTED TO A TOPIC LEAVES A RECORD. Until now it left none: the routing
  # existed only inside a run summary, so the record could not say what became of a
  # post that was read and correctly produced no claim. "Every post is accounted for"
  # was true per run and lost immediately after — which is not accounted for.
  #
  # `Wekui.Judgment.ThemeJudgment` has modelled exactly this since before the
  # vocabulary existed: an Actor's answer to *what is this Post about*, append-only,
  # superseding, with a partial-unique slot on (post, theme). It had zero rows.
  #
  # `judge_set` replaces a post's whole set in one step, so the current answer always
  # reads as one coherent judgement from one Actor rather than an accretion.
  defp judge_topics(event, agent, written, topics, by_xid) do
    from_topics =
      Enum.flat_map(topics, fn entry ->
        case active_topic(event, entry["topic"]) do
          nil ->
            []

          theme ->
            for id <- List.wrap(entry["citations"]),
                post = by_xid[to_string(id)],
                do: {post, theme}
        end
      end)

    # A topic that arrived through the wrong field brings its POSTS with it. Keeping
    # only the name left those posts with no judgment and no accounting, so every
    # sweep read them again, and the one after that.
    from_theme_field =
      Enum.flat_map(written, fn
        {:routed, name, posts} ->
          case active_topic(event, name) do
            nil -> []
            theme -> Enum.map(posts, &{&1, theme})
          end

        _other ->
          []
      end)

    (from_topics ++ from_theme_field)
    |> Enum.group_by(fn {post, _theme} -> post end, fn {_post, theme} -> theme.id end)
    |> Enum.map(fn {post, theme_ids} ->
      Judgment.judge_theme_set!(%{
        event_id: event.id,
        post_id: post.id,
        theme_ids: Enum.uniq(theme_ids),
        actor_id: agent.id,
        confidence: 0.7
      })

      post.id
    end)
    |> length()
  end

  # THE THIRD LEG OF THE CONSERVATION LAW, MADE DURABLE. A post the extractor read and
  # said nothing about — no claim, no topic — left no trace, so the sweep handed it out
  # again on every pass. Seen live twice: six batches, one post, six calls.
  #
  # `Wekui.Judgment.ThemeNone` has modelled it all along: an Actor's answer that a Post
  # carries no theme. That IS the extractor's answer when it read a post and found
  # nothing in it, and it is a real judgement rather than an absence — which is why it
  # belongs on the record and not in a variable that dies with the run.
  #
  # A post cited by an `unfitted` entry is deliberately included: the extractor DID read
  # it and reported that it evidences something the vocabulary cannot name. That is an
  # answer about themes, and the entry survives separately in the residue.
  defp judge_silence(event, agent, written, topics, posts, by_xid) do
    spoke =
      for({:ok, claim} <- written, do: claim.id)
      |> Enum.flat_map(&Narrative.list_claim_citations!/1)
      |> MapSet.new(& &1.post_id)

    routed =
      (for({:routed, _name, routed_posts} <- written, post <- routed_posts, do: post.id) ++
         (topics
          |> Enum.flat_map(&List.wrap(&1["citations"]))
          |> Enum.map(&Map.get(by_xid, to_string(&1)))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(& &1.id)))
      |> MapSet.new()

    answered = MapSet.union(spoke, routed)

    posts
    |> Enum.reject(&MapSet.member?(answered, &1.id))
    |> Enum.map(fn post ->
      Judgment.judge_theme_none!(%{
        event_id: event.id,
        post_id: post.id,
        actor_id: agent.id,
        confidence: 0.6
      })
    end)
    |> length()
  end

  defp active_topic(event, name) do
    folded = Normalize.fold(to_string(name || ""))

    event.id
    |> Taxonomy.list_active_themes!()
    |> Enum.find(&(&1.nature == :topic and Normalize.fold(&1.name) == folded))
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

  # EVERY POST IS ACCOUNTED FOR. A batch splits into the posts a claim cites, the posts
  # the model routed to a topic, the posts it reported as evidencing something the
  # vocabulary has no word for, and the rest — which evidenced nothing. Before this a
  # post that fit nothing simply vanished, and a silence is not auditable
  # (`docs/mechanisms.md`).
  #
  # All three lists carry citations, so all three count. An earlier version counted only
  # claim citations and reported 14 of 20 looting posts "unread" while three `unfitted`
  # entries were citing most of them — the accounting was wrong in the direction that
  # makes the pipeline look worse than it is, which is still wrong.
  defp summarize(results, unfitted, topics, posts, by_xid, judged) do
    from_claims =
      for({:ok, claim} <- results, do: claim.id)
      |> Enum.flat_map(&Narrative.list_claim_citations!/1)
      |> MapSet.new(& &1.post_id)

    from_routed = for({:routed, _name, posts} <- results, post <- posts, do: post.id)

    accounted =
      (unfitted ++ topics)
      |> Enum.flat_map(&List.wrap(&1["citations"]))
      |> Enum.map(&Map.get(by_xid, to_string(&1)))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new(& &1.id)
      |> MapSet.union(from_claims)
      |> MapSet.union(MapSet.new(from_routed))

    # A topic the model put in "theme" instead of "topics" still routed correctly; it
    # just arrived through the wrong door, and the count says how often.
    recovered = for({:routed, name, _posts} <- results, do: name)
    {named, misrouted} = split_topics(topics, hd(posts).event_id)

    %{
      claims: length(results),
      drafted: Enum.count(results, &match?({:ok, _}, &1)),
      skipped: Enum.count(results, &match?({:skip, _}, &1)),
      routed_from_theme: Enum.frequencies(recovered),
      skips: for({:skip, reason} <- results, do: reason),
      posts: length(posts),
      cited: MapSet.size(from_claims),
      unfitted: Enum.map(unfitted, &to_string(&1["what_happened"] || "")),
      topics: Enum.frequencies(named ++ recovered),
      # Posts that now carry a durable theme judgment, not just a line in this summary.
      judged: judged,
      # A HAPPENING name in the topics list is the model declining to claim something
      # it recognised — a lost claim, not a topic, and invisible until counted.
      misrouted_topics: Enum.frequencies(misrouted),
      unread: length(posts) - MapSet.size(accounted)
    }
  end

  defp split_topics(topics, event_id) do
    active = Taxonomy.list_active_themes!(event_id)
    names = Map.new(active, &{Normalize.fold(&1.name), &1.nature})

    topics
    |> Enum.map(&to_string(&1["topic"] || ""))
    |> Enum.split_with(&(Map.get(names, Normalize.fold(&1)) == :topic))
  end
end
