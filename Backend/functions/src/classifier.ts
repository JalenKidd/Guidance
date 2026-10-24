import { createOpenAIClient, resolveModel } from "./openai.js";
import type { GuidedRules } from "./validation.js";

export type OffloadingKind = "essay" | "math" | "answers" | "humanize";

export interface CheckDecision {
  action: "allow" | "block";
  reason: string;
  /** A learning-style prompt the student can send instead of the blocked one. */
  suggestedPrompt?: string;
  /** Parent rules appended to allowed prompts before they reach the AI site. */
  instructions: string;
  source: "rules" | "ai";
}

export interface AIVerdict {
  offloading: boolean;
  kind: OffloadingKind | null;
  reason: string;
}

export type AIJudge = (prompt: string, rules: GuidedRules) => Promise<AIVerdict>;

const OFFLOADING_PATTERNS: Array<{ kind: OffloadingKind; pattern: RegExp }> = [
  {
    kind: "humanize",
    pattern: /\b(humani[sz]e|undetectable|bypass|avoid|pass|beat|fool)\b.{0,40}\b(ai[ -]?detect\w*|turnitin|gptzero|plagiarism|detector)/i,
  },
  {
    kind: "humanize",
    pattern: /\b(rewrite|reword|paraphrase)\b.{0,60}\b(so (it|my teacher)|sound (human|like me)|not (look|sound) like ai)/i,
  },
  {
    kind: "essay",
    pattern: /\b(write|do|finish|complete|make|type|draft)\b.{0,30}\b(my|this|the|an?|\d+[- ]?(paragraph|page|word))\b.{0,40}\b(essay|paper|report|assignment|homework|discussion post|book report|lab report|worksheet|project|paragraphs?|poem|story|speech)\b/i,
  },
  {
    kind: "essay",
    pattern: /\b\d+[- ]?(paragraph|page|word)s?\b.{0,40}\b(essay|paper|report|response)\b/i,
  },
  {
    kind: "math",
    pattern: /\b(solve|do|answer|finish|complete)\b.{0,30}\b(this|these|all|my|the following|each)\b.{0,40}\b(problems?|questions?|equations?|worksheet|homework|for me)\b/i,
  },
  {
    kind: "answers",
    pattern: /\b(just|only)\s+(give|tell|send)\s+me\s+the\s+(final\s+)?answers?\b/i,
  },
  {
    kind: "answers",
    pattern: /\b(answers?|answer key|solutions?)\b.{0,20}\b(to|for)\b.{0,30}\b(my |the |this )?(homework|worksheet|test|quiz|exam|assignment|study guide)\b/i,
  },
];

/** "How do I write a conclusion?" is asking to learn, even though it mentions writing one. */
const LEARNING_FRAMING = /^\s*(how (do|can|should|would) (i|you|we)|how to|what('s| is) (a|the) (best |right )?way to|tips (for|on)|help me (understand|learn|plan|outline|brainstorm|study|practice)|explain|teach me)\b/i;

export function detectOffloading(prompt: string): OffloadingKind | null {
  if (LEARNING_FRAMING.test(prompt)) return null;
  for (const { kind, pattern } of OFFLOADING_PATTERNS) {
    if (pattern.test(prompt)) return kind;
  }
  return null;
}

export function buildInstructions(rules: GuidedRules): string {
  const lines: string[] = [];
  if (rules.blockHomeworkOffloading) {
    lines.push("I'm a student. Help me learn instead of doing graded work for me: explain step by step and don't hand me ready-to-submit answers.");
  }
  if (rules.requireAttemptFirst) {
    lines.push("If this is schoolwork, ask what I've tried before giving a full solution.");
  }
  lines.push(...rules.globalInstructions);
  if (lines.length === 0) return "";
  return `(Parent rules from Guidance: ${lines.join(" ")})`;
}

const REASONS: Record<OffloadingKind, string> = {
  essay: "This asks the AI to write the assignment for you.",
  math: "This asks the AI to do the problems for you.",
  answers: "This asks for answers instead of help understanding.",
  humanize: "This tries to hide AI-written work from a teacher.",
};

const SUGGESTIONS: Record<OffloadingKind, string> = {
  essay: "Don't write this for me. Help me brainstorm a thesis and an outline for my assignment, then give me feedback on my draft.",
  math: "Don't solve this for me. Explain the method for this kind of problem with a similar example, then let me try mine and check my work.",
  answers: "Don't give me the answers. Quiz me one question at a time and give me a hint when I get stuck.",
  humanize: "Help me improve my own writing: point out unclear sentences in my draft and explain how I could fix them myself.",
};

function blockDecision(kind: OffloadingKind | null, reason: string | undefined, instructions: string, source: CheckDecision["source"]): CheckDecision {
  const k = kind ?? "answers";
  return {
    action: "block",
    reason: reason || REASONS[k],
    suggestedPrompt: SUGGESTIONS[k],
    instructions,
    source,
  };
}

const AI_TIMEOUT_MS = 4000;

/**
 * Decide whether a prompt typed on a Guided AI site goes through.
 * Clear-cut offloading is caught by local patterns with no network call; anything
 * else is passed to the AI judge when one is configured. An unavailable or slow
 * judge never blocks the student.
 */
export async function checkPrompt(prompt: string, rules: GuidedRules, judge?: AIJudge): Promise<CheckDecision> {
  const instructions = buildInstructions(rules);
  const allow: CheckDecision = { action: "allow", reason: "Allowed with your parent's rules.", instructions, source: "rules" };

  if (!rules.blockHomeworkOffloading) return allow;

  const kind = detectOffloading(prompt);
  if (kind) return blockDecision(kind, undefined, instructions, "rules");

  if (!judge) return allow;

  try {
    const verdict = await Promise.race([
      judge(prompt, rules),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("judge timeout")), AI_TIMEOUT_MS)),
    ]);
    if (verdict.offloading) return blockDecision(verdict.kind, verdict.reason, instructions, "ai");
    return { ...allow, source: "ai" };
  } catch (err) {
    console.warn("AI judge unavailable, allowing:", err instanceof Error ? err.message : err);
    return allow;
  }
}

