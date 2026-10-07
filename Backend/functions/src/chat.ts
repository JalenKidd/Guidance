import { buildSystemPrompt } from "./promptBuilder.js";
import { createOpenAIClient, resolveModel } from "./openai.js";
import type { ChatRequest } from "./validation.js";

export async function handleChat(body: ChatRequest) {
  const client = createOpenAIClient();
  const model = resolveModel();
  const system = buildSystemPrompt(body.policy);

  const input = [
    { role: "system" as const, content: system },
    ...body.conversation.map((m) => ({ role: m.role, content: m.content })),
  ];

  const response = await client.responses.create({
    model,
    input,
  });

  const text = response.output_text?.trim();
  if (!text) {
    throw new Error("Empty model response");
  }

  return {
    text,
    usage: {
      inputTokens: response.usage?.input_tokens,
      outputTokens: response.usage?.output_tokens,
    },
  };
}
