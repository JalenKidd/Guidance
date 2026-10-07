import express from "express";
import { handleChat } from "./chat.js";
import { chatRequestSchema } from "./validation.js";

const app = express();
app.use(express.json({ limit: "256kb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.post("/chat", async (req, res) => {
  const parsed = chatRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: "Invalid request." });
  }

  const last = parsed.data.conversation[parsed.data.conversation.length - 1];
  if (last.role !== "user") {
    return res.status(400).json({ error: "Last message must be from the user." });
  }

  try {
    const result = await handleChat(parsed.data);
    res.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Assistant error";
    if (message.includes("OPENAI")) {
      return res.status(503).json({ error: "Assistant service is not configured." });
    }
    console.error("Chat error:", message);
    res.status(502).json({ error: "Could not generate a response. Try again." });
  }
});

const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => {
  console.log(`GuideAI backend listening on port ${port}`);
});
