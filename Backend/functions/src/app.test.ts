import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { seedDemoAccounts } from "./accounts.js";
import { createApp } from "./app.js";
import { defaultPolicy, loadCatalog } from "./catalog.js";
import { Store } from "./store.js";

let base = "";
let close: () => void;

before(async () => {
  const app = createApp({ store: new Store(), catalog: loadCatalog() });
  const server = app.listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  close = () => server.close();
});

after(() => close());

async function call(method: string, path: string, body?: unknown, token?: string) {
  const res = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

test("parent → kid → paired extension → check → activity", async () => {
  const family = await call("POST", "/families");
  assert.equal(family.status, 201);
  const { familyId, parentToken } = family.body;

  const kid = await call("POST", `/families/${familyId}/kids`, { name: "Maya" }, parentToken);
  assert.equal(kid.status, 201);
  assert.match(kid.body.pairingCode, /^[A-Z0-9]{6}$/);
  assert.equal(kid.body.paired, false);
  assert.equal(kid.body.policy.categories.essay, "block");

  const policy = { ...kid.body.policy, masterAIOff: true };
  const put = await call("PUT", `/families/${familyId}/kids/${kid.body.id}/policy`, policy, parentToken);
  assert.equal(put.status, 200);
  assert.equal(put.body.policy.masterAIOff, true);

  const pair = await call("POST", "/pair", { code: kid.body.pairingCode.toLowerCase() });
  assert.equal(pair.status, 200);
  assert.equal(pair.body.kidName, "Maya");
  const device = pair.body.deviceToken;

  const devicePolicy = await call("GET", "/device/policy", undefined, device);
  assert.equal(devicePolicy.body.policy.masterAIOff, true);

  const check = await call("POST", "/device/check", { site: "chatgpt.com", prompt: "write my essay on the Civil War" }, device);
  assert.equal(check.body.action, "block");

  const events = await call("POST", "/device/events", { events: [{ type: "blocked", domain: "quillbot.com", categoryId: "essay" }] }, device);
  assert.equal(events.status, 202);

  const activity = await call("GET", `/families/${familyId}/kids/${kid.body.id}/activity`, undefined, parentToken);
  assert.equal(activity.body.paired, true);
  assert.equal(activity.body.counts.blocked, 1);
  assert.equal(activity.body.counts.guided_block, 1);
  assert.equal(activity.body.events[0].domain, "quillbot.com");
  assert.ok(activity.body.lastHeartbeat);
});

test("the parent's name reaches the kid's extension", async () => {
  const { body: family } = await call("POST", "/families", { parentName: "Maria" });
  const kid = (await call("POST", `/families/${family.familyId}/kids`, { name: "Leo" }, family.parentToken)).body;
  const pair = await call("POST", "/pair", { code: kid.pairingCode });
  assert.equal(pair.body.guardianName, "Maria");

  const renamed = await call("PUT", `/families/${family.familyId}`, { parentName: "Mom" }, family.parentToken);
  assert.equal(renamed.body.parentName, "Mom");
  const policy = await call("GET", "/device/policy", undefined, pair.body.deviceToken);
  assert.equal(policy.body.guardianName, "Mom");
});

test("parent routes reject the wrong token", async () => {
  const { body } = await call("POST", "/families");
  const res = await call("GET", `/families/${body.familyId}`, undefined, "nope");
  assert.equal(res.status, 401);
});

test("device routes reject unpaired devices", async () => {
  const res = await call("GET", "/device/policy", undefined, "nope");
  assert.equal(res.status, 401);
});

test("invalid rules are rejected with a readable message", async () => {
  const { body } = await call("POST", "/families");
  const kid = await call("POST", `/families/${body.familyId}/kids`, { name: "Leo" }, body.parentToken);
  const res = await call(
    "PUT",
    `/families/${body.familyId}/kids/${kid.body.id}/policy`,
    { siteOverrides: { "not a domain": "block" } },
    body.parentToken
  );
  assert.equal(res.status, 400);
  assert.match(res.body.error, /domain/);
});

test("the catalog is public", async () => {
  const res = await call("GET", "/catalog");
  assert.equal(res.status, 200);
  assert.ok(res.body.version >= 1);
});

async function pairedKid(name = "Sam") {
  const family = (await call("POST", "/families")).body;
  const kid = (await call("POST", `/families/${family.familyId}/kids`, { name }, family.parentToken)).body;
  const device = (await call("POST", "/pair", { code: kid.pairingCode })).body.deviceToken;
  const parentPath = `/families/${family.familyId}/kids/${kid.id}`;
  return { parent: family.parentToken, device, parentPath };
}

test("safety alerts reach the parent without changing what the kid sees", async () => {
  const { parent, device, parentPath } = await pairedKid();
  const check = await call("POST", "/device/check", { site: "chatgpt.com", prompt: "how do i hide a vape from my parents" }, device);
  assert.equal(check.body.action, "allow");

  const urgent = await call("POST", "/device/check", { site: "claude.ai", prompt: "i want to kill myself", mode: "safety" }, device);
  assert.equal(urgent.body.action, "allow");
  assert.equal(urgent.body.instructions, "", "safety-only checks don't add homework instructions");

  const activity = await call("GET", `${parentPath}/activity`, undefined, parent);
  const alerts = activity.body.events.filter((e: { type: string }) => e.type === "safety_alert");
  assert.equal(alerts.length, 2);
  assert.equal(alerts[0].topic, "self_harm");
  assert.equal(alerts[0].severity, "urgent");
  assert.equal(alerts[0].excerpt, "i want to kill myself");
  assert.equal(alerts[1].topic, "nicotine");
  // Safety-only checks aren't counted as guided prompts.
  assert.equal(activity.body.counts.guided_allow, 1);
});

test("finished answers are hidden and logged", async () => {
  const { parent, device, parentPath } = await pairedKid();
  const response = "1) x = 5. Final answer: 5\n2) x = 7. Final answer: 7";
  const res = await call("POST", "/device/check-response", { site: "chatgpt.com", prompt: "do my math homework", response }, device);
  assert.equal(res.body.action, "hide");
  const activity = await call("GET", `${parentPath}/activity`, undefined, parent);
  assert.equal(activity.body.counts.answer_hidden, 1);
});

test("ask a parent: request → approve → temporary allow → expires from policy", async () => {
  const { parent, device, parentPath } = await pairedKid();
  const created = await call(
    "POST",
    "/device/requests",
    { domain: "quillbot.com", categoryId: "essay", kind: "site", reason: "Teacher said we can use it to check citations", minutes: 30 },
    device
  );
  assert.equal(created.status, 201);
  assert.equal(created.body.status, "pending");

  // Asking again updates the same request instead of adding another.
  const again = await call("POST", "/device/requests", { domain: "quillbot.com", kind: "site", reason: "please, it's for English", minutes: 15 }, device);
  assert.equal(again.body.id, created.body.id);

  const activity = await call("GET", `${parentPath}/activity`, undefined, parent);
  assert.equal(activity.body.requests.length, 1);
  assert.equal(activity.body.requests[0].reason, "please, it's for English");

  const decided = await call("POST", `${parentPath}/requests/${created.body.id}`, { approve: true, minutes: 20 }, parent);
  assert.equal(decided.status, 200);
  assert.equal(decided.body.request.status, "approved");
  const allow = decided.body.kid.policy.temporaryAllows[0];
  assert.equal(allow.domain, "quillbot.com");
  const minutesLeft = (Date.parse(allow.until) - Date.now()) / 60_000;
  assert.ok(minutesLeft > 19 && minutesLeft <= 20);

  const status = await call("GET", `/device/requests/${created.body.id}`, undefined, device);
  assert.equal(status.body.status, "approved");
  const policy = await call("GET", "/device/policy", undefined, device);
  assert.equal(policy.body.policy.temporaryAllows.length, 1);

  const twice = await call("POST", `${parentPath}/requests/${created.body.id}`, { approve: false }, parent);
  assert.equal(twice.status, 409);
});

test("requests need a reason and a standard length", async () => {
  const { device } = await pairedKid();
  const noReason = await call("POST", "/device/requests", { domain: "quillbot.com", kind: "site", reason: "", minutes: 30 }, device);
  assert.equal(noReason.status, 400);
  const tooLong = await call("POST", "/device/requests", { domain: "quillbot.com", kind: "site", reason: "for school", minutes: 600 }, device);
  assert.equal(tooLong.status, 400);
});

test("kids can't see another kid's requests", async () => {
  const a = await pairedKid("A");
  const b = await pairedKid("B");
  const created = await call("POST", "/device/requests", { domain: "quillbot.com", kind: "site", reason: "for school", minutes: 15 }, a.device);
  const peek = await call("GET", `/device/requests/${created.body.id}`, undefined, b.device);
  assert.equal(peek.status, 404);
});

test("demo accounts sign into their own families; Marves keeps the existing family", async () => {
  const store = new Store();
  const old = store.createFamily();
  const oldKid = store.addKid(old, "Jalen the son", defaultPolicy(loadCatalog()));
  store.pairDevice(oldKid);
  store.createFamily(); // an unpaired leftover family

  seedDemoAccounts(store);
  seedDemoAccounts(store); // second run changes nothing
  assert.equal(store.allFamilies().length, 2 + 3);
  assert.equal(store.familyForAccount("MarvesPaztanes@gmail.com")?.id, old.id);
  assert.equal(old.parentName, "Marves");

  const app = createApp({ store, catalog: loadCatalog() });
  const server = app.listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const signIn = (email: string, password: string) =>
    fetch(`${url}/auth/sign-in`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, password }) });

  try {
    const marves = await signIn("MarvesPaztanes@gmail.com", "guidance123");
    assert.equal(marves.status, 200);
    assert.equal((await marves.json()).familyId, old.id);

    const ids = new Set<string>();
    for (const email of ["jalenpaztanes@gmail.com", "MIGUELPAZTANES@gmail.com", " alanipaztanes@gmail.com "]) {
      const res = await signIn(email, "guidance123");
      assert.equal(res.status, 200, email);
      ids.add((await res.json()).familyId);
    }
    assert.equal(ids.size, 3);
    assert.ok(!ids.has(old.id));

    assert.equal((await signIn("marvespaztanes@gmail.com", "wrong")).status, 401);
    assert.equal((await signIn("someone@gmail.com", "guidance123")).status, 401);
  } finally {
    server.close();
  }
});

