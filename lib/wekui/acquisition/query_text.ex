defmodule Wekui.Acquisition.QueryText do
  @moduledoc """
  The one settled way of writing a Query's request to X, so that the same
  coordinates always produce the same characters.

  ## Shape

      <location group>[ <event group>] since_time:<epoch> until_time:<epoch> queryType=<Latest|Top>

    * a group joins its members with `" OR "`, and is parenthesised only when
      it has two or more — a single member is no group at all;
    * an anchored location group renders as `<anchored name> (<qualifier> OR …)`:
      the name itself, next to the group of its ancestors' names;
    * any member containing whitespace is quoted;
    * the slice is Unix epoch seconds, `[since, until)` — half-open, so
      consecutive slices never double-count a post on the boundary;
    * the result mode rides at the end as ` queryType=Latest` / ` queryType=Top`.
      It lives in the text and nowhere else, so two places can never disagree
      about what was asked.

  This module never reorders anything: callers pass members already sorted, so
  the same coordinates always produce byte-identical text.
  """

  @latest_suffix " queryType=Latest"
  @top_suffix " queryType=Top"

  @doc "How a request in latest mode ends. Coverage matches on this."
  @spec latest_suffix() :: String.t()
  def latest_suffix, do: @latest_suffix

  @typedoc """
  The coordinates of one Query:

    * `:location` — `{:raw, [name]}` or `{:anchored, name, [qualifier]}`
    * `:terms` — the event group (`[]` for a base sweep)
    * `:since` / `:until` — the slice, `[since, until)`
    * `:mode` — `:latest | :top`
  """
  @type parts :: %{
          location: {:raw, [String.t()]} | {:anchored, String.t(), [String.t()]},
          terms: [String.t()],
          since: DateTime.t(),
          until: DateTime.t(),
          mode: :latest | :top
        }

  @doc "Renders the request for one set of coordinates."
  @spec render(parts()) :: String.t()
  def render(%{location: location, terms: terms, since: since, until: until_, mode: mode}) do
    [
      location_group(location),
      event_group(terms),
      "since_time:#{DateTime.to_unix(since)}",
      "until_time:#{DateTime.to_unix(until_)}",
      "queryType=#{mode_name(mode)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  The result mode the text was asked in — `:latest`, `:top`, or `nil` when the
  text carries no recognisable suffix. This is the read behind Coverage.
  """
  @spec result_mode_of(String.t()) :: :latest | :top | nil
  def result_mode_of(text) when is_binary(text) do
    cond do
      String.ends_with?(text, @latest_suffix) -> :latest
      String.ends_with?(text, @top_suffix) -> :top
      true -> nil
    end
  end

  @doc """
  Splits the text back into the request a runner sends: the X query string
  without the mode suffix, the mode, and the slice bounds as epoch seconds.
  """
  @spec decode(String.t()) :: %{
          query: String.t(),
          result_mode: :latest | :top | nil,
          since_time: integer() | nil,
          until_time: integer() | nil
        }
  def decode(text) when is_binary(text) do
    {query, mode} =
      cond do
        String.ends_with?(text, @latest_suffix) ->
          {String.replace_suffix(text, @latest_suffix, ""), :latest}

        String.ends_with?(text, @top_suffix) ->
          {String.replace_suffix(text, @top_suffix, ""), :top}

        true ->
          {text, nil}
      end

    %{
      query: query,
      result_mode: mode,
      since_time: capture_epoch(~r/(?:^|\s)since_time:(\d+)/, query),
      until_time: capture_epoch(~r/(?:^|\s)until_time:(\d+)/, query)
    }
  end

  @doc """
  How many pieces this request spends against X's limit. Every word, quoted
  phrase, `OR`, exclusion, filter and each of the two slice bounds counts one;
  parentheses are free, and the mode suffix is request metadata rather than
  part of the question, so it never counts.
  """
  @spec operator_count(String.t()) :: non_neg_integer()
  def operator_count(text) when is_binary(text) do
    %{query: query} = decode(text)

    query
    |> String.replace(~r/[()]/, " ")
    |> then(&Regex.scan(~r/"[^"]*"|\S+/, &1))
    |> length()
  end

  @doc ~S(Quotes a member containing whitespace: `La Guaira` → `"La Guaira"`.)
  @spec token(String.t()) :: String.t()
  def token(member) when is_binary(member) do
    if member =~ ~r/\s/, do: ~s("#{member}"), else: member
  end

  defp location_group({:raw, names}), do: group(names)
  defp location_group({:anchored, name, qualifiers}), do: "#{token(name)} #{group(qualifiers)}"

  defp event_group([]), do: nil
  defp event_group(terms), do: group(terms)

  defp group([single]), do: token(single)

  defp group(members) when is_list(members) and members != [] do
    "(" <> Enum.map_join(members, " OR ", &token/1) <> ")"
  end

  defp mode_name(:latest), do: "Latest"
  defp mode_name(:top), do: "Top"

  defp capture_epoch(regex, query) do
    case Regex.run(regex, query) do
      [_, epoch] -> String.to_integer(epoch)
      nil -> nil
    end
  end
end
