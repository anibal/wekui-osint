defmodule Wekui.Core.Changes.ContentHash do
  @moduledoc """
  Writes the lowercase hex SHA-256 of one attribute into another.

      change {ContentHash, from: :prompt, to: :content_hash}

  Only fires when `:from` is actually being changed, so the hash can never drift
  from its source and can never be supplied by the caller. This is what makes two
  agents with the same prompt the same agent: identical text hashes identically,
  every time.
  """

  use Ash.Resource.Change

  @impl true
  def init(opts) do
    if is_atom(opts[:from]) and is_atom(opts[:to]) do
      {:ok, opts}
    else
      {:error, "#{inspect(__MODULE__)} expects atom :from and :to options"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    case Ash.Changeset.fetch_change(changeset, opts[:from]) do
      {:ok, value} when is_binary(value) ->
        hash = :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)
        Ash.Changeset.force_change_attribute(changeset, opts[:to], hash)

      _other ->
        changeset
    end
  end
end
