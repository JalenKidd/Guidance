import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { defaultPolicy, loadCatalog } from "./catalog.js";
import type { KidPolicy } from "./validation.js";

// The resolver lives with the Safari extension so both share one implementation.
const require = createRequire(import.meta.url);
const resolver = require("../../../Extensions/GuidanceSafari/Resources/shared/resolver.js");

const catalog = loadCatalog();

/** Local-time date: 2026-10-21 is a Wednesday (getDay() === 3). */
function at(hhmm: string, day = 21) {
  const [h, m] = hhmm.split(":").map(Number);
  return new Date(2026, 9, day, h, m);
}

function policy(overrides: Partial<KidPolicy> = {}): KidPolicy {
  return { ...defaultPolicy(catalog), ...overrides };
}

test("category defaults apply to catalog sites and subdomains", () => {
  const p = policy();
  assert.equal(resolver.resolveSite("quillbot.com", p, catalog, at("12:00")).state, "block");
  assert.equal(resolver.resolveSite("www.quillbot.com", p, catalog, at("12:00")).state, "block");
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("12:00")).state, "guided");
  assert.equal(resolver.resolveSite("khanmigo.ai", p, catalog, at("12:00")).state, "allow");
});

test("sites outside the catalog are untouched", () => {
  const r = resolver.resolveSite("wikipedia.org", policy(), catalog, at("12:00"));
  assert.deepEqual(r, { state: "allow", categoryId: null, source: "none" });
});

test("lookalike domains do not match", () => {
  assert.equal(resolver.resolveSite("notquillbot.com", policy(), catalog, at("12:00")).source, "none");
});

test("site override beats the category", () => {
  const p = policy({ categories: { ...policy().categories, chatbots: "block" }, siteOverrides: { "claude.ai": "allow" } });
  assert.equal(resolver.resolveSite("claude.ai", p, catalog, at("12:00")).state, "allow");
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("12:00")).state, "block");
});

test("one chatbot can be Guided while its category is blocked", () => {
  const p = policy({ categories: { ...policy().categories, chatbots: "block" }, siteOverrides: { "claude.ai": "guided" } });
  const r = resolver.resolveSite("claude.ai", p, catalog, at("12:00"));
  assert.equal(r.state, "guided");
  assert.equal(r.source, "override");
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("12:00")).state, "block");
});

test("parents can block a site that isn't in the catalog", () => {
  const p = policy({ siteOverrides: { "newaiessay.io": "block" } });
  const r = resolver.resolveSite("app.newaiessay.io", p, catalog, at("12:00"));
  assert.equal(r.state, "block");
  assert.equal(r.source, "override");
});

test("master AI off blocks every AI site, even allowed and overridden ones", () => {
  const p = policy({ masterAIOff: true, siteOverrides: { "claude.ai": "allow" } });
  for (const host of ["khanmigo.ai", "claude.ai", "midjourney.com"]) {
    const r = resolver.resolveSite(host, p, catalog, at("12:00"));
    assert.equal(r.state, "block", host);
    assert.equal(r.source, "master");
  }
  assert.equal(resolver.resolveSite("wikipedia.org", p, catalog, at("12:00")).state, "allow");
});

const schoolNights = {
  id: "s1",
  name: "School nights",
  enabled: true,
  days: [0, 1, 2, 3, 4],
  start: "16:00",
  end: "21:00",
  masterAIOff: false,
  categories: { chatbots: "block" as const, image: "block" as const },
};

test("a schedule changes categories only inside its window", () => {
  const p = policy({ schedules: [schoolNights] });
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("15:59")).state, "guided");
  const inside = resolver.resolveSite("chatgpt.com", p, catalog, at("16:00"));
  assert.equal(inside.state, "block");
  assert.equal(inside.source, "schedule:School nights");
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("21:00")).state, "guided");
  // Friday (day 23) isn't in the schedule.
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("17:00", 23)).state, "guided");
});

test("overnight schedules carry past midnight into the next day", () => {
  const bedtime = { ...schoolNights, id: "s2", name: "Bedtime", days: [3], start: "21:30", end: "07:00", masterAIOff: true, categories: {} };
  const p = policy({ schedules: [bedtime] });
  assert.equal(resolver.resolveSite("khanmigo.ai", p, catalog, at("21:29")).state, "allow");
  assert.equal(resolver.resolveSite("khanmigo.ai", p, catalog, at("23:00")).state, "block");
  // Thursday 6:59am is still Wednesday night's window.
  assert.equal(resolver.resolveSite("khanmigo.ai", p, catalog, at("06:59", 22)).state, "block");
  assert.equal(resolver.resolveSite("khanmigo.ai", p, catalog, at("07:00", 22)).state, "allow");
  // Wednesday early morning belongs to Tuesday night, which isn't scheduled.
  assert.equal(resolver.resolveSite("khanmigo.ai", p, catalog, at("03:00")).state, "allow");
});

test("schedules can loosen a category, and the strictest overlapping schedule wins", () => {
  const studyHall = { ...schoolNights, id: "s3", name: "Study hall", start: "17:00", end: "18:00", categories: { math: "allow" as const } };
  const p = policy({ schedules: [studyHall] });
  assert.equal(resolver.resolveSite("mathway.com", p, catalog, at("17:30")).state, "allow");
  const both = policy({ schedules: [studyHall, { ...schoolNights, categories: { math: "block" as const } }] });
  assert.equal(resolver.resolveSite("mathway.com", both, catalog, at("17:30")).state, "block");
});

test("disabled schedules are ignored", () => {
  const p = policy({ schedules: [{ ...schoolNights, enabled: false }] });
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("17:00")).state, "guided");
});

test("resolveAll covers every catalog domain plus overrides", () => {
  const p = policy({ siteOverrides: { "newaiessay.io": "block" } });
  const all = resolver.resolveAll(p, catalog, at("12:00"));
  const count = catalog.categories.reduce((n, c) => n + c.domains.length, 0) + 1;
  assert.equal(all.length, count);
  assert.equal(all.find((r: { domain: string }) => r.domain === "newaiessay.io").state, "block");
});

test("an approved request beats every other rule until it expires", () => {
  const p = policy({
    masterAIOff: true,
    siteOverrides: { "quillbot.com": "block" },
    temporaryAllows: [{ domain: "quillbot.com", until: at("12:30").toISOString() }],
  });
  const during = resolver.resolveSite("www.quillbot.com", p, catalog, at("12:00"));
  assert.equal(during.state, "allow");
  assert.equal(during.source, "approved");
  assert.equal(resolver.resolveSite("quillbot.com", p, catalog, at("12:30")).state, "block");
  // Only the approved site is opened up.
  assert.equal(resolver.resolveSite("chatgpt.com", p, catalog, at("12:00")).state, "block");
});
