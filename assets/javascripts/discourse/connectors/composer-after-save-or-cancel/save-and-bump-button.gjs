import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class SaveAndBumpButton extends Component {
  @service composer;
  @service currentUser;
  @service siteSettings;
  @service toasts;

  @tracked isSaving = false;

  get shouldShow() {
    const model = this.composer.model;
    if (!model) return false;

    // Only show when editing
    if (model.action !== "edit") return false;

    // Unless "show on all edits" is enabled, only show on the first post (OP)
    if (!this.siteSettings.save_and_bump_show_on_all_edits) {
      if (model.post?.post_number !== 1) return false;
    }

    // Check permissions: staff or meets minimum trust level
    if (!this.siteSettings.save_and_bump_enabled) return false;

    const minTL = this.siteSettings.save_and_bump_minimum_trust_level;
    const userTL = this.currentUser?.trust_level ?? 0;

    return this.currentUser?.staff || userTL >= minTL;
  }

  @action
  async saveAndBump() {
    if (this.isSaving) return;
    this.isSaving = true;

    // Capture IDs before save, since the composer model is cleared when
    // the composer closes after a successful save.
    const topicId = this.composer.model.topic?.id;
    const postId = this.composer.model.post?.id;

    if (!topicId) {
      this.isSaving = false;
      return;
    }

    // Grab references to services before the component may be torn down
    // when the composer closes after save.
    const toasts = this.toasts;

    try {
      // Perform the normal save via the composer service.
      // Note: composer.save() swallows errors internally so the catch
      // block below won't fire for save failures; the user will see
      // Discourse's own error handling in that case.
      await this.composer.save(true);
    } catch {
      this.isSaving = false;
      return;
    }

    try {
      // Bump the topic via our plugin endpoint
      await ajax(`/discourse-save-and-bump/topics/${topicId}/bump`, {
        type: "POST",
        data: { post_id: postId },
      });

      toasts.success({
        duration: 3000,
        data: { message: i18n("save_and_bump.success") },
      });
    } catch {
      toasts.error({
        duration: 5000,
        data: { message: i18n("save_and_bump.error") },
      });
    } finally {
      this.isSaving = false;
    }
  }

  <template>
    {{#if this.shouldShow}}
      <DButton
        @action={{this.saveAndBump}}
        @label="save_and_bump.button_label"
        @translatedTitle={{i18n "save_and_bump.button_title"}}
        @isLoading={{this.isSaving}}
        @disabled={{this.composer.disableSubmit}}
        class="btn-primary save-and-bump-btn"
      />
    {{/if}}
  </template>
}