test("kids can be renamed", async () => {
  const { body: family } = await call("POST", "/families");
  const kid = (await call("POST", `/families/${family.familyId}/kids`, { name: "Leo" }, family.parentToken)).body;
  const renamed = await call("PUT", `/families/${family.familyId}/kids/${kid.id}`, { name: "Leonardo" }, family.parentToken);
  assert.equal(renamed.body.name, "Leonardo");
  assert.equal(renamed.body.pairingCode, kid.pairingCode);
});

test("saved and downloaded rules stay pending until the paired device confirms the current revision", async () => {
  const family = (await call("POST", "/families")).body;
  const kid = (await call("POST", `/families/${family.familyId}/kids`, { name: "Maya" }, family.parentToken)).body;
  const path = `/families/${family.familyId}/kids/${kid.id}`;
  assert.equal(kid.policyRevision, 1);
  assert.equal(kid.appliedPolicyRevision, null);
  assert.equal(kid.policyAppliedAt, null);

  const device = (await call("POST", "/pair", { code: kid.pairingCode })).body.deviceToken;
  const saved = await call("PUT", `${path}/policy`, { ...kid.policy, masterAIOff: true, changeId: "edit-1" }, family.parentToken);
  assert.equal(saved.body.policyRevision, 2);
  assert.equal(saved.body.appliedPolicyRevision, null);
  const download = await call("GET", "/device/policy", undefined, device);
  assert.equal(download.body.policyRevision, 2);
  assert.equal(download.body.policy.masterAIOff, true);
  const pending = (await call("GET", `${path}/activity`, undefined, family.parentToken)).body;
  assert.equal(pending.policyRevision, 2);
  assert.equal(pending.appliedPolicyRevision, null, "downloading must never imply installation");
  assert.equal(pending.policyAppliedAt, null);

  const applied = await call("POST", "/device/policy-applied", { policyRevision: 2, policyAppliedAt: "2000-01-01T00:00:00Z" }, device);
  assert.equal(applied.status, 200);
  assert.equal(applied.body.appliedPolicyRevision, 2);
  assert.ok(Date.parse(applied.body.policyAppliedAt) > Date.now() - 60_000, "the server owns the acknowledgement time");
  const duplicate = await call("POST", "/device/policy-applied", { policyRevision: 2 }, device);
  assert.equal(duplicate.body.policyAppliedAt, applied.body.policyAppliedAt, "retries preserve the original confirmation time");

  const familyAfter = (await call("GET", `/families/${family.familyId}`, undefined, family.parentToken)).body;
  assert.equal(familyAfter.kids[0].appliedPolicyRevision, 2);
  assert.equal(familyAfter.kids[0].policyAppliedAt, applied.body.policyAppliedAt);
  const changed = await call("PUT", `${path}/policy`, { ...kid.policy, changeId: "edit-2" }, family.parentToken);
  assert.equal(changed.body.policyRevision, 3);
  assert.equal(changed.body.appliedPolicyRevision, 2, "the old confirmation remains evidence of an older revision only");
  assert.equal(changed.body.policyAppliedAt, applied.body.policyAppliedAt);
  const activity = (await call("GET", `${path}/activity`, undefined, family.parentToken)).body;
  assert.equal(activity.policyRevision, 3);
  assert.equal(activity.appliedPolicyRevision, 2);
});

