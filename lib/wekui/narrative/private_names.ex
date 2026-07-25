defmodule Wekui.Narrative.PrivateNames do
  @moduledoc """
  The persons red line, enforced mechanically (F54). A Claim names no private
  individual — the trapped, the rescued, the missing, the dead, and their
  relatives, neighbours and rescuers — ever; they are told by role and attribute
  (`docs/pages/claim.md`). A rule enforced only by a prompt is not enforced: the
  old record carried 606 beats naming private people — 415 with a
  rescued/dead/missing status claim — under prompts that forbade it in the same
  words. This is what enforces it, on the write path.

  Detection is conventional, no new dependency: find capitalized name-like
  sequences (two-plus words, Spanish connectors allowed), then drop the ones a
  vocabulary explains — the event's gazetteer names (a building is a `place`, not
  a person) and the operator-owned public-figure allowlist (officials acting
  publicly may be named). What is left is treated as a private individual.
  Deliberately over-inclusive: a false flag is a human's one-glance dismissal (or
  an allowlist entry); a miss is a red-line breach. Ported from the old app's
  F54/F55-hardened gate.
  """

  alias Wekui.Core.Place
  alias Wekui.Core.PlaceName
  alias Wekui.Normalize

  require Ash.Query

  # First words that make a capitalized sequence a THING — a place, an
  # institution, a collective — rather than a person. Every word here is a hole
  # in the gate: add only nouns implausible as a Spanish given name/surname, and
  # keep a human report as the backstop over whatever slips through.
  @institution_words ~w(
    edificio edif residencia residencias urbanizacion urb torre torres
    conjunto centro club hotel bar restaurant restaurante salon avenida av
    calle puente parque playa mision plaza sector barrio parroquia estado
    municipio marina bloque muelle balneario iglesia colegio escuela
    fuerzas guardia proteccion ejercito armada asamblea bomberos ministerio
    gobierno alcaldia policia cruz copernicus usar redan onu ee uu
    venezuela colombia argentina espana mexico catar
    estados republica israel qatar jordania chile peru panama brasil cuba
    uruguay ecuador turquia italia francia alemania portugal salvador
    unidad unidades equipo equipos brigada brigadas cuadrilla comision
    rescatistas voluntarios voluntarias estudiantes vecinos vecinas familiares
    habitantes damnificados sobrevivientes autoridades funcionarios personal
    tropas militares efectivos agentes topos delegacion comando cuerpo cuerpos
    grupo grupos instituto universidad hospital clinica ambulatorio refugio
    albergue fundacion organizacion asociacion camara empresa consorcio
    embajada consulado gobernacion prefectura defensa direccion servicio
    servicios sistema aerolinea aeropuerto puerto terminal metro hidrocapital
    corpoelec pdvsa inameh funvisis sismologico
    res resd consejo junta comite cooperativa complejo residencial quinta
    posada hostal farmacia supermercado abasto panaderia mercado liceo
    guarderia ancianato asilo cancha estadio gimnasio autopista carretera
    via viaducto quebrada rio cerro loma punta bahia ensenada malecon
    litoral costa region zona area paramedico paramedicos medico medicos
    enfermeras enfermeros doctores socorristas buzos rescatista camilleros
    islas isla archipielago golfo analisis necesidades informe reporte
  )

  # Two-plus capitalized words, Spanish name connectors (de/del/la/las/los/y/e)
  # allowed between them.
  @sequence ~r/\p{Lu}[\p{L}]+(?:\s+(?:de|del|la|las|los|y|e)\s+\p{Lu}[\p{L}]+|\s+\p{Lu}[\p{L}]+)+/u

  # Leading articles/prepositions are trimmed so a sentence start ("El Ejército
  # llegó…", "En la Bajada…") does not fire on its own; repeats because a start
  # can shed more than one token before the name.
  @leading_article ~r/^(el|la|los|las|un|una|en|de|del|desde|tras|con|por|para|durante|segun|según|hasta|ante|sobre|entre|al|a)\s+/iu

  @doc """
  The name-like sequences in `text` that `vocabulary` cannot explain — apparent
  private individuals. `[]` means the text is clean. `nil` text is clean.
  """
  def unexplained(text, vocabulary)

  def unexplained(nil, _vocabulary), do: []

  def unexplained(text, vocabulary) when is_binary(text) and is_list(vocabulary) do
    text
    |> candidate_sequences()
    |> Enum.reject(&explained?(&1, vocabulary))
  end

  @doc """
  The event's name vocabulary: gazetteer geography (every Place's canonical name
  and every surface `place_name`) plus the operator-owned public-figure
  allowlist. All folded. Loaded fresh per check — a small local read that a
  curation just before may have grown.
  """
  def vocabulary(event_id), do: known_names(event_id) ++ public_figures()

  @doc "The operator-owned allowlist of people who may be named (`config :wekui, :public_figures`), folded."
  def public_figures do
    :wekui
    |> Application.get_env(:public_figures, [])
    |> Enum.map(&Normalize.fold/1)
  end

  ## ─────────────────────────── detection ───────────────────────────

  defp candidate_sequences(text) do
    @sequence
    |> Regex.scan(text)
    |> Enum.flat_map(fn [match | _groups] -> split_conjunctions(match) end)
    |> Enum.map(&strip_leading/1)
    |> Enum.filter(&(length(String.split(&1)) >= 2))
    |> Enum.uniq()
  end

  # "y"/"e" join the parts of a Spanish personal name, but they also join a LIST
  # of places — and a disaster claim is full of lists. Each side is judged on its
  # own; a real conjoined surname still fails on both halves, so nothing leaks.
  defp split_conjunctions(sequence), do: Regex.split(~r/\s+[ye]\s+/u, sequence)

  defp strip_leading(sequence) do
    case String.replace(sequence, @leading_article, "") do
      ^sequence -> sequence
      shorter -> strip_leading(shorter)
    end
  end

  defp explained?(sequence, known) do
    folded = Normalize.fold(sequence)
    [first | _rest] = String.split(folded)

    first in @institution_words or
      Enum.any?(known, fn name ->
        String.contains?(name, folded) or String.contains?(folded, name)
      end)
  end

  # Every name the gazetteer knows is geography, not a person — canonical names
  # AND every surface form in place_names (reading only canonicals blinds the
  # gate to the alias vocabulary the posts actually use).
  defp known_names(event_id) do
    canonical =
      Place
      |> Ash.Query.filter(event_id == ^event_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.canonical_name)

    surface =
      PlaceName
      |> Ash.Query.filter(place.event_id == ^event_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.name)

    (canonical ++ surface)
    |> Enum.map(&Normalize.fold/1)
    |> Enum.uniq()
  end
end
