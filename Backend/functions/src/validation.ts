import { z } from "zod";

export const categoryStateSchema = z.enum(["allow", "guided", "block"]);
export type CategoryState = z.infer<typeof categoryStateSchema>;

/** Bare hostname such as "quillbot.com" (no scheme, path, or port). */
export const domainSchema = z
  .string()
  .trim()
  .toLowerCase()
  .max(253)
  .regex(/^(?!-)[a-z0-9-]+(\.[a-z0-9-]+)+$/, "Enter a domain like example.com");

const timeSchema = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use 24-hour HH:MM");
const categoryIdSchema = z.string().max(40);

export const scheduleSchema = z.object({
  id: z.string().min(1).max(40),
  name: z.string().trim().min(1).max(60),
  enabled: z.boolean().default(true),
  /** 0 = Sunday … 6 = Saturday, matching JavaScript's Date.getDay(). */
  days: z.array(z.number().int().min(0).max(6)).min(1).max(7),
  start: timeSchema,
  end: timeSchema,
  masterAIOff: z.boolean().default(false),
  categories: z.record(categoryIdSchema, categoryStateSchema).default({}),
});

export const kidPolicySchema = z.object({
  masterAIOff: z.boolean().default(false),
  categories: z.record(categoryIdSchema, categoryStateSchema).default({}),
  /** "guided" only takes effect on sites whose category supports Guided (chatbots). */
  siteOverrides: z.record(domainSchema, z.enum(["allow", "guided", "block"])).default({}),
  schedules: z.array(scheduleSchema).max(20).default([]),
  guidedRules: z
    .object({
      blockHomeworkOffloading: z.boolean().default(true),
      requireAttemptFirst: z.boolean().default(true),
      /** Hide AI answers that hand over finished schoolwork, and show hints instead. */
      hideFinishedAnswers: z.boolean().default(true),
      globalInstructions: z.array(z.string().trim().min(1).max(300)).max(10).default([]),
    })
    .default({}),
  /** Extra Guided instructions for one catalog app, keyed by app id. */
  appInstructions: z
    .record(categoryIdSchema, z.array(z.string().trim().min(1).max(300)).max(5))
    .default({}),
  /** Approved "Ask a parent" requests. They beat every other rule until they expire. */
  temporaryAllows: z
    .array(
      z.object({
        domain: domainSchema,
        until: z.string().datetime(),
        requestId: z.string().max(64).optional(),
      })
    )
    .max(20)
    .default([]),
});

export type KidPolicy = z.infer<typeof kidPolicySchema>;
export type GuidedRules = KidPolicy["guidedRules"];

/** Transport metadata stays separate from the actual rule policy. */
export const policyUpdateSchema = kidPolicySchema.extend({
  changeId: z.string().trim().min(1).max(128).optional(),
});

export const policyAppliedSchema = z.object({
  policyRevision: z.number().int().positive().safe(),
});

export const familySchema = z.object({
  parentName: z.string().trim().min(1).max(40).optional(),
});

export const signInSchema = z.object({
  email: z.string().trim().toLowerCase().max(254),
  password: z.string().max(200),
});

export const createKidSchema = z.object({
  name: z.string().trim().min(1).max(40),
});

export const pairSchema = z.object({
  code: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z0-9]{6}$/, "Pairing codes are 6 letters or numbers"),
});

export const checkRequestSchema = z.object({
  site: domainSchema,
  prompt: z.string().trim().min(1).max(8000),
  /** "guided": homework rules + safety alerts. "safety": safety alerts only (chatbot set to Allow). */
  mode: z.enum(["guided", "safety"]).default("guided"),
});

export const eventTypeSchema = z.enum(["blocked", "guided_block", "guided_allow", "answer_hidden", "heartbeat"]);

export const eventsRequestSchema = z.object({
  events: z
    .array(
      z.object({
        type: eventTypeSchema,
        domain: domainSchema.optional(),
        categoryId: categoryIdSchema.optional(),
        reason: z.string().max(300).optional(),
        at: z.string().datetime().optional(),
      })
    )
    .min(1)
    .max(50),
});

export const suggestionSchema = z.object({
  domain: domainSchema,
  categoryId: categoryIdSchema.optional(),
  note: z.string().trim().max(300).optional(),
});

export const checkResponseSchema = z.object({
  site: domainSchema,
  prompt: z.string().trim().max(8000).default(""),
  response: z.string().trim().min(1).max(30000),
});

export const accessRequestSchema = z.object({
  domain: domainSchema,
  categoryId: categoryIdSchema.optional(),
  /** "site": open a blocked site. "guided": use a Guided chatbot without homework checks. */
  kind: z.enum(["site", "guided"]),
  reason: z.string().trim().min(3, "Tell your parent why you need it").max(300),
  minutes: z.number().int().refine((m) => [15, 30, 60].includes(m), "Pick 15, 30 or 60 minutes"),
});

export const requestDecisionSchema = z.object({
  approve: z.boolean(),
  /** Parents can grant a different length than the kid asked for. */
  minutes: z.number().int().min(5).max(240).optional(),
});