test("policy confirmations reject missing, invalid, stale, future, and unpaired revisions", async () => {
  const { parent, device, parentPath } = await pairedKid();
  for (const body of [{}, { policyRevision: 0 }, { policyRevision: -1 }, { policyRevision: 1.5 }, { policyRevision: "1" }, { policyRevision: Number.MAX_SAFE_INTEGER + 1 }]) {
    assert.equal((await call("POST", "/device/policy-applied", body, device)).status, 400);
  }
  assert.equal((await call("POST", "/device/policy-applied", { policyRevision: 1 })).status, 401);
  assert.equal((await call("POST", "/device/policy-applied", { policyRevision: 1 }, "not-a-device")).status, 401);
  assert.equal((await call("POST", "/device/policy-applied", { policyRevision: 1 }, parent)).status, 401);
  assert.equal((await call("POST", "/device/policy-applied", { policyRevision: 2 }, device)).status, 409);
  await call("PUT", `${parentPath}/policy`, { masterAIOff: true }, parent);
  const stale = await call("POST", "/device/policy-applied", { policyRevision: 1 }, device);
  assert.equal(stale.status, 409);
  assert.equal(stale.body.policyRevision, 2);
  const activity = (await call("GET", `${parentPath}/activity`, undefined, parent)).body;
  assert.equal(activity.appliedPolicyRevision, null);
  assert.equal(activity.policyAppliedAt, null);
});

