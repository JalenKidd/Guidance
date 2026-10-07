import assert from "node:assert/strict";
import test from "node:test";
import { buildSystemPrompt } from "./promptBuilder.js";

test("learning mode includes learning guidance", () => {
  const prompt = buildSystemPrompt({ mode: "learning", customInstructions: "" });
  assert.match(prompt, /Learning Mode/i);
  assert.match(prompt, /safety/i);
});

test("custom instructions are incorporated", () => {
  const prompt = buildSystemPrompt({
    mode: "standard",
    customInstructions: "Make the student attempt math first.",
  });
  assert.match(prompt, /attempt math first/i);
});

test("restricted and learning modes differ", () => {
  const learning = buildSystemPrompt({ mode: "learning" });
  const restricted = buildSystemPrompt({ mode: "restricted" });
  assert.notEqual(learning, restricted);
  assert.match(restricted, /Restricted Mode/i);
});
