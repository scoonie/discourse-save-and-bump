import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";

export default class SaveAndBumpButton extends Component {
  @service appEvents;
  @service composer;
  @service currentUser;
  @service siteSettings;
  @service toasts;

  @tracked isSaving = false;
  _pendingSaveCallback = null;
  _isDestroying = false;

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
  saveAndBump() {
    if (this.isSaving) return;
    this.isSaving = true;

    const model = this.composer.model;
    if (!model) {
      this.isSaving = false;
      return;
    }

    // Set the flag on the composer model. The api-initializer registers
    // Composer.serializeOnUpdate("save_and_bump", "saveAndBump"), so this
    // value is automatically included in the PUT /posts/:id payload, where
    // the backend's :should_bump_topic modifier performs the silent bump.
    model.saveAndBump = true;

    // Grab references to services before the component may be torn down
    // when the composer closes after a successful save.
    const toasts = this.toasts;
    const appEvents = this.appEvents;

    // Use appEvents to detect save completion. This is more reliable than
    // awaiting composer.save() because:
    // 1. DButton's INP optimization wraps actions in next(), making async
    //    return values unreliable.
    // 2. composer.save() closes the composer on success, destroying this
    //    component mid-operation. Setting tracked properties on a destroyed
    //    Glimmer component throws silently.
    // 3. The appEvents service survives component destruction.
    const onSaved = () => {
      this._pendingSaveCallback = null;
      appEvents.off("composer:saved", this, onSaved);
      toasts.success({
        duration: 3000,
        data: { message: i18n("save_and_bump.success") },
      });
    };

    this._pendingSaveCallback = onSaved;
    appEvents.on("composer:saved", this, onSaved);

    // Perform the normal save via the composer service.
    // If save fails, Discourse shows its own error handling. Clean up
    // our listener on rejection or synchronous early return.
    const saveResult = this.composer.save(true);

    // Handle the case where save() returns a promise that rejects or
    // returns undefined (early return from validation failure).
    if (saveResult && typeof saveResult.then === "function") {
      saveResult.catch(() => {
        // Save failed - clean up listener and reset state
        this._pendingSaveCallback = null;
        appEvents.off("composer:saved", this, onSaved);
        this._resetSaveState();
      });
    } else {
      // save() returned synchronously (validation failure / early return).
      // The composer:saved event won't fire, so clean up immediately.
      this._pendingSaveCallback = null;
      appEvents.off("composer:saved", this, onSaved);
      this._resetSaveState();
    }
  }

  _resetSaveState() {
    if (this.composer.model) {
      this.composer.model.saveAndBump = false;
    }
    if (!this._isDestroying) {
      this.isSaving = false;
    }
  }

  willDestroy() {
    this._isDestroying = true;
    super.willDestroy(...arguments);
    // Clean up any pending event listener if component is destroyed
    // before save completes (e.g. user navigates away).
    if (this._pendingSaveCallback) {
      this.appEvents.off("composer:saved", this, this._pendingSaveCallback);
      this._pendingSaveCallback = null;
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

