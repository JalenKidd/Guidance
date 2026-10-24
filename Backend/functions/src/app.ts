import express, { type NextFunction, type Request, type Response } from "express";
import { passwordMatches } from "./accounts.js";
import { appForSite, defaultPolicy, type Catalog } from "./catalog.js";
import { checkPrompt, checkResponse, type AIJudge, type ResponseJudge } from "./classifier.js";
import { safetyTopicsFor, topicInfo, type SafetyModerator } from "./safety.js";
import type { ActivityEvent, Family, Kid, Store } from "./store.js";
import {
  accessRequestSchema,
  checkRequestSchema,
  checkResponseSchema,
  createKidSchema,
  eventsRequestSchema,
  familySchema,
  kidPolicySchema,
  pairSchema,
  policyAppliedSchema,
  policyUpdateSchema,
  requestDecisionSchema,
  signInSchema,
  suggestionSchema,
  type KidPolicy,
} from "./validation.js";

interface AppOptions {
  store: Store;
  catalog: Catalog;
  judge?: AIJudge;
  responseJudge?: ResponseJudge;
  moderator?: SafetyModerator;
}

const EXCERPT_LENGTH = 500;

function bearer(req: Request): string | undefined {
  const header = req.header("authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice(7) : undefined;
}

/** Stored policy with defaults filled in (older saves) and expired approvals dropped. */
function currentPolicy(kid: Kid, now = Date.now()): KidPolicy {
  const policy = kidPolicySchema.parse(kid.policy);
  policy.temporaryAllows = policy.temporaryAllows.filter((t) => Date.parse(t.until) > now);
  return policy;
}

function publicKid(kid: Kid) {
  return {
    id: kid.id,
    name: kid.name,
    pairingCode: kid.pairingCode,
    paired: Boolean(kid.deviceToken),
    lastHeartbeat: kid.lastHeartbeat ?? null,
    policy: currentPolicy(kid),
    policyRevision: kid.policyRevision,
    appliedPolicyRevision: kid.appliedPolicyRevision,
    policyAppliedAt: kid.policyAppliedAt,
  };
}

export function createApp({ store, catalog, judge, responseJudge, moderator }: AppOptions) {
  const app = express();
  app.use(express.json({ limit: "256kb" }));

  // The Safari extension calls from its own origin. Auth is bearer-token only
  // (no cookies), so allowing any origin is safe here.
  app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    if (req.method === "OPTIONS") return res.sendStatus(204);
    next();
  });

  const categoryFor = (site: string) =>
    catalog.categories.find((c) => c.domains.some((d) => site === d || site.endsWith(`.${d}`)))?.id;

  /** The kid's Guided rules plus any instructions the parent set for this one app. */
  const guidedRulesFor = (policy: KidPolicy, site: string) => {
    const app = appForSite(catalog, site);
    const extra = (app && policy.appInstructions?.[app.id]) || [];
    if (!extra.length) return policy.guidedRules;
    return { ...policy.guidedRules, globalInstructions: [...policy.guidedRules.globalInstructions, ...extra] };
  };

  const requireParent = (req: Request, res: Response, next: NextFunction) => {
    const family = store.family(req.params.familyId);
    if (!family || bearer(req) !== family.parentToken) {
      return res.status(401).json({ error: "Not signed in to this family." });
    }
    res.locals.family = family;
    next();
  };

  const requireKid = (req: Request, res: Response, next: NextFunction) => {
    const family = res.locals.family as Family;
    const kid = family.kids.find((k) => k.id === req.params.kidId);
    if (!kid) return res.status(404).json({ error: "Kid not found." });
    res.locals.kid = kid;
    next();
  };

  const requireDevice = (req: Request, res: Response, next: NextFunction) => {
    const token = bearer(req);
    const kid = token ? store.kidByDeviceToken(token) : undefined;
    if (!kid) return res.status(401).json({ error: "This device isn't paired. Enter the pairing code again." });
    res.locals.kid = kid;
    next();
  };

  app.get("/health", (_req, res) => {
    res.json({ ok: true, catalogVersion: catalog.version, aiJudge: Boolean(judge), moderation: Boolean(moderator) });
  });

  app.get("/catalog", (_req, res) => {
    res.json(catalog);
  });

  // ---- Parent app ----

  app.post("/auth/sign-in", (req, res) => {
    const parsed = signInSchema.safeParse(req.body);
    const family = parsed.success ? store.familyForAccount(parsed.data.email) : undefined;
    if (!parsed.success || !family || !passwordMatches(parsed.data.password)) {
      return res.status(401).json({ error: "Email or password is incorrect." });
    }
    res.json({ familyId: family.id, parentToken: family.parentToken, parentName: family.parentName ?? null });
  });

  app.post("/families", (req, res) => {
    const parsed = familySchema.safeParse(req.body ?? {});
    const family = store.createFamily(parsed.success ? parsed.data.parentName : undefined);
    res.status(201).json({ familyId: family.id, parentToken: family.parentToken });
  });

  app.get("/families/:familyId", requireParent, (_req, res) => {
    const family = res.locals.family as Family;
    res.json({ familyId: family.id, parentName: family.parentName ?? null, kids: family.kids.map(publicKid) });
  });

  app.put("/families/:familyId", requireParent, (req, res) => {
    const parsed = familySchema.safeParse(req.body);
    if (!parsed.success || !parsed.data.parentName) return res.status(400).json({ error: "Enter your name." });
    const family = res.locals.family as Family;
    store.setParentName(family, parsed.data.parentName);
    res.json({ familyId: family.id, parentName: family.parentName, kids: family.kids.map(publicKid) });
  });

  app.post("/families/:familyId/kids", requireParent, (req, res) => {
    const parsed = createKidSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Enter a name for your kid." });
    const kid = store.addKid(res.locals.family, parsed.data.name, defaultPolicy(catalog));
    res.status(201).json(publicKid(kid));
  });

  app.put("/families/:familyId/kids/:kidId", requireParent, requireKid, (req, res) => {
    const parsed = createKidSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Enter a name for your kid." });
    store.renameKid(res.locals.kid, parsed.data.name);
    res.json(publicKid(res.locals.kid));
  });

  app.delete("/families/:familyId/kids/:kidId", requireParent, requireKid, (req, res) => {
    store.removeKid(res.locals.family, req.params.kidId);
    res.sendStatus(204);
  });

  app.put("/families/:familyId/kids/:kidId/policy", requireParent, requireKid, (req, res) => {
    const parsed = policyUpdateSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: parsed.error.issues[0]?.message ?? "Invalid rules." });
    }
    const { changeId, ...policy } = parsed.data;
    if (!store.updatePolicy(res.locals.kid, policy, changeId)) {
      return res.status(409).json({ error: "This change was already saved with different rules. Start a new change." });
    }
    res.json(publicKid(res.locals.kid));
  });

  app.get("/families/:familyId/kids/:kidId/activity", requireParent, requireKid, (_req, res) => {
    const kid = res.locals.kid as Kid;
    const events = store.eventsFor(kid.id);
    const counts: Record<string, number> = {};
    for (const e of events) counts[e.type] = (counts[e.type] ?? 0) + 1;
    res.json({
      lastHeartbeat: kid.lastHeartbeat ?? null,
      paired: Boolean(kid.deviceToken),
      policyRevision: kid.policyRevision,
      appliedPolicyRevision: kid.appliedPolicyRevision,
      policyAppliedAt: kid.policyAppliedAt,
      counts,
      events,
      requests: store.requestsFor(kid.id),
    });
  });

  app.post("/families/:familyId/kids/:kidId/requests/:requestId", requireParent, requireKid, (req, res) => {
    const kid = res.locals.kid as Kid;
    const request = store.request(req.params.requestId);
    if (!request || request.kidId !== kid.id) return res.status(404).json({ error: "Request not found." });
    if (request.status !== "pending") return res.status(409).json({ error: "This request was already answered." });
    const parsed = requestDecisionSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Invalid decision." });

    if (!parsed.data.approve) {
      store.decideRequest(request, false);
      return res.json({ request, kid: publicKid(kid) });
    }

    const minutes = parsed.data.minutes ?? request.minutes;
    const until = new Date(Date.now() + minutes * 60_000).toISOString();
    const policy = currentPolicy(kid);
    policy.temporaryAllows = [
      ...policy.temporaryAllows.filter((t) => t.domain !== request.domain),
      { domain: request.domain, until, requestId: request.id },
    ].slice(-20);
    store.updatePolicy(kid, policy);
    store.decideRequest(request, true, until);
    res.json({ request, kid: publicKid(kid) });
  });

  app.post("/families/:familyId/suggestions", requireParent, (req, res) => {
    const parsed = suggestionSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.issues[0]?.message ?? "Invalid site." });
    store.addSuggestion({ familyId: (res.locals.family as Family).id, ...parsed.data, at: new Date().toISOString() });
    res.status(201).json({ ok: true });
  });

  // ---- Kid's Safari extension ----

  app.post("/pair", (req, res) => {
    const parsed = pairSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.issues[0]?.message ?? "Invalid code." });
    const kid = store.kidByPairingCode(parsed.data.code);
    if (!kid) return res.status(404).json({ error: "That code doesn't match any kid. Check it in the Guidance app." });
    const deviceToken = store.pairDevice(kid);
    res.json({ kidId: kid.id, kidName: kid.name, guardianName: store.familyOfKid(kid.id)?.parentName ?? null, deviceToken });
  });

  app.get("/device/policy", requireDevice, (_req, res) => {
    const kid = res.locals.kid as Kid;
    store.recordHeartbeat(kid);
    res.json({
      kidName: kid.name,
      guardianName: store.familyOfKid(kid.id)?.parentName ?? null,
      policy: currentPolicy(kid),
      policyRevision: kid.policyRevision,
      catalogVersion: catalog.version,
    });
  });

  app.post("/device/policy-applied", requireDevice, (req, res) => {
    const parsed = policyAppliedSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Enter a valid policy revision." });
    const kid = res.locals.kid as Kid;
    if (!store.recordPolicyApplied(kid, parsed.data.policyRevision)) {
      return res.status(409).json({ error: "The rules changed. Download and apply the latest rules before confirming.", policyRevision: kid.policyRevision });
    }
    res.json({ policyRevision: kid.policyRevision, appliedPolicyRevision: kid.appliedPolicyRevision, policyAppliedAt: kid.policyAppliedAt });
  });

  /**
   * Prompt check on chatbot sites. "guided" applies homework rules and safety alerts;
   * "safety" (chatbots the parent allows outright) only raises safety alerts.
   * Safety alerts never change what the kid sees.
   */
  app.post("/device/check", requireDevice, async (req, res) => {
    const parsed = checkRequestSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Invalid request." });
    const kid = res.locals.kid as Kid;
    const policy = currentPolicy(kid);
    const { site, prompt, mode } = parsed.data;
    const now = new Date().toISOString();
    const categoryId = categoryFor(site);

    const [decision, topics] = await Promise.all([
      mode === "guided"
        ? checkPrompt(prompt, guidedRulesFor(policy, site), judge)
        : Promise.resolve({ action: "allow" as const, reason: "", instructions: "", source: "rules" as const }),
      safetyTopicsFor(prompt, moderator),
    ]);

    const events: Omit<ActivityEvent, "id">[] = topics.map((topic) => ({
      kidId: kid.id,
      type: "safety_alert",
      domain: site,
      categoryId,
      topic,
      severity: topicInfo(topic).severity,
      excerpt: prompt.slice(0, EXCERPT_LENGTH),
      at: now,
    }));
    if (mode === "guided") {
      events.push({
        kidId: kid.id,
        type: decision.action === "block" ? "guided_block" : "guided_allow",
        domain: site,
        categoryId,
        reason: decision.action === "block" ? decision.reason : undefined,
        at: now,
      });
    }
    if (events.length) store.addEvents(events);
    res.json(decision);
  });

  app.post("/device/check-response", requireDevice, async (req, res) => {
    const parsed = checkResponseSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Invalid request." });
    const kid = res.locals.kid as Kid;
    const { site, prompt, response } = parsed.data;
    const decision = await checkResponse(prompt, response, guidedRulesFor(currentPolicy(kid), site), responseJudge);
    if (decision.action === "hide") {
      store.addEvents([
        { kidId: kid.id, type: "answer_hidden", domain: site, categoryId: categoryFor(site), reason: decision.reason, at: new Date().toISOString() },
      ]);
    }
    res.json(decision);
  });

  app.post("/device/requests", requireDevice, (req, res) => {
    const parsed = accessRequestSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.issues[0]?.message ?? "Invalid request." });
    const kid = res.locals.kid as Kid;
    const request = store.addRequest({ kidId: kid.id, ...parsed.data });
    if (!request) return res.status(429).json({ error: "You already have lots of requests waiting. Ask your parent to check the Guidance app." });
    res.status(201).json(request);
  });

  app.get("/device/requests/:requestId", requireDevice, (req, res) => {
    const request = store.request(req.params.requestId);
    if (!request || request.kidId !== (res.locals.kid as Kid).id) return res.status(404).json({ error: "Request not found." });
    res.json(request);
  });

  app.post("/device/events", requireDevice, (req, res) => {
    const parsed = eventsRequestSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Invalid events." });
    const kid = res.locals.kid as Kid;
    const now = new Date().toISOString();
    store.recordHeartbeat(kid, now);
    const activity = parsed.data.events
      .filter((e) => e.type !== "heartbeat")
      .map((e) => ({
        kidId: kid.id,
        type: e.type as "blocked" | "guided_block" | "guided_allow" | "answer_hidden",
        domain: e.domain,
        categoryId: e.categoryId,
        reason: e.reason,
        at: e.at ?? now,
      }));
    if (activity.length) store.addEvents(activity);
    res.status(202).json({ ok: true });
  });

  return app;
}