test("policy saves are semantic and an edit id can be retried safely", async () => {
  const { parent, device, parentPath } = await pairedKid();
  const initial = (await call("GET", "/device/policy", undefined, device)).body;
  const policy = { ...initial.policy, masterAIOff: true };
  const saved = await call("PUT", `${parentPath}/policy`, { ...policy, changeId: "lost-response" }, parent);
  assert.equal(saved.body.policyRevision, 2);
  assert.equal("changeId" in saved.body.policy, false);
  const retried = await call("PUT", `${parentPath}/policy`, { changeId: "lost-response", ...policy }, parent);
  assert.equal(retried.body.policyRevision, 2);
  const unchanged = await call("PUT", `${parentPath}/policy`, { ...policy, categories: Object.fromEntries(Object.entries(policy.categories).reverse()), changeId: "same-settings-new-edit" }, parent);
  assert.equal(unchanged.body.policyRevision, 2, "object-key order is not a rule change");
  const conflict = await call("PUT", `${parentPath}/policy`, { ...initial.policy, changeId: "same-settings-new-edit" }, parent);
  assert.equal(conflict.status, 409);
  assert.equal((await call("GET", "/device/policy", undefined, device)).body.policy.masterAIOff, true);
  assert.equal((await call("PUT", `${parentPath}/policy`, { ...policy, changeId: "" }, parent)).status, 400);

  // The same policy with omitted optional defaults is also a no-op.
  await call("PUT", `${parentPath}/policy`, {}, parent);
  const defaults = (await call("GET", "/device/policy", undefined, device)).body;
  const equivalent = await call("PUT", `${parentPath}/policy`, defaults.policy, parent);
  assert.equal(equivalent.body.policyRevision, defaults.policyRevision);
  const lateRetry = await call("PUT", `${parentPath}/policy`, { ...policy, changeId: "lost-response" }, parent);
  assert.equal(lateRetry.status, 200);
  assert.equal(lateRetry.body.policyRevision, defaults.policyRevision, "retrying an older edit never overwrites a newer save");
  assert.equal(lateRetry.body.policy.masterAIOff, false);
});

