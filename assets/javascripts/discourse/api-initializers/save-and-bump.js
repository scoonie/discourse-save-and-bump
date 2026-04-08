import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.0", (api) => {
  // Plugin is initialized via the connector component.
  // This file ensures proper registration with Discourse's plugin system.
});
