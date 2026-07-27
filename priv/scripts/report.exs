# The record, written out as markdown for review.
#
#     mix run priv/scripts/report.exs
#
# Read-only and free — no inference, no key, no spend. Writes `tmp/<event>.md`
# (git-ignored, because the report names private individuals so their handles can
# be checked; nothing else in the record ever does).
#
# Overridable: EVENT, OUT.

require Ash.Query

# dev logs every query at :debug, which drowns a script's own output.
Logger.configure(level: :info)

alias Wekui.Core
alias Wekui.Report

event_name = System.get_env("EVENT", "litoral-central-2026")

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)} — run priv/scripts/pilot_event.exs")
    found -> found
  end

path = System.get_env("OUT", "tmp/#{event.name}.md")
File.mkdir_p!(Path.dirname(path))
File.write!(path, Report.render(event))

IO.puts("\n  wrote #{path} (#{File.stat!(path).size} bytes)\n")