test("temporary approvals advance the revision and a lost save response cannot erase them", async () => {
  const { parent, device, parentPath } = await pairedKid();
  const initial = (await call("GET", "/device/policy", undefined, device)).body;
  const edit = { ...initial.policy, masterAIOff: true, changeId: "before-approval" };
  await call("PUT", `${parentPath}/policy`, edit, parent);
  await call("POST", "/device/policy-applied", { policyRevision: 2 }, device);
  const request = (await call("POST", "/device/requests", { domain: "quillbot.com", kind: "site", reason: "For my assignment", minutes: 15 }, device)).body;
  const approved = await call("POST", `${parentPath}/requests/${request.id}`, { approve: true }, parent);
  assert.equal(approved.body.kid.policyRevision, 3);
  assert.equal(approved.body.kid.appliedPolicyRevision, 2);
  const retry = await call("PUT", `${parentPath}/policy`, edit, parent);
  assert.equal(retry.status, 200);
  assert.equal(retry.body.policyRevision, 3);
  assert.equal(retry.body.policy.temporaryAllows.length, 1);
});

test("re-pairing clears applied evidence and invalidates the previous device", async () => {
  const family = (await call("POST", "/families")).body;
  const kid = (await call("POST", `/families/${family.familyId}/kids`, { name: "Leo" }, family.parentToken)).body;
  const first = (await call("POST", "/pair", { code: kid.pairingCode })).body.deviceToken;
  await call("POST", "/device/policy-applied", { policyRevision: 1 }, first);
  const second = (await call("POST", "/pair", { code: kid.pairingCode })).body.deviceToken;
  const activity = (await call("GET", `/families/${family.familyId}/kids/${kid.id}/activity`, undefined, family.parentToken)).body;
  assert.equal(activity.policyRevision, 1);
  assert.equal(activity.appliedPolicyRevision, null);
  assert.equal(activity.policyAppliedAt, null);
  assert.equal((await call("POST", "/device/policy-applied", { policyRevision: 1 }, first)).status, 401);
  assert.equal((await call("POST", "/device/policy-applied", { policyRevision: 1 }, second)).status, 200);
});

test("older stored kids migrate to an unconfirmed first revision and delivery survives a restart", () => {
  const directory = mkdtempSync(join(tmpdir(), "guidance-delivery-"));
  const path = join(directory, "store.json");
  try {
    writeFileSync(path, JSON.stringify({ families: { family: {
      id: "family", parentToken: "parent", createdAt: "2026-01-01T00:00:00Z", kids: [{
        id: "kid", name: "Leo", pairingCode: "ABCDEF", deviceToken: "device",
        policy: {}, lastHeartbeat: "2026-01-01T00:00:00Z", createdAt: "2026-01-01T00:00:00Z",
      }],
    } } }));
    const store = new Store(path);
    const kid = store.family("family")!.kids[0];
    assert.equal(kid.policyRevision, 1);
    assert.equal(kid.appliedPolicyRevision, null);
    assert.equal(kid.policyAppliedAt, null);
    assert.equal(JSON.parse(readFileSync(path, "utf8")).families.family.kids[0].policyRevision, 1);
    store.recordPolicyApplied(kid, 1);
    const defaults = { masterAIOff: false, categories: {}, siteOverrides: {}, schedules: [], guidedRules: { blockHomeworkOffloading: true, requireAttemptFirst: true, hideFinishedAnswers: true, globalInstructions: [] }, temporaryAllows: [] };
    store.updatePolicy(kid, defaults, "migration-defaults");
    assert.equal(kid.policyRevision, 1, "missing older fields normalize before comparing");
    store.updatePolicy(kid, { ...defaults, masterAIOff: true }, "persisted-edit");
    const reopened = new Store(path);
    const restored = reopened.family("family")!.kids[0];
    assert.equal(restored.policyRevision, 2);
    assert.equal(restored.appliedPolicyRevision, 1);
    assert.ok(restored.policyAppliedAt);
    assert.equal(reopened.updatePolicy(restored, { ...defaults, masterAIOff: true }, "persisted-edit"), true);
    assert.equal(restored.policyRevision, 2, "retry identity survives a restart");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
