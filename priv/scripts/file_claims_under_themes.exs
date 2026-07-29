# Files the pre-vocabulary claims under the vocabulary, where their own words reach it.
#
#     mix run priv/scripts/file_claims_under_themes.exs
#
# No inference, no key, no spend. `Wekui.Narrative.ThemeResolver` is deterministic.
#
# Sixty-seven claims were drafted before the record had any vocabulary of happenings.
# Their `kind` is whatever a model typed and nothing could refuse one. Now that a
# person has ratified 32 themes, most of those claims can be filed under one — and a
# claim the record cannot file reaches no reader.
#
# This is a MIGRATION, not a judgement, and that is why it carries no curation act:
# nobody decided anything. Filing "colapso" under `Colapso estructural` asserts nothing
# the claim did not already assert; `kind` — the extractor's own words — is untouched.
# Filing is the same kind of thing as a place link: a current best reading, not a
# historical fact.
#
# WHAT STAYS UNFILED IS THE POINT. Roughly a third of them reach no active happening
# theme, and almost all of those are the plea family — `solicitud de información sobre
# desaparecidos` and its four other spellings, `personas atrapadas`, `desaparición`.
# The vocabulary says those are TOPICS: things a post is about, from which no claim
# follows. So the record now refuses to say a family who asked is a person who is
# missing. Those claims stay on the record, honest and silent, until a themed
# re-extraction supersedes them.
#
# Idempotent: a claim already filed under the same theme is skipped.

require Ash.Query

Logger.configure(level: :info)

alias Wekui.Core
alias Wekui.Narrative
alias Wekui.Narrative.ThemeResolver

event_name = System.get_env("EVENT", "litoral-central-2026")
say = fn message -> IO.puts("  " <> message) end

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

IO.puts("\n── filing the pre-vocabulary claims ─────────────────────────────\n")
say.("event  #{event.name}")

claims = Narrative.current_claims!(event.id)

{filed, unfiled} =
  Enum.reduce(claims, {0, []}, fn claim, {filed, unfiled} ->
    case ThemeResolver.resolve(event.id, claim.kind) do
      {:ok, theme} when claim.theme_id != theme.id ->
        Narrative.file_claim_under_theme!(claim, %{theme_id: theme.id})
        {filed + 1, unfiled}

      {:ok, _already} ->
        {filed, unfiled}

      :no_theme ->
        {filed, [claim | unfiled]}
    end
  end)

say.("filed  #{filed} of #{length(claims)} claim(s)")
say.("unfiled #{length(unfiled)} — the vocabulary has no HAPPENING their words reach")

IO.puts("")

unfiled
|> Enum.frequencies_by(& &1.kind)
|> Enum.sort_by(&(-elem(&1, 1)))
|> Enum.each(fn {kind, n} -> say.("  #{String.pad_leading(to_string(n), 3)}  #{kind}") end)

IO.puts("""

  A claim the record cannot file reaches no reader. Most of the unfiled are pleas —
  the vocabulary calls those TOPICS, so the record now refuses to say that a family
  who asked is a person who is missing. That refusal is the whole point.
""")
