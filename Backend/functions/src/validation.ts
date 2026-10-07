import { z } from "zod";

export const chatRequestSchema = z.object({
  conversation: z
    .array(
      z.object({
        role: z.enum(["user", "assistant"]),
        content: z.string().trim().min(1).max(8000),
      })
    )
    .min(1)
    .max(40),
  policy: z.object({
    mode: z.enum(["learning", "standard", "restricted"]),
    customInstructions: z.string().max(2000).optional().default(""),
    requireAttemptFirst: z.boolean().optional().default(true),
    allowFullAssignmentGeneration: z.boolean().optional().default(false),
  }),
});

export type ChatRequest = z.infer<typeof chatRequestSchema>;
