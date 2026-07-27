# The operator's answers about Caraballeda, applied as ATTRIBUTED acts.
#
#     mix run priv/scripts/curate_2026_07_27_caraballeda.exs
#
# No inference, no key, no spend.
#
# These are the first curation acts the record can name a person for. Their
# sibling, `curate_2026_07_27.exs`, applied three acts before attribution
# existed; those carry no who and never will, and that script is their only
# record. This one does not need to be the record — `Wekui.Curation` writes it to
# `curation_acts`, with the person, the moment, what moved and why. The script is
# only the applier.
#
# Idempotent: registering a person returns the person we already hold, a claim
# already settled by hand is left alone, and a place already folded is not folded
# again.

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

IO.puts("\n── Caraballeda, settled ─────────────────────────────────────────\n")

# Registering the curator is NOT a curation act and carries no attribution — it is
# the bootstrap, the same way the pilot's agent was registered by a seed script.
curator = Core.register_person!(%{event_id: event.id, name: curator_name})
say.("curator: #{curator.name} (#{String.slice(curator.id, 0, 8)})")

places = Core.list_places!(event.id)

find_place = fn name, type, lifecycle ->
  Enum.find(
    places,
    &(&1.canonical_name == name and &1.type == type and &1.lifecycle == lifecycle)
  )
end

parroquia =
  find_place.("Caraballeda", "parroquia", :active) ||
    Mix.raise("no active parroquia Caraballeda in #{event_name}")

# ── Act 1 — a bare "Caraballeda" means the parroquia ─────────────────────────
#
# The claim about the woman's rescue had been resolved to the duplicate node at
# confidence 0.5, because two nodes carried the name and nothing in the mention
# could choose between them.
claim =
  event.id
  |> Narrative.current_claims!()
  |> Enum.find(&(&1.place_mention == "Caraballeda"))

settled? =
  claim && claim.id |> Narrative.list_claim_places!() |> Enum.any?(&(&1.how_resolved == :manual))

cond do
  is_nil(claim) ->
    say.("act 1 already: no claim mentions a bare “Caraballeda”")

  settled? ->
    say.("act 1 already: “#{claim.kind} — #{claim.subject}” is settled by hand")

  true ->
    Curation.relink_claim_place!(
      claim,
      parroquia,
      curator,
      "A bare “Caraballeda” means the parroquia."
    )

    say.("act 1: “#{claim.kind} — #{claim.subject}” → Caraballeda (parroquia)")
end

# ── Act 2 — the duplicate node was never a place ─────────────────────────────
#
# His ruling: "Caraballeda is the Parish. Sector Caraballeda, Urbanización
# Caraballeda, and any other combination are just alternatives from the popular
# speech." So the populated_place beneath the parroquia is not a finer place — it
# is the parish under a name people use for it, recorded twice by the gazetteer.
#
# One act, however many rows it moves: the buildings beneath it move up to the
# parish, its names move up so nothing it answered to is lost, and the node is
# deprecated onto the parish rather than deleted.
case find_place.("Caraballeda", "populated_place", :active) do
  nil ->
    say.("act 2 already: no active duplicate “Caraballeda” to fold")

  duplicate ->
    folded =
      Curation.fold_place_into!(
        duplicate,
        parroquia,
        curator,
        "Caraballeda is the parish. Sector Caraballeda, Urbanización Caraballeda and any other combination are alternatives from popular speech, not finer places."
      )

    say.("act 2: folded the duplicate “Caraballeda” (#{folded.type}) into the parroquia")
end

acts = Curation.list_acts!(event.id)
IO.puts("\n  #{length(acts)} attributed act(s) on the record\n")
