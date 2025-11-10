# name: discourse-save-and-bump
# about: Adds a secure endpoint to "save & bump" the topic when editing the OP, with no replies
# version: 1.0.0
# authors: You
# url: https://your.repo.example/discourse-save-and-bump

enabled_site_setting :save_and_bump_tl4_enabled

after_initialize do
  module ::DiscourseSaveAndBump
    class Engine < ::Rails::Engine
      engine_name "discourse_save_and_bump"
      isolate_namespace DiscourseSaveAndBump
    end
  end

  require_dependency "application_controller"

  class DiscourseSaveAndBump::SaveAndBumpController < ::ApplicationController
    requires_login

    def update
      topic = Topic.find(params[:id])

      guardian.ensure_can_see!(topic)
      post = topic.first_post
      raise Discourse::InvalidParameters.new(:id) unless post

      guardian.ensure_can_edit!(post)

      if topic.reply_count.to_i > 0
        raise Discourse::InvalidAccess.new(I18n.t("save_and_bump.errors.has_replies"))
      end

      allowed = current_user.staff? ||
        (SiteSetting.save_and_bump_tl4_enabled && current_user.trust_level.to_i >= TrustLevel[4])

      raise Discourse::InvalidAccess.new(I18n.t("save_and_bump.errors.forbidden")) unless allowed

      RateLimiter.new(current_user, "save_and_bump", 10, 1.minute).performed!

      now = Time.zone.now
      topic.update_columns(bumped_at: now)

      StaffActionLogger.new(current_user).log_custom(
        "save_and_bump",
        topic_id: topic.id,
        topic_title: topic.title,
        bumped_at: now
      )

      render json: success_json
    end
  end

  DiscourseSaveAndBump::Engine.routes.draw do
    put "/t/:id/save-and-bump" => "save_and_bump#update"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseSaveAndBump::Engine, at: "/"
  end
end
