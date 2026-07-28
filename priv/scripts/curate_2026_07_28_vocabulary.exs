# The operator's rulings on the proposed vocabulary, applied.
#
#     mix run priv/scripts/curate_2026_07_28_vocabulary.exs
#
# No inference, no key, no spend.
#
# He read the twenty-one themes the corpus proposed and ruled on five of them. Four of
# the five are things the eight-day corpus CANNOT teach — a body recovered versus a
# death declared, neighbours digging beside the international teams, the aid chain past
# the moment of delivery. He knows the arc of a disaster; the readers only had its
# first week. That is the split this project keeps finding: the machine derives the
# structure, the human supplies what the data has not lived through yet.
#
# What each ruling does here:
#
#   * a SPLIT retires the merged theme (`discard`, with the reason naming its
#     successors) and the amended data file creates the two that replace it. There is
#     no `split_theme` verb — the inverse of a fold — and its absence is why this takes
#     two steps instead of one. Named, not hidden.
#   * a FAMILY reparents an existing theme under a new structural node.
#
# Everything is `:proposed` throughout: none of this enters the vocabulary until he
# promotes it. Retiring a proposal is still an attributed act — it is on the record,
# and a proposal deleted by nobody is the same defect as a decision made by nobody.
#
# Idempotent: a theme already retired is skipped, and a theme already under its parent
# is left alone.

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

IO.puts("\n── the vocabulary, ruled ────────────────────────────────────────\n")
say.("curator: #{curator.name}")

# The amended proposal first: the fourteen themes his rulings call for.
counts = Taxonomy.Seed.litoral_central(event.id)
say.("seed:    #{counts.created} theme(s) created, #{counts.reused} already held")

held = fn name ->
  event.id
  |> Taxonomy.list_themes!()
  |> Enum.find(&(&1.name == name))
end

# {merged theme, what replaced it, why} — ruled 2026-07-28.
splits = [
  {"Persona fallecida o cuerpo recuperado",
   ["Persona fallecida", "Cuerpo recuperado o identificado"],
   "A death and a body are not the same fact. As this record ages many people will be declared dead with no body ever found or identified, and a merged theme could not tell the two apart."},
  {"Solicitud de rescate o recursos", ["Solicitud de rescate", "Solicitud de recursos"],
   "Asking for rescuers because someone may be alive is not asking for fuel. One is a life; the other is logistics."},
  {"Operación de búsqueda y rescate en curso",
   ["Operación de rescate con vida", "Operación de recuperación de cuerpos"],
   "Working to reach someone believed alive is not working to recover the dead. The operation, its urgency and its meaning for the record all differ."}
]

split =
  Enum.count(splits, fn {merged_name, into, why} ->
    merged = held.(merged_name) || Mix.raise("no theme named #{inspect(merged_name)}")

    if merged.lifecycle == :discarded do
      say.("already: “#{merged_name}” is retired")
      false
    else
      Curation.discard_theme!(
        merged,
        curator,
        why <> " Split into: " <> Enum.join(into, " + ") <> "."
      )

      say.("split:   “#{merged_name}” → #{Enum.join(into, " + ")}")
      true
    end
  end)

# {theme, its new parent, why} — a family the readers had no reason to see.
families = [
  {"Apoyo internacional desplegado", "Apoyo desplegado",
   "International teams are the loudest but not the only ones. Locals trying to help, and national bodies deployed, were what was actually on the ground."},
  {"Entrega de ayuda humanitaria", "Ayuda humanitaria",
   "Aid is a chain, not an event: gathered at a collection point, moved, then delivered. Citizens self-organize the first two and they are their own work."}
]

moved =
  Enum.count(families, fn {name, parent_name, why} ->
    theme = held.(name) || Mix.raise("no theme named #{inspect(name)}")
    parent = held.(parent_name) || Mix.raise("no theme named #{inspect(parent_name)}")

    if theme.parent_id == parent.id do
      say.("already: “#{name}” sits under “#{parent_name}”")
      false
    else
      Curation.reparent_theme!(theme, parent, curator, why)
      say.("moved:   “#{name}” under “#{parent_name}”")
      true
    end
  end)

themes = Taxonomy.list_themes!(event.id)
live = Enum.reject(themes, &(&1.lifecycle in [:discarded, :deprecated]))
by_nature = Enum.frequencies_by(live, & &1.nature)

IO.puts("")
say.("#{split} split, #{moved} moved")

say.(
  "#{length(live)} theme(s) standing — #{by_nature[:happening] || 0} happening, #{by_nature[:topic] || 0} topic; #{length(themes) - length(live)} retired"
)

say.("#{length(Curation.list_acts!(event.id))} attributed act(s) on the record")
IO.puts("")
