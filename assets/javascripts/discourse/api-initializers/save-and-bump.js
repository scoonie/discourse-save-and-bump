import { apiInitializer } from "discourse/lib/api";
import Composer from "discourse/models/composer";

export default apiInitializer("1.0", () => {
  // Register save_and_bump as a serialized field for post update requests.
  // When model.saveAndBump is truthy it will be included in the PUT /posts/:id
  // payload as save_and_bump=true, triggering the silent bump on the server.
  Composer.serializeOnUpdate("save_and_bump", "saveAndBump");
});
