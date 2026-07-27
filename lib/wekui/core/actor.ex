defmodule Wekui.Core.Actor do
  @moduledoc """
  Whoever or whatever performed a deliberate act — a **person** or an **agent**.
  An agent is a machine worker driven by a `model` and a `prompt`; a person is a
  human, whose details wait until a human act is first attributed. `kind` tells
  the two apart.

  An agent is content-addressed: `register_agent` is an upsert on
  `(event_id, content_hash, model)`, where `content_hash` is the SHA-256 of the
  `prompt`, computed on write and never accepted. So the same model and the same
  prompt are the same agent — registering it again returns the row we already
  hold and changes nothing. This is the old app's content-addressed `prompts`
  (`(content_hash, model)`) elevated into a first-class thing, now Event-scoped
  like everything else.

  A **person** is named, and that name is the whole of their details: `register_person`
  is an upsert on `(event_id, name)`, so the same name is the same curator. An agent
  leaves `name` absent and a person leaves `model`, `prompt` and `content_hash` absent —
  SQLite treats NULLs as distinct in a unique index, so each kind coexists freely under
  the other's identity.

  An Actor's name is **not** a `Wekui.Narrative.Person`'s name and the private-name gate
  does not reach it: a Person is whom a Claim is *about*, an Actor is who *acted*. An
  Actor's name never enters a Claim or a Beat — it appears in the audit trail and in the
  report's record of what a human already settled.

  An Actor is remembered, never revised: it has no lifecycle, and no update or
  destroy action — it is only ever the who behind acts that have one.
  """

  use Ash.Resource,
    otp_app: :wekui,
    domain: Wekui.Core,
    data_layer: AshSqlite.DataLayer

  alias Wekui.Core.Changes.ContentHash

  sqlite do
    table "actors"
    repo Wekui.Repo

    # (event_id, content_hash, model) is the unique agent identity; its index,
    # prefixed by event_id, also covers event_id reads.
    references do
      reference :event, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :register_agent do
      primary? true

      description """
      Records an agent — a (model, prompt) worker — or returns the one this Event
      already holds. The same model and prompt are the same agent; re-registering
      one changes nothing and returns it.
      """

      accept [:event_id, :model, :prompt]

      # An agent is defined by both; a row missing either is not an agent.
      validate present([:model, :prompt])

      change set_attribute(:kind, :agent)
      change {ContentHash, from: :prompt, to: :content_hash}

      upsert? true
      upsert_identity :unique_agent
      # An agent is immutable: re-registering it returns the row, unchanged.
      upsert_fields []
    end

    create :register_person do
      description """
      Records a person — a human who curates this Event's record — or returns the one
      it already holds. The same name is the same curator; re-registering changes
      nothing and returns them.
      """

      accept [:event_id, :name]

      # A person with no name is the thing this action exists to stop being.
      validate present([:name])

      change set_attribute(:kind, :person)

      upsert? true
      upsert_identity :unique_person
      # Remembered, never revised — same as an agent.
      upsert_fields []
    end

    read :by_event do
      description "Every Actor of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      description "Which sort of Actor this is: a person or an agent."
      allow_nil? false
      public? true
      constraints one_of: [:person, :agent]
    end

    attribute :name, :string do
      description "What a person is called — the whole of a person's details. Absent for an agent, and never a Person's name: this is who acted, not whom a Claim is about."
      public? true
    end

    attribute :model, :string do
      description "The machine model an agent runs. Absent for a person."
      public? true
    end

    attribute :prompt, :string do
      description "The prompt an agent is driven by. Absent for a person."
      public? true
    end

    attribute :content_hash, :string do
      description "The SHA-256 of the prompt — an agent's content address. Derived, never supplied."
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_agent, [:event_id, :content_hash, :model] do
      message "this Event already holds that agent"
    end

    identity :unique_person, [:event_id, :name] do
      message "this Event already holds that person"
    end
  end
end
