import type OpenAI from "openai";

/**
 * Safety topics a parent is told about when their kid asks an AI about them.
 * Always on. Guidance never blocks these prompts: curiosity is normal and honest
 * information is often the safer outcome. It only notifies the parent.
 */
export const SAFETY_TOPICS = [
  { id: "self_harm", name: "Self-harm or suicide", severity: "urgent" },
  { id: "nicotine", name: "Vaping or smoking", severity: "notice" },
  { id: "drugs_alcohol", name: "Drugs or alcohol", severity: "notice" },
  { id: "sexual", name: "Sexual content", severity: "notice" },
  { id: "weapons_violence", name: "Weapons or violence", severity: "notice" },
  { id: "eating_disorders", name: "Eating disorders", severity: "notice" },
  { id: "dangerous_challenges", name: "Dangerous challenges", severity: "notice" },
  { id: "bypass_controls", name: "Getting around parental controls", severity: "notice" },
] as const;

export type SafetyTopicId = (typeof SAFETY_TOPICS)[number]["id"];
export const SAFETY_TOPIC_IDS = SAFETY_TOPICS.map((t) => t.id) as [SafetyTopicId, ...SafetyTopicId[]];

const PATTERNS: Record<SafetyTopicId, RegExp[]> = {
  self_harm: [
    /\b(kill(ing)?|hurt(ing)?|cut(ting)?|harm(ing)?) my ?self\b/i,
    /\b(end|take) my (own )?life\b/i,
    /\b(i )?(want|wanna|going) to die\b/i,
    /\bsuicid\w*/i,
    /\bself[- ]?harm\w*/i,
    /\bunalive\w*/i,
    /\bno (reason|point) (to|in) (live|living)\b/i,
    /\bhow many \w+ (pills|tablets)\b.{0,20}\b(die|dead|kill|overdose)\b/i,
    /\b(painless|easiest) way to die\b/i,
  ],
  nicotine: [/\b(vap(e|es|ing|ed)|juul|elf ?bar|geek ?bar|nicotine|zyns?|cigarettes?|cigs|smok(e|ing) (a )?(cig|blunt|joint))\b/i],
  drugs_alcohol: [
    /\b(smok(e|ing) weed|weed (pens?|carts?|edibles?)|buy(ing)? weed|marijuana|thc|dab pen|edibles?|cocaine|coke line|xanax|percs?|percocet|fentanyl|molly|mdma|lsd|acid tab|shrooms|ketamine)\b/i,
    /\bget(ting)? (drunk|high|wasted|faded)\b/i,
    /\b(vodka|tequila|fake id|buy (beer|alcohol|liquor))\b/i,
  ],
  sexual: [/\b(porn\w*|nudes?|sext\w*|onlyfans|hook ?ups?|how to have sex|lose my virginity)\b/i],
  weapons_violence: [
    /\b(make|build) (a )?(bomb|pipe bomb|gun|molotov)\b/i,
    /\b(3d[- ]?print\w*|ghost) gun\b/i,
    /\bhow (do i|to|can i) (kill|hurt|poison|stab|shoot) (someone|somebody|a person|people|him|her|them|my)\b/i,
    /\bschool shoot\w*/i,
    /\bbuy (a )?gun\b/i,
  ],
  eating_disorders: [
    /\b(pro[- ]?ana|pro[- ]?mia|thinspo\w*)\b/i,
    /\b(starve my ?self|stop eating|throw(ing)? up after (eating|meals?)|make my ?self (throw up|puke))\b/i,
    /\blose \d+ ?(lbs?|pounds|kg) in (a|one|1) (week|day)\b/i,
    /\b(under|less than) \d{3} calories (a|per) day\b/i,
  ],
  dangerous_challenges: [/\b(blackout|choking|benadryl|nyquil chicken|skull ?breaker|tide ?pod|fire) challenge\b/i, /\bchoking game\b/i],
  bypass_controls: [
    /\b(bypass|get around|disable|turn off|hack|remove|delete|get past|trick)\b.{0,30}\b(screen ?time|parental controls?|guidance|nextdns|content filter|web filter|the filter|family link|bark|qustodio|linewize|goguardian)\b/i,
    /\b(screen ?time|parental controls?) (passcode|password) (hack|bypass|crack|guess)\b/i,
  ],
};

export function detectSafetyTopics(text: string): SafetyTopicId[] {
  return SAFETY_TOPIC_IDS.filter((id) => PATTERNS[id].some((p) => p.test(text)));
}

export type SafetyModerator = (text: string) => Promise<SafetyTopicId[]>;

/** Maps OpenAI's free moderation categories onto Guidance topics. */
export function openAIModerator(client: OpenAI): SafetyModerator {
  return async (text) => {
    const result = await client.moderations.create({ model: "omni-moderation-latest", input: text });
    const c = result.results[0]?.categories as unknown as Record<string, boolean> | undefined;
    if (!c) return [];
    const topics = new Set<SafetyTopicId>();
    if (c["self-harm"] || c["self-harm/intent"] || c["self-harm/instructions"]) topics.add("self_harm");
    if (c["sexual"] || c["sexual/minors"]) topics.add("sexual");
    if (c["violence"] || c["illicit/violent"]) topics.add("weapons_violence");
    if (c["illicit"]) topics.add("drugs_alcohol");
    return [...topics];
  };
}

const MODERATION_TIMEOUT_MS = 3000;

/**
 * Safety topics in `text`. Local patterns always run; the moderator (when configured)
 * adds what they miss.
 */
export async function safetyTopicsFor(text: string, moderator?: SafetyModerator): Promise<SafetyTopicId[]> {
  const found = new Set(detectSafetyTopics(text));
  if (moderator) {
    try {
      const extra = await Promise.race([
        moderator(text),
        new Promise<never>((_, reject) => setTimeout(() => reject(new Error("moderation timeout")), MODERATION_TIMEOUT_MS)),
      ]);
      extra.forEach((t) => found.add(t));
    } catch (err) {
      console.warn("Moderation unavailable:", err instanceof Error ? err.message : err);
    }
  }
  return SAFETY_TOPIC_IDS.filter((id) => found.has(id));
}

export function topicInfo(id: SafetyTopicId) {
  return SAFETY_TOPICS.find((t) => t.id === id)!;
}
