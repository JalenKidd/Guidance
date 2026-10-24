import { readFileSync } from "node:fs";
import { z } from "zod";
import { categoryStateSchema, domainSchema, type KidPolicy } from "./validation.js";

const categorySchema = z.object({
  id: z.string().regex(/^[a-z][a-z0-9-]{1,39}$/),
  name: z.string().min(1),
  description: z.string(),
  icon: z.string(),
  supportsGuided: z.boolean(),
  defaultState: categoryStateSchema,
  domains: z.array(domainSchema).min(1),
});

export const catalogSchema = z
  .object({
    version: z.number().int().positive(),
    categories: z.array(categorySchema).min(1),
  })
  .superRefine((catalog, ctx) => {
    const seenIds = new Set<string>();
    const seenDomains = new Map<string, string>();
    for (const category of catalog.categories) {
      if (seenIds.has(category.id)) {
        ctx.addIssue({ code: "custom", message: `Duplicate category id ${category.id}` });
      }
      seenIds.add(category.id);
      for (const domain of category.domains) {
        const owner = seenDomains.get(domain);
        if (owner) {
          ctx.addIssue({ code: "custom", message: `${domain} is in both ${owner} and ${category.id}` });
        }
        seenDomains.set(domain, category.id);
      }
    }
  });

export type Catalog = z.infer<typeof catalogSchema>;

/** catalog.json sits next to package.json, so this path works from both src/ and dist/. */
const catalogURL = new URL("../catalog.json", import.meta.url);

export function loadCatalog(): Catalog {
  return catalogSchema.parse(JSON.parse(readFileSync(catalogURL, "utf8")));
}

export function defaultPolicy(catalog: Catalog): KidPolicy {
  return {
    masterAIOff: false,
    categories: Object.fromEntries(catalog.categories.map((c) => [c.id, c.defaultState])),
    siteOverrides: {},
    schedules: [],
    guidedRules: {
      blockHomeworkOffloading: true,
      requireAttemptFirst: true,
      hideFinishedAnswers: true,
      globalInstructions: [],
    },
    temporaryAllows: [],
  };
}
