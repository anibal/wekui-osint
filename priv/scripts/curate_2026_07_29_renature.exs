# Correcting a line I drew wrong, measured by the pipeline refusing to use it.
#
#     mix run priv/scripts/curate_2026_07_29_renature.exs
#
# No inference, no key, no spend.
#
# WHAT HAPPENED. The spike brief defined a happening as "something that OCCURRED at a
# moment you could point to". Under that definition being missing is a duration and not
# a moment, so all three independent readers marked `Persona desaparecida o sin
# contacto` a TOPIC — correctly, by my definition — and the operator ratified a
# vocabulary whose consequence was invisible.
#
# The consequence: a claim may only carry a happening, so **the record could not say
# that anybody was missing**. It could not say anybody was trapped either. Those are
# the two largest themes in the corpus (66 and 61 posts of 302) and they are the
# memorial's core content.
#
# Nothing announced it. It surfaced only when v8 read 27 posts and the pipeline REFUSED
# 20 of the 24 claims it drew — 10 `Persona desaparecida o sin contacto`, 9 `Solicitud
# de información`, 1 `Solicitud de rescate`. The model was reading the corpus correctly
# and the vocabulary had no way to accept it. That is exactly the refusal-rate-per-theme
# signal `docs/ontology-fitness.md` names as the one that closes the loop, arriving
# before the measurement that would have caught it was built.
#
# THE LINE, CORRECTED. Not moment-versus-duration. The question is:
#
#     Does the record assert this about THE WORLD, or is it only about what a POST is doing?
#
#   * "this person's whereabouts are unknown"      → a fact about the world → happening
#   * "this person is trapped under rubble"        → a fact about the world → happening
#   * "teams are working this site"                → a fact about the world → happening
#   * "these people lost their homes"              → a fact about the world → happening
#   * "somebody asked whether anyone has news"     → a fact about the post  → topic
#   * "somebody criticised the response"           → a fact about the post  → topic
#
# The pleas stay topics, which is the distinction this whole layer was built for: a
# family asking is not a person missing. What changes is that the record can now say
# the second thing when a post actually asserts it.
#
# This is a CORRECTION OF A MISCLASSIFICATION, not a meaning that moved — the themes
# mean exactly what they meant. `redefine` records what the nature used to be, and one
# `redefine_theme!` in the other direction reverses any of it.
#
# Idempotent: a theme already marked happening is skipped.

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

# {theme, why it is a fact about the world rather than about a post}
world_facts = [
  {"Persona desaparecida o sin contacto",
   "A post asserting that a specific person's whereabouts are unknown states a fact about the world, not about itself. Marked a topic because the spike brief defined a happening as occurring 'at a moment', and being missing is a duration — so the record could not say that anybody was missing at all. It is the largest theme in the corpus."},
  {"Persona atrapada con vida bajo escombros",
   "Being trapped is a state of the world that a post asserts, and the second largest theme in the corpus. Same cause: a state has no moment, so the definition excluded it."},
  {"Operación de rescate con vida",
   "Rescuers working a site is something happening in the world, reported by the post rather than performed by it."},
  {"Operación de recuperación de cuerpos",
   "Same: the operation is in the world. Kept separate from the rescue of the living because the operator ruled on 2026-07-28 that reaching the living is not recovering the dead."},
  {"Damnificados y refugio",
   "People losing their homes and sheltering elsewhere is a fact about them, not about the post that reports it."}
]

IO.puts("\n── correcting the happening/topic line ──────────────────────────\n")
say.("curator: #{curator.name}")

held = fn name ->
  event.id |> Taxonomy.list_themes!() |> Enum.find(&(&1.name == name))
end

changed =
  Enum.count(world_facts, fn {name, why} ->
    theme = held.(name) || Mix.raise("no theme named #{inspect(name)}")

    if theme.nature == :happening do
      say.("already: “#{name}” is a happening")
      false
    else
      Curation.redefine_theme!(theme, %{nature: :happening}, curator, why)
      say.("happening: “#{name}”")
      true
    end
  end)

live = Taxonomy.list_active_themes!(event.id)
by_nature = Enum.frequencies_by(live, & &1.nature)

IO.puts("")
say.("#{changed} theme(s) corrected")

say.(
  "#{by_nature[:happening] || 0} happening — a claim may carry these; #{by_nature[:topic] || 0} topic"
)

say.("#{length(Curation.list_acts!(event.id))} attributed act(s) on the record")
IO.puts("")
