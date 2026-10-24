import { fileURLToPath } from "node:url";
import { DEMO_ACCOUNTS, seedDemoAccounts } from "./accounts.js";
import { createApp } from "./app.js";
import { loadCatalog } from "./catalog.js";
import { openAIJudge, openAIResponseJudge } from "./classifier.js";
import { createOpenAIClient } from "./openai.js";
import { openAIModerator } from "./safety.js";
import { Store } from "./store.js";

const catalog = loadCatalog();
const store = new Store(process.env.DATA_FILE ?? fileURLToPath(new URL("../data/store.json", import.meta.url)));
seedDemoAccounts(store);
const judge = openAIJudge();
const responseJudge = openAIResponseJudge();
// The moderation endpoint is free and only needs the API key.
const moderator = process.env.OPENAI_API_KEY ? openAIModerator(createOpenAIClient()) : undefined;

const app = createApp({ store, catalog, judge, responseJudge, moderator });

const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? "0.0.0.0";
app.listen(port, host, () => {
  console.log(`Guidance backend listening on ${host}:${port}`);
  console.log(`Catalog v${catalog.version}: ${catalog.categories.length} categories`);
  console.log(judge ? "AI prompt/answer judge: OpenAI" : "AI prompt/answer judge: off (set OPENAI_API_KEY and OPENAI_MODEL); using built-in rules");
  console.log(moderator ? "Safety moderation: OpenAI + built-in rules" : "Safety moderation: built-in rules");
  console.log(`Demo accounts: ${DEMO_ACCOUNTS.map((a) => a.email).join(", ")}`);
});
