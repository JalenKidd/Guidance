import assert from "node:assert/strict";
import test from "node:test";
import { catalogSchema, defaultPolicy, loadCatalog } from "./catalog.js";
import { kidPolicySchema } from "./validation.js";

test("the shipped catalog is valid and has no duplicate domains", () => {
  const catalog = loadCatalog();
  assert.ok(catalog.categories.length >= 8);
});

test("catalog validation rejects a domain listed in two categories", () => {
  const catalog = loadCatalog();
  const broken = structuredClone(catalog);
  broken.categories[1].domains.push(broken.categories[0].domains[0]);
  assert.equal(catalogSchema.safeParse(broken).success, false);
});

test("the default policy validates and covers every category", () => {
  const catalog = loadCatalog();
  const policy = kidPolicySchema.parse(defaultPolicy(catalog));
  assert.deepEqual(Object.keys(policy.categories).sort(), catalog.categories.map((c) => c.id).sort());
});

test("policy fills defaults for missing fields", () => {
  const policy = kidPolicySchema.parse({});
  assert.equal(policy.masterAIOff, false);
  assert.equal(policy.guidedRules.blockHomeworkOffloading, true);
});

test("site overrides are normalized and must be bare domains", () => {
  assert.deepEqual(kidPolicySchema.parse({ siteOverrides: { "Claude.AI": "allow" } }).siteOverrides, { "claude.ai": "allow" });
  assert.equal(kidPolicySchema.safeParse({ siteOverrides: { "https://claude.ai/new": "allow" } }).success, false);
});

test("schedule times must be HH:MM", () => {
  const schedule = { id: "a", name: "Bedtime", days: [1], start: "9pm", end: "07:00" };
  assert.equal(kidPolicySchema.safeParse({ schedules: [schedule] }).success, false);
  assert.equal(kidPolicySchema.safeParse({ schedules: [{ ...schedule, start: "21:00" }] }).success, true);
});