const JUDGE_INSTRUCTIONS = `You review prompts a student is about to send to an AI chatbot, on behalf of their parent.
Decide if the prompt is "cognitive offloading": asking the AI to produce graded schoolwork the student should do themselves
(write an essay/assignment, solve homework problems, give test or worksheet answers, or disguise AI-written work).
Asking for explanations, hints, feedback on the student's own work, brainstorming, studying, or ordinary questions is NOT offloading.
When unsure, answer offloading=false. Keep reason to one short sentence addressed to the student.`;

/** Returns an OpenAI-backed judge, or undefined when OPENAI_API_KEY / OPENAI_MODEL aren't set. */
export function openAIJudge(): AIJudge | undefined {
  if (!process.env.OPENAI_API_KEY || !process.env.OPENAI_MODEL) return undefined;
  const client = createOpenAIClient();
  const model = resolveModel();

  return async (prompt, rules) => {
    const extra = rules.globalInstructions.length
      ? `\nParent's own rules (also count prompts that clearly break these): ${rules.globalInstructions.join(" | ")}`
      : "";
    const response = await client.responses.create({
      model,
      instructions: JUDGE_INSTRUCTIONS + extra,
      input: prompt,
      text: {
        format: {
          type: "json_schema",
          name: "offloading_verdict",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: ["offloading", "kind", "reason"],
            properties: {
              offloading: { type: "boolean" },
              kind: { type: ["string", "null"], enum: ["essay", "math", "answers", "humanize", null] },
              reason: { type: "string" },
            },
          },
        },
      },
    });
    return JSON.parse(response.output_text) as AIVerdict;
  };
}

// ---- AI answers ----

export interface ResponseDecision {
  action: "show" | "hide";
  reason: string;
  /** Shown instead of the hidden answer, so the student still gets help. */
  hints: string[];
  source: "rules" | "ai";
}

export interface ResponseVerdict {
  finishedWork: boolean;
  kind: OffloadingKind | null;
  hints: string[];
}

export type ResponseJudge = (prompt: string, response: string) => Promise<ResponseVerdict>;

const SCHOOL_CONTEXT = /\b(essay|assignment|homework|worksheet|paper|report|due|teacher|class|grade|turn (it )?in|submit|quiz|test|exam|problem set|lab|paragraphs?)\b/i;

/**
 * Cheap check for an AI answer that hands over finished schoolwork. Only fires when
 * the prompt is about schoolwork. A ready-to-submit essay is long, paragraph-shaped
 * and written in the third person; feedback on a student's draft talks to "you".
 */
