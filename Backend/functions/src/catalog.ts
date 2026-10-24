import { readFileSync } from "node:fs";
import { z } from "zod";
import { categoryStateSchema, domainSchema, type KidPolicy } from "./validation.js";

const appSchema = z.object({
  id: z.string().regex(/^[a-z][a-z0-9-]{1,39}$/),
  name: z.string().min(1),
  domains: z.array(domainSchema).min(1),
  /** Who the app is for, including its minimum age when known. */
  audience: z.string(),
  /** Short facts a parent should know. */
  quirks: z.array(z.string()).default([]),
});

const categorySchema = z.object({
  id: z.string().regex(/^[a-z][a-z0-9-]{1,39}$/),
  name: z.string().min(1),
  description: z.string(),
  icon: z.string(),
  supportsGuided: z.boolean(),
  defaultState: categoryStateSchema,
  domains: z.array(domainSchema).min(1),
  apps: z.array(appSchema).default([]),
});

export const catalogSchema = z
  .object({
    version: z.number().int().positive(),
    categories: z.array(categorySchema).min(1),
  })
  .superRefine((catalog, ctx) => {
    const seenIds = new Set<string>();
    const seenDomains = new Map<string, string>();
    const seenAppDomains = new Set<string>();
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
      for (const app of category.apps) {
        if (seenIds.has(`app:${app.id}`)) {
          ctx.addIssue({ code: "custom", message: `Duplicate app id ${app.id}` });
        }
        seenIds.add(`app:${app.id}`);
        for (const domain of app.domains) {
          if (!category.domains.includes(domain)) {
            ctx.addIssue({ code: "custom", message: `${app.id} lists ${domain}, which isn't in ${category.id}` });
          }
          if (seenAppDomains.has(domain)) {
            ctx.addIssue({ code: "custom", message: `${domain} is in more than one app` });
          }
          seenAppDomains.add(domain);
        }
      }
    }
  });

export type Catalog = z.infer<typeof catalogSchema>;

/** catalog.json sits next to package.json, so this path works from both src/ and dist/. */
const catalogURL = new URL("../catalog.json", import.meta.url);

export function loadCatalog(): Catalog {
  return catalogSchema.parse(JSON.parse(readFileSync(catalogURL, "utf8")));
}

/** The catalog app a site belongs to, matching subdomains too (www.chatgpt.com → chatgpt). */
export function appForSite(catalog: Catalog, site: string) {
  for (const category of catalog.categories) {
    const app = category.apps.find((a) => a.domains.some((d) => site === d || site.endsWith(`.${d}`)));
    if (app) return app;
  }
  return undefined;
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
    appInstructions: {},
  };
}
