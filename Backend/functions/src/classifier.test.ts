import assert from "node:assert/strict";
import test from "node:test";
import { buildInstructions, checkPrompt, checkResponse, detectOffloading, type AIJudge, type ResponseJudge } from "./classifier.js";
import type { GuidedRules } from "./validation.js";

const rules: GuidedRules = { blockHomeworkOffloading: true, requireAttemptFirst: true, hideFinishedAnswers: true, globalInstructions: [] };

const offloading: Array<[string, string]> = [
  ["write my 5 paragraph essay on the Civil War", "essay"],
  ["Can you write an essay about Romeo and Juliet for my English class", "essay"],
  ["do my homework for me", "essay"],
  ["give me a 500 word essay on climate change", "essay"],
  ["solve these problems for me: 3x+5=20, 2x-4=10", "math"],
  ["just give me the answer", "answers"],
  ["what are the answers to my chemistry worksheet", "answers"],
  ["rewrite this so my teacher can't tell it's AI", "humanize"],
  ["humanize this text so it passes turnitin", "humanize"],
];

const learning = [
  "Explain what caused the Civil War",
  "Can you help me understand how photosynthesis works?",
  "Here's my thesis, what could make it stronger?",
  "Give me a hint for factoring x^2 + 5x + 6",
  "What is the difference between mitosis and meiosis",
  "Quiz me on the French Revolution",
  "How do I write a good conclusion paragraph?",
];

for (const [prompt, kind] of offloading) {
  test(`flags offloading: ${prompt}`, () => {
    assert.equal(detectOffloading(prompt), kind);
  });
}

for (const prompt of learning) {
  test(`allows learning prompt: ${prompt}`, () => {
    assert.equal(detectOffloading(prompt), null);
  });
}

test("blocked prompts come with a reason and a learning-style alternative", async () => {
  const decision = await checkPrompt("write my essay on the Civil War", rules);
  assert.equal(decision.action, "block");
  assert.match(decision.reason, /write the assignment/);
  assert.match(decision.suggestedPrompt ?? "", /outline/);
});

test("allowed prompts carry the parent's instructions", async () => {
  const decision = await checkPrompt("Explain what caused the Civil War", {
    ...rules,
    globalInstructions: ["Keep answers at a 7th grade reading level."],
  });
  assert.equal(decision.action, "allow");
  assert.match(decision.instructions, /Parent rules from Guidance/);
  assert.match(decision.instructions, /7th grade/);
});

test("turning off the offloading rule allows everything", async () => {
  const decision = await checkPrompt("write my essay", { ...rules, blockHomeworkOffloading: false });
  assert.equal(decision.action, "allow");
});

test("instructions are empty when the parent set no rules", () => {
  assert.equal(buildInstructions({ blockHomeworkOffloading: false, requireAttemptFirst: false, hideFinishedAnswers: false, globalInstructions: [] }), "");
});

test("the AI judge catches what the patterns miss", async () => {
  const judge: AIJudge = async () => ({ offloading: true, kind: "essay", reason: "This asks for a finished book report." });
  const decision = await checkPrompt("I need something to turn in about Hatchet by tomorrow", rules, judge);
  assert.equal(decision.action, "block");
  assert.equal(decision.source, "ai");
  assert.equal(decision.reason, "This asks for a finished book report.");
});

test("pattern matches skip the AI judge", async () => {
  let called = false;
  const judge: AIJudge = async () => {
    called = true;
    return { offloading: false, kind: null, reason: "" };
  };
  await checkPrompt("write my essay", rules, judge);
  assert.equal(called, false);
});

test("a failing AI judge never blocks the student", async () => {
  const judge: AIJudge = async () => {
    throw new Error("network down");
  };
  const decision = await checkPrompt("I need something to turn in about Hatchet", rules, judge);
  assert.equal(decision.action, "allow");
});

// ---- AI answers ----

const essay = Array.from({ length: 5 }, (_, i) =>
  `Paragraph ${i + 1}. The American Civil War was shaped by deep disagreements over slavery, states' rights and economic change. ` +
  "Historians point to the expansion of slavery into western territories as a central cause, along with the collapse of compromise " +
  "and the election of 1860, which convinced many Southern leaders that secession was their only option for protecting the institution. " +
    "Economic differences between an industrializing North and an agricultural South deepened the divide over the following decades."
).join("\n\n");

test("hides a finished essay answer to a schoolwork prompt and offers hints", async () => {
  const decision = await checkResponse("I need my Civil War essay for class", essay, rules);
  assert.equal(decision.action, "hide");
  assert.equal(decision.hints.length, 3);
});

test("shows the same text when the prompt isn't schoolwork", async () => {
  const decision = await checkResponse("tell me about the civil war", essay, rules);
  assert.equal(decision.action, "show");
});

test("shows feedback on the student's own draft", async () => {
  const feedback = essay.replace(/Historians point/g, "Your draft points").replace(/The American/g, "You explain how the American") + " You could also strengthen your thesis. Your evidence is good and you should keep it.";
  const youHeavy = feedback.replace(/\. /g, ". You did well here. ");
  const decision = await checkResponse("can you give feedback on my essay draft", youHeavy, rules);
  assert.equal(decision.action, "show");
});

test("hides worked answers to a homework set", async () => {
  const response = "1) 3x + 5 = 20, so x = 5. Final answer: 5\n2) 2x - 4 = 10, so x = 7. Final answer: 7";
  const decision = await checkResponse("can you check my math homework", response, rules);
  assert.equal(decision.action, "hide");
});

test("parents can turn answer hiding off", async () => {
  const decision = await checkResponse("I need my Civil War essay for class", essay, { ...rules, hideFinishedAnswers: false });
  assert.equal(decision.action, "show");
});

test("the response judge's hints are used when available", async () => {
  const judge: ResponseJudge = async () => ({ finishedWork: true, kind: "essay", hints: ["Start with your thesis."] });
  const decision = await checkResponse("anything", "anything", rules, judge);
  assert.equal(decision.action, "hide");
  assert.deepEqual(decision.hints, ["Start with your thesis."]);
});

test("a failing response judge falls back to the rules", async () => {
  const judge: ResponseJudge = async () => {
    throw new Error("down");
  };
  const decision = await checkResponse("tell me about the civil war", essay, rules, judge);
  assert.equal(decision.action, "show");
});
