# The operator's answer to Q2 — the two Caraballedas — applied as an ATTRIBUTED act.
#
#     mix run priv/scripts/curate_2026_07_27_caraballeda.exs
#
# Read-only of the network: no inference, no key, no spend.
#
# This is the first curation act the record can name a person for. Its sibling,
# `curate_2026_07_27.exs`, applied three acts before attribution existed; those
# carry no who and never will, and that script is their only record. This one
# does not need to be the record — `Wekui.Curation` writes it to `curation_acts`,
# with the person, the moment, what moved and why. The script is only the applier.
#
# Idempotent: registering a person returns the person we already hold, and a
# claim already settled by hand is left alone.

require Ash.Query

# dev logs every query at :debug, which drowns a script's own output.
Logger.configure(level: :info)

alias Wekui.Core
alias Wekui.Curation
alias Wekui.Narrative

event_name = System.get_env("EVENT", "litoral-central-2026")
curator_name = System.get_env("CURATOR", "Aníbal Rojas")

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

say = fn message -> IO.puts("  " <> message) end

IO.puts("\n── the first attributed act ─────────────────────────────────────\n")

# Registering the curator is NOT a curation act and carries no attribution — it is
# the bootstrap, the same way the pilot's agent was registered by a seed script.
curator = Core.register_person!(%{event_id: event.id, name: curator_name})
say.("curator: #{curator.name} (#{String.slice(curator.id, 0, 8)})")

# ── Q2 — a bare "Caraballeda" means the parroquia ────────────────────────────
#
# The tree answered whether they are one place recorded twice: they are not. The
# parroquia holds 22 settlements; the populated_place beneath it holds 44
# buildings and also answers to "Urbanización Caraballeda". Two real places that
# share a bare name — so the resolver tied at 0.5 and took the finer one.
#
# His call: a bare mention means the parish. It is the coarser, safer reading, and
# the tree rolls the town up into it anyway.
places = Core.list_places!(event.id)

find_place = fn name, type ->
  Enum.find(places, &(&1.canonical_name == name and &1.type == type)) ||
    Mix.raise("no place #{inspect(name)} (#{type}) in #{event_name}")
end

parroquia = find_place.("Caraballeda", "parroquia")

claim =
  event.id
  |> Narrative.current_claims!()
  |> Enum.find(&(&1.place_mention == "Caraballeda"))

settled? =
  claim && claim.id |> Narrative.list_claim_places!() |> Enum.any?(&(&1.how_resolved == :manual))

cond do
  is_nil(claim) ->
    say.("Q2 already: no claim mentions a bare “Caraballeda”")

  settled? ->
    say.("Q2 already: “#{claim.kind} — #{claim.subject}” is settled by hand")

  true ->
    Curation.relink_claim_place!(
      claim,
      parroquia,
      curator,
      "Two real places share the bare name: the parroquia and the town inside it. A bare “Caraballeda” means the parroquia — the coarser reading, and the tree rolls the town up into it."
    )

    say.("Q2 re-placed: “#{claim.kind} — #{claim.subject}” → Caraballeda (parroquia)")
end

acts = Curation.list_acts!(event.id)
IO.puts("\n  #{length(acts)} attributed act(s) on the record\n")
