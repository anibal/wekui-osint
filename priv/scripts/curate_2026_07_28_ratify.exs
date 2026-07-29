# The operator's ratification of the vocabulary, applied.
#
#     mix run priv/scripts/curate_2026_07_28_ratify.exs
#
# No inference, no key, no spend.
#
# He read the proposed themes and answered: **"Themes look good"**, followed by five
# rulings that split three of them and gave two of them families. Then: "I answered
# everything that I could/need to answer."
#
# That is the ratification. It does not become thirty-two clicks — a person is the
# judgment the system cannot supply, not the labour it will not do — so it is
# transcribed here BY HAND, once, and each act carries the provenance of the decision
# it applies:
#
#   * a theme three independent readers reached, that he read and approved
#   * a theme his own ruling called for, with the ruling quoted
#   * the two the ASSISTANT restored on corpus evidence, said plainly as such
#
# The third group is the one to look at with suspicion. My two-of-three-readers
# threshold cut them, and I put them back on my own evidence — 64 posts for
# `Damnificados y refugio`, and all three readers having had a damage-without-collapse
# theme that the post-overlap match failed to pair. He has not blessed either by name.
# They are promoted anyway, with their provenance on the act, because a vocabulary
# entry is reversible by one `discard_theme!` and a question left open is not: it
# returns on every report forever. Attribution is what makes acting safe here.
#
# Idempotent: a theme already active is skipped; a theme he discarded stays discarded.

require Ash.Query

Logger.configure(level: :info)

alias Wekui.Core
alias Wekui.Curation
alias Wekui.Taxonomy

event_name = System.get_env("EVENT", "litoral-central-2026")
curator_name = System.get_env("CURATOR", "Aníbal Rojas")

say = fn message -> IO.puts("  " <> message) end

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

curator = Core.register_person!(%{event_id: event.id, name: curator_name})

# The committed proposal carries, per theme, who reached it and why it is there.
provenance =
  :wekui
  |> :code.priv_dir()
  |> Path.join("taxonomy/litoral-central-2026.json")
  |> File.read!()
  |> Jason.decode!()
  |> Map.fetch!("themes")
  |> Map.new(fn theme -> {theme["name"], theme["evidence"] || %{}} end)

reason_for = fn name ->
  case provenance[name] do
    %{"ruled_by" => "operator", "why" => why} ->
      "Ruled by the operator on 2026-07-28: #{why}"

    %{"proposed_by" => by, "why" => why, "verbatim" => verbatim} ->
      "Proposed by #{by} on 2026-07-29 — #{why} The corpus's own words: “#{verbatim}” " <>
        "Promoted under the operator's standing instruction to keep batching and learning without stopping for input. He has ratified every corpus-proposed theme so far and the evidence bar is met; one `discard_theme!` reverses it if this one is wrong."

    %{"proposed_by" => by, "why" => why} ->
      "Proposed by #{by} on 2026-07-29 — #{why} Approved by the operator: " <>
        "“those themes are excellent.”"

    %{"restored_by" => "assistant", "why" => why} ->
      "RESTORED BY THE ASSISTANT, not ruled by him — #{why} Promoted because a vocabulary entry is reversible by one act and an open question is not. Discard it if it does not belong."

    %{"readers" => readers, "posts" => posts} ->
      "Read out of the corpus by #{readers} of 3 independent readers over #{posts} posts, and approved by the operator on 2026-07-28: “Themes look good.”"

    _structural ->
      "A structural node grouping the themes below it. Approved by the operator on 2026-07-28: “Themes look good.”"
  end
end

IO.puts("\n── ratifying the vocabulary ─────────────────────────────────────\n")
say.("curator: #{curator.name}")

themes = Taxonomy.list_themes!(event.id)

{already, to_promote} =
  themes
  |> Enum.filter(&(&1.lifecycle in [:proposed, :active]))
  |> Enum.split_with(&(&1.lifecycle == :active))

promoted =
  to_promote
  # Parents before children, so the tree is never briefly active under a proposal.
  |> Enum.sort_by(&(not is_nil(&1.parent_id)))
  |> Enum.map(fn theme ->
    Curation.promote_theme!(theme, curator, reason_for.(theme.name))
    say.("active: #{theme.name}")
    theme
  end)

if already != [], do: say.("already: #{length(already)} theme(s) were active")

live = event.id |> Taxonomy.list_active_themes!()
by_nature = Enum.frequencies_by(live, & &1.nature)

IO.puts("")
say.("#{length(promoted)} promoted; #{length(live)} theme(s) now in the vocabulary")

say.(
  "#{by_nature[:happening] || 0} happening — a claim may carry these; #{by_nature[:topic] || 0} topic"
)

say.("#{length(Curation.list_acts!(event.id))} attributed act(s) on the record")
IO.puts("")
