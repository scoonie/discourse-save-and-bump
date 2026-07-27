# frozen_string_literal: true

# name: discourse-save-and-bump
# about: Adds a "Save & Bump" button when editing the first post, allowing TL4+ and staff to bump the topic to the top of the activity feed.
# version: 2.0.0
# authors: scoonie
# url: https://github.com/scoonie/discourse-save-and-bump

enabled_site_setting :save_and_bump_enabled

after_initialize do
  SAVE_AND_BUMP_CF = "save_and_bump_requested"

  register_post_custom_field_type(SAVE_AND_BUMP_CF, :boolean)

  # Allow the save_and_bump param to be sent on post update requests.
  # When the client sends save_and_bump=true, we store a transient custom
  # field on the post so the :should_bump_topic modifier can read it later
  # in the same PostRevisor lifecycle.
  add_permitted_post_update_param(:save_and_bump) do |post, value|
    if ActiveModel::Type::Boolean.new.cast(value)
      post.custom_fields[SAVE_AND_BUMP_CF] = true
      post.save_custom_fields
    end
  end

  # Hook into PostRevisor's bump decision. Returns true to trigger a silent
  # bump via core's PostRevisor#bump_topic (no visible post created), false
  # to suppress bumping, or nil to defer to Discourse's default logic.
  #
  # Modifier parameters:
  #   _result       - the accumulated return value from prior modifiers (nil initially)
  #   post          - the Post being revised
  #   _post_changes - hash of raw-content changes (unused here)
  #   _topic_changes - hash of topic-attribute changes (unused here)
  #   editor        - the User performing the edit
  register_modifier(:should_bump_topic) do |_result, post, _post_changes, _topic_changes, editor|
    # Guard: only handle requests that carry our save-and-bump flag.
    # The ensure block below only runs when this check passes.
    next nil unless post.custom_fields[SAVE_AND_BUMP_CF]

    begin
      allowed =
        SiteSetting.save_and_bump_enabled &&
          (editor.staff? || editor.trust_level >= SiteSetting.save_and_bump_minimum_trust_level.to_i)

      next false unless allowed

      unless SiteSetting.save_and_bump_show_on_all_edits
        next false unless post.post_number == 1
      end

      true
    ensure
      # Clear the transient flag now that it has been consumed, so future
      # normal edits on this post do not accidentally bump the topic.
      post.custom_fields.delete(SAVE_AND_BUMP_CF)
      post.save_custom_fields
    end
  end
end
