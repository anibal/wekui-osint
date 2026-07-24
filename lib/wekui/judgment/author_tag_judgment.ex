defmodule Wekui.Judgment.AuthorTagJudgment do
  @moduledoc """
  An Actor's answer to *what is this Author* — that an Author carries an Author
  Tag. The author-scoped twin of a `Wekui.Judgment.ThemeJudgment`: the same
  append-only, superseding mechanism, keyed to an Author instead of a Post.

  The slot is `(author_id, tag_id)`: an Author may carry any number of current
  tag judgments at once, but at most one for each Tag — a partial unique index
  over the open rows enforces it. A tag answer and the Author's "no tag" are
  mutually exclusive: writing one retracts the other.

  `judge_set` replaces an Author's whole set of Tags in one step, so the current
  set always reads as one coherent answer from one Actor.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Judgment, data_layer: AshSqlite.DataLayer

  alias Wekui.Judgment.Changes.{CloseCurrent, Retract, Supersede}
  alias Wekui.Judgment.AuthorTagNone
  alias Wekui.Judgment.Validations.Provenance
  alias Wekui.Validations.Reference

  require Ash.Query

  sqlite do
    table "author_tag_judgments"
    repo Wekui.Repo

    custom_indexes do
      index [:author_id]
      index [:tag_id]
      index [:actor_id]
      index [:event_id]

      # One current answer per (Author, Tag): the partial unique that makes
      # supersession safe — only the open rows are constrained.
      index [:author_id, :tag_id],
        unique: true,
        where: "superseded_at IS NULL",
        name: "author_tag_judgments_current_slot_index",
        message: "this Author already has a current answer for that Tag"
    end

    references do
      reference :event, on_delete: :restrict
      reference :author, on_delete: :restrict
      reference :tag, on_delete: :restrict
      reference :actor, on_delete: :restrict
      reference :superseded_by, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :judge do
      primary? true
      transaction? true

      description """
      Records that an Author carries a Tag, superseding any prior answer for that
      Author-and-Tag and retracting the Author's "no tag".
      """

      accept [:event_id, :author_id, :tag_id, :actor_id, :confidence, :judged_at]

      validate {Reference, resource: Wekui.Capture.Author, attribute: :author_id}

      validate {Reference,
                resource: Wekui.Taxonomy.AuthorTag, attribute: :tag_id, lifecycle: :active}

      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate Provenance

      change {Supersede, slot: [:author_id, :tag_id]}
      change {CloseCurrent, resource: AuthorTagNone, match: [:author_id]}
    end

    update :retract do
      description "Closes this tag judgment without a successor."
      accept []
      require_atomic? false
      change Retract
    end

    update :link_successor do
      description "Internal: points a just-closed judgment at the successor that replaced it."
      accept []
      require_atomic? false
      argument :superseded_by_id, :uuid, allow_nil?: false
      change set_attribute(:superseded_by_id, arg(:superseded_by_id))
    end

    action :judge_set, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]

      description """
      Replaces an Author's whole set of Tags in one step: judges every Tag in the
      set from one Actor, and retracts the Tags no longer present. Returns the
      Author's current tag judgments.
      """

      argument :event_id, :uuid, allow_nil?: false
      argument :author_id, :uuid, allow_nil?: false
      argument :actor_id, :uuid, allow_nil?: false
      argument :tag_ids, {:array, :uuid}, allow_nil?: false, constraints: [min_length: 1]
      argument :confidence, :float
      argument :judged_at, :utc_datetime_usec

      run &Wekui.Judgment.AuthorTagJudgment.run_judge_set/2
    end

    read :current_for_author do
      description "An Author's current tag judgments, oldest first."
      argument :author_id, :uuid, allow_nil?: false

      filter expr(author_id == ^arg(:author_id) and is_nil(superseded_at))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :by_event do
      description "Every tag judgment of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :confidence, :float do
      description "How sure an agent is, 0 to 1. Absent for a person's judgment."
      public? true
      constraints min: 0.0, max: 1.0
    end

    attribute :judged_at, :utc_datetime_usec do
      description "When the answer was made."
      allow_nil? false
      public? true
      default &DateTime.utc_now/0
    end

    attribute :superseded_at, :utc_datetime_usec do
      description "When this answer was closed. Absent while it is the current answer."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    belongs_to :author, Wekui.Capture.Author do
      allow_nil? false
      public? true
    end

    belongs_to :tag, Wekui.Taxonomy.AuthorTag do
      allow_nil? false
      public? true
    end

    belongs_to :actor, Wekui.Core.Actor do
      allow_nil? false
      public? true
    end

    belongs_to :superseded_by, __MODULE__ do
      description "The answer that replaced this one. Absent for a retraction and for the current answer."
      public? true
    end
  end

  @doc false
  # Set-replacement body for `judge_set`, wrapped in an explicit Repo.transaction
  # (ash_sqlite cannot run Ash-managed transactions). Mirrors ThemeJudgment.
  def run_judge_set(input, _context) do
    a = input.arguments
    judged_at = Map.get(a, :judged_at) || DateTime.utc_now()
    target = MapSet.new(a.tag_ids)

    Wekui.Repo.transaction(fn ->
      {:ok, current} =
        Ash.read(
          Ash.Query.filter(__MODULE__, author_id == ^a.author_id and is_nil(superseded_at)),
          authorize?: false
        )

      Enum.each(current, fn judgment ->
        unless MapSet.member?(target, judgment.tag_id) do
          judgment |> Ash.Changeset.for_update(:retract) |> Ash.update!(authorize?: false)
        end
      end)

      Enum.each(a.tag_ids, fn tag_id ->
        __MODULE__
        |> Ash.Changeset.for_create(:judge, %{
          event_id: a.event_id,
          author_id: a.author_id,
          tag_id: tag_id,
          actor_id: a.actor_id,
          confidence: Map.get(a, :confidence),
          judged_at: judged_at
        })
        |> Ash.create!(authorize?: false)
      end)

      {:ok, set} =
        Ash.read(
          Ash.Query.filter(__MODULE__, author_id == ^a.author_id and is_nil(superseded_at)),
          authorize?: false
        )

      set
    end)
  end
end