export function looksLikeFinishedWork(prompt: string, response: string): OffloadingKind | null {
  if (!SCHOOL_CONTEXT.test(prompt) && !detectOffloading(prompt)) return null;

  const words = response.split(/\s+/).filter(Boolean);
  const paragraphs = response.split(/\n\s*\n/).filter((p) => p.trim().split(/\s+/).length >= 25);
  const secondPerson = words.filter((w) => /^(you|your|you're|yours)\b/i.test(w)).length / Math.max(words.length, 1);
  if (words.length >= 300 && paragraphs.length >= 4 && secondPerson < 0.015) return "essay";

  const finalAnswers = response.match(/(final answer|answer:|the answer is|∴|\\boxed\{)/gi) ?? [];
  if (finalAnswers.length >= 2) return "math";

  return null;
}

const HINTS: Record<OffloadingKind, string[]> = {
  essay: [
    "Write your thesis in one sentence first. What's the main thing you want to prove?",
    "List three reasons or pieces of evidence that support it, then pick the strongest one to start with.",
    "Draft one paragraph yourself, then ask the AI for feedback on it.",
  ],
  math: [
    "Write down what the problem gives you and what it asks for.",
    "Which formula or method connects them? Ask the AI to explain that method with a different example.",
    "Try the first step yourself, then ask the AI to check it.",
  ],
  answers: [
    "Try answering in your own words first, even if you're unsure.",
    "Ask the AI for a hint about just the part you're stuck on.",
    "Ask it to quiz you on the topic instead.",
  ],
  humanize: [
    "Read your draft out loud and mark sentences that don't sound like you.",
    "Ask the AI which sentences are unclear and why, then rewrite them yourself.",
    "Ask your teacher what counts as acceptable AI help for this assignment.",
  ],
};

const RESPONSE_REASONS: Record<OffloadingKind, string> = {
  essay: "Guidance hid this answer because it's a finished piece of writing you could turn in.",
  math: "Guidance hid this answer because it gives away the final answers.",
  answers: "Guidance hid this answer because it hands over the answers.",
  humanize: "Guidance hid this answer because it rewrites work to hide AI use.",
};

const RESPONSE_TIMEOUT_MS = 6000;

/** Decide whether an AI site's answer on a Guided chatbot is shown or swapped for hints. */
export async function checkResponse(
  prompt: string,
  response: string,
  rules: GuidedRules,
  judge?: ResponseJudge
): Promise<ResponseDecision> {
  const show: ResponseDecision = { action: "show", reason: "", hints: [], source: "rules" };
  if (!rules.hideFinishedAnswers) return show;

  if (judge) {
    try {
      const verdict = await Promise.race([
        judge(prompt, response),
        new Promise<never>((_, reject) => setTimeout(() => reject(new Error("judge timeout")), RESPONSE_TIMEOUT_MS)),
      ]);
      if (!verdict.finishedWork) return { ...show, source: "ai" };
      const kind = verdict.kind ?? "answers";
      return {
        action: "hide",
        reason: RESPONSE_REASONS[kind],
        hints: verdict.hints.length ? verdict.hints.slice(0, 4) : HINTS[kind],
        source: "ai",
      };
    } catch (err) {
      console.warn("Response judge unavailable, using rules:", err instanceof Error ? err.message : err);
    }
  }

  const kind = looksLikeFinishedWork(prompt, response);
  if (!kind) return show;
  return { action: "hide", reason: RESPONSE_REASONS[kind], hints: HINTS[kind], source: "rules" };
}

const RESPONSE_JUDGE_INSTRUCTIONS = `You review an AI chatbot's answer to a student, on behalf of their parent.
Decide if the answer hands the student FINISHED graded schoolwork they could submit as their own: a complete essay or
assignment, a full set of homework answers, or final answers to problems without the student having done the work.
Explanations, examples, outlines, hints, feedback on the student's own draft, and ordinary information are NOT finished work.
If it is finished work, write 3 short hints (one sentence each, addressed to the student) that help them do it themselves
without revealing the answers. Otherwise return an empty hints list.`;

/** OpenAI-backed response judge, or undefined when OPENAI_API_KEY / OPENAI_MODEL aren't set. */
export function openAIResponseJudge(): ResponseJudge | undefined {
  if (!process.env.OPENAI_API_KEY || !process.env.OPENAI_MODEL) return undefined;
  const client = createOpenAIClient();
  const model = resolveModel();

  return async (prompt, response) => {
    const result = await client.responses.create({
      model,
      instructions: RESPONSE_JUDGE_INSTRUCTIONS,
      input: `STUDENT ASKED:\n${prompt.slice(0, 4000)}\n\nAI ANSWERED:\n${response.slice(0, 12000)}`,
      text: {
        format: {
          type: "json_schema",
          name: "response_verdict",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: ["finishedWork", "kind", "hints"],
            properties: {
              finishedWork: { type: "boolean" },
              kind: { type: ["string", "null"], enum: ["essay", "math", "answers", "humanize", null] },
              hints: { type: "array", items: { type: "string" } },
            },
          },
        },
      },
    });
    return JSON.parse(result.output_text) as ResponseVerdict;
  };
}
