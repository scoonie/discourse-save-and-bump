# frozen_string_literal: true

# name: discourse-save-and-bump
# about: Adds a "Save & Bump" button when editing the first post, allowing TL4+ and staff to bump the topic to the top of the activity feed.
# version: 1.2.0
# authors: scoonie
# url: https://github.com/scoonie/discourse-save-and-bump

enabled_site_setting :save_and_bump_enabled

after_initialize do
  module ::DiscourseSaveAndBump
    PLUGIN_NAME = "discourse-save-and-bump"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseSaveAndBump
    end

    class SaveAndBumpController < ::ApplicationController
      requires_plugin PLUGIN_NAME
      requires_login

      def bump
        topic = Topic.find(params[:topic_id])

        # Ensure the user can see the topic
        guardian.ensure_can_see!(topic)

        # Permission: feature must be enabled, and user must be staff or meet minimum trust level.
        # Staff and trusted users only need to be able to see the topic (checked above); they do
        # not need edit permission on the post in order to bump.
        allowed =
          SiteSetting.save_and_bump_enabled &&
          (current_user.staff? ||
            current_user.trust_level >= SiteSetting.save_and_bump_minimum_trust_level)

        raise Discourse::InvalidAccess unless allowed

        # Rate limit: max 5 bumps per topic per hour per user
        RateLimiter.new(current_user, "save_and_bump_#{topic.id}", 5, 1.hour).performed!

        # Bump the topic by setting bumped_at to now and publishing
        # the change so that topic list caches are invalidated.
        # This mirrors Discourse core's PostRevisor#bump_topic behaviour.
        now = Time.zone.now
        topic.update_columns(bumped_at: now, updated_at: now)
        TopicTrackingState.publish_muted(topic)
        TopicTrackingState.publish_unmuted(topic)
        TopicTrackingState.publish_latest(topic)

        # Log the action for audit trail
        StaffActionLogger.new(current_user).log_custom(
          "save_and_bump",
          topic_id: topic.id,
          topic_title: topic.title,
          bumped_at: now.iso8601,
        )

        render json: success_json
      end
    end
  end

  DiscourseSaveAndBump::Engine.routes.draw do
    post "/topics/:topic_id/bump" => "save_and_bump#bump"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseSaveAndBump::Engine, at: "/discourse-save-and-bump"
  end
end
