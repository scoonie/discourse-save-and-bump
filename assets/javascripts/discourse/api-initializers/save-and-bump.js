import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default apiInitializer("1.0", (api) => {
  api.addTopicFooterButton({
    id: "save-and-bump",
    icon: "arrow-up",
    label: "save_and_bump.bump_button_label",
    title: "save_and_bump.bump_button_title",

    displayed() {
      const siteSettings = api.container.lookup("service:site-settings");
      const currentUser = api.getCurrentUser();

      if (!siteSettings.save_and_bump_enabled) return false;
      if (!currentUser) return false;
      if (currentUser.staff) return true;

      const minTL = siteSettings.save_and_bump_minimum_trust_level;
      return (currentUser.trust_level ?? 0) >= minTL;
    },

    action() {
      const topic = this.topic;
      if (!topic?.id) return;

      const toasts = api.container.lookup("service:toasts");

      ajax(`/discourse-save-and-bump/topics/${topic.id}/bump`, {
        type: "POST",
      })
        .then(() => {
          toasts.success({
            duration: 3000,
            data: { message: i18n("save_and_bump.bump_success") },
          });
        })
        .catch(() => {
          toasts.error({
            duration: 5000,
            data: { message: i18n("save_and_bump.bump_error") },
          });
        });
    },
  });
});
