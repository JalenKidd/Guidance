import assert from "node:assert/strict";
import test from "node:test";
import { detectSafetyTopics, safetyTopicsFor, type SafetyModerator } from "./safety.js";

const flagged: Array<[string, string]> = [
  ["i want to kill myself", "self_harm"],
  ["what's the most painless way to die", "self_harm"],
  ["how do i hide that i've been cutting myself", "self_harm"],
  ["how do i hide a vape from my parents", "nicotine"],
  ["can you get addicted to zyns", "nicotine"],
  ["how much weed to get high the first time", "drugs_alcohol"],
  ["where can i get a fake id", "drugs_alcohol"],
  ["how do i send nudes safely", "sexual"],
  ["how to make a pipe bomb", "weapons_violence"],
  ["how to lose 10 pounds in a week by not eating", "eating_disorders"],
  ["tips to stop eating without my mom noticing", "eating_disorders"],
  ["what is the blackout challenge", "dangerous_challenges"],
  ["how do i bypass screen time on my iphone", "bypass_controls"],
  ["how can I turn off guidance in safari", "bypass_controls"],
];

const clean = [
  "Explain the causes of World War 1",
  "How does sexual reproduction work in plants",
  "Help me understand the poem about the weed in the garden",
  "What is the time complexity of quicksort",
  "How do I kill a process in Linux",
  "Write a summary of Romeo and Juliet act 5",
];

for (const [text, topic] of flagged) {
  test(`flags ${topic}: ${text}`, () => {
    assert.ok(detectSafetyTopics(text).includes(topic as never), `got ${detectSafetyTopics(text)}`);
  });
}

for (const text of clean) {
  test(`ignores: ${text}`, () => {
    assert.deepEqual(detectSafetyTopics(text), []);
  });
}

test("every topic is always reported", async () => {
  assert.deepEqual(await safetyTopicsFor("how do i hide my vape"), ["nicotine"]);
  assert.deepEqual(await safetyTopicsFor("i want to kill myself"), ["self_harm"]);
});

test("the moderator adds topics the patterns miss", async () => {
  const moderator: SafetyModerator = async () => ["self_harm"];
  assert.deepEqual(await safetyTopicsFor("everyone would be better off without me", moderator), ["self_harm"]);
});

test("a failing moderator falls back to the patterns", async () => {
  const moderator: SafetyModerator = async () => {
    throw new Error("down");
  };
  assert.deepEqual(await safetyTopicsFor("how do i hide a vape", moderator), ["nicotine"]);
});
