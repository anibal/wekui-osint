defmodule Wekui.ProposedByTest do
  @moduledoc """
  A Place, Theme or Author Tag can record who proposed it and, when it was read
  out of a Post, the Post it was inferred from. Provenance is optional (a
  hand-typed one has neither), but whatever it names must belong to the same
  Event — that is what later lets us ask how good an Actor is at reading each
  out of Posts.
  """
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Taxonomy

  setup do
    event = event!()
    %{event: event, other: event!(), agent: agent!(event), post: post!(event)}
  end

  describe "Place proposed_by" do
    test "records the Actor and the Post a Place was read from", ctx do
      place =
        Core.create_place!(%{
          event_id: ctx.event.id,
          type: "edificio",
          canonical_name: "Torre uno",
          proposed_by_actor_id: ctx.agent.id,
          proposed_from_post_id: ctx.post.id
        })

      assert place.proposed_by_actor_id == ctx.agent.id
      assert place.proposed_from_post_id == ctx.post.id
    end

    test "a hand-typed Place carries neither", ctx do
      place =
        Core.create_place!(%{
          event_id: ctx.event.id,
          type: "edificio",
          canonical_name: "Torre dos"
        })

      assert place.proposed_by_actor_id == nil
      assert place.proposed_from_post_id == nil
    end

    test "rejects a proposer Actor from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.create_place(%{
                 event_id: ctx.event.id,
                 type: "edificio",
                 canonical_name: "Torre tres",
                 proposed_by_actor_id: agent!(ctx.other).id
               })
    end

    test "rejects a source Post from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.create_place(%{
                 event_id: ctx.event.id,
                 type: "edificio",
                 canonical_name: "Torre cuatro",
                 proposed_from_post_id: post!(ctx.other).id
               })
    end
  end

  describe "Theme proposed_by" do
    test "records the Actor and the Post", ctx do
      theme =
        Taxonomy.create_theme!(%{
          event_id: ctx.event.id,
          name: "rescate",
          applies_when: "the post asserts that a person was pulled out alive",
          nature: :happening,
          proposed_by_actor_id: ctx.agent.id,
          proposed_from_post_id: ctx.post.id
        })

      assert theme.proposed_by_actor_id == ctx.agent.id
      assert theme.proposed_from_post_id == ctx.post.id
    end

    test "rejects provenance from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.create_theme(%{
                 event_id: ctx.event.id,
                 name: "damnificados",
                 applies_when: "the post states that people were displaced from their homes",
                 nature: :topic,
                 proposed_from_post_id: post!(ctx.other).id
               })
    end
  end

  describe "Author Tag proposed_by" do
    test "records the Actor and the Post", ctx do
      tag =
        Taxonomy.create_author_tag!(%{
          event_id: ctx.event.id,
          name: "rescatista",
          proposed_by_actor_id: ctx.agent.id,
          proposed_from_post_id: ctx.post.id
        })

      assert tag.proposed_by_actor_id == ctx.agent.id
      assert tag.proposed_from_post_id == ctx.post.id
    end

    test "rejects provenance from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Taxonomy.create_author_tag(%{
                 event_id: ctx.event.id,
                 name: "vocero",
                 proposed_by_actor_id: agent!(ctx.other).id
               })
    end
  end
end
