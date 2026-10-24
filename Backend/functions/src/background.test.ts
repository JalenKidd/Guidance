import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { createContext, runInContext } from "node:vm";

const backgroundSource = readFileSync(new URL("../../../Extensions/GuidanceSafari/Resources/background.js", import.meta.url), "utf8");
const resolverSource = readFileSync(new URL("../../../Extensions/GuidanceSafari/Resources/shared/resolver.js", import.meta.url), "utf8");

type State = Record<string, any>;
type Request = { path: string; method: string; token?: string; body?: any; signal: AbortSignal };
type WorkerOptions = {
  state?: State;
  request: (request: Request) => unknown | Promise<unknown>;
  install?: (rules: any[], state: State) => void | Promise<void>;
  scheduleTimeout?: (callback: () => void) => ReturnType<typeof setTimeout>;
  status?: (path: string) => number;
};

function worker({ state = {}, request, install, scheduleTimeout, status }: WorkerOptions) {
  let listener: (message: unknown) => Promise<unknown>;
  let installs = 0;
  let rules: any[] = [];
  const context = createContext({
    console: { warn() {} },
    AbortController,
    setTimeout: scheduleTimeout || setTimeout,
    clearTimeout,
    browser: {
      storage: { local: {
        async get(keys: string[]) {
          return structuredClone(Object.fromEntries(keys.map((key) => [key, state[key]])));
        },
        async set(values: State) { Object.assign(state, structuredClone(values)); },
      } },
      declarativeNetRequest: {
        async getDynamicRules() { return structuredClone(rules); },
        async updateDynamicRules({ addRules }: { addRules: any[] }) {
          installs++;
          await install?.(addRules, state);
          rules = structuredClone(addRules);
        },
      },
      runtime: {
        onMessage: { addListener(value: typeof listener) { listener = value; } },
        onStartup: { addListener() {} },
        onInstalled: { addListener() {} },
      },
      alarms: { create() {}, onAlarm: { addListener() {} } },
    },
    async fetch(url: string, options: { method: string; headers: Record<string, string>; body?: string; signal: AbortSignal }) {
      const value = await request({
        path: new URL(url).pathname,
        method: options.method,
        token: options.headers.authorization?.replace(/^Bearer /, ""),
        body: options.body ? JSON.parse(options.body) : undefined,
        signal: options.signal,
      });
      const responseStatus = status?.(new URL(url).pathname) ?? 200;
      return { ok: responseStatus >= 200 && responseStatus < 300, status: responseStatus, async text() { return JSON.stringify(value ?? {}); } };
    },
  });
  runInContext(resolverSource, context);
  runInContext(backgroundSource, context);
  return {
    state,
    get installs() { return installs; },
    get rules() { return rules; },
    send: (message: unknown) => listener(message),
  };
}

const identity = { serverURL: "https://guidance.test", deviceToken: "device-one" };
const catalog = { version: 1, categories: [{ id: "chatbots", domains: ["chatgpt.com"] }] };
const policy = { masterAIOff: true, categories: { chatbots: "block" }, siteOverrides: {}, schedules: [], temporaryAllows: [] };
function initialState(): State { return { ...identity, catalog, catalogVersion: 1 }; }
function device(revision?: number) {
  return { policy, catalogVersion: 1, policyRevision: revision, kidName: "Maya" };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

test("extension acknowledges the exact revision only after storage and DNR installation succeed", async () => {
  const requests: Request[] = [];
  let installed = false;
  const w = worker({
    state: initialState(),
    install(rules, state) {
      assert.equal(state.policyRevision, 7, "policy is saved before installing");
      assert.equal(state.policy.masterAIOff, true);
      assert.equal(rules[0].action.type, "block");
      installed = true;
    },
    request(req) {
      requests.push(req);
      if (req.path === "/device/policy") return device(7);
      assert.equal(req.path, "/device/policy-applied");
      assert.equal(req.token, identity.deviceToken);
      assert.equal(req.body.policyRevision, 7);
      assert.ok(installed, "download alone must not acknowledge delivery");
      return {};
    },
  });
  await w.send({ type: "sync" });
  assert.equal(w.installs, 1);
  assert.ok(w.state.rulesAppliedAt > 0);
  assert.equal(w.state.policyAcknowledged.policyRevision, 7);
  assert.deepEqual(requests.map((req) => req.path), ["/device/policy", "/device/policy-applied"]);
});

test("failed DNR installation does not advance the receipt or successful install time", async () => {
  const previousReceipt = { ...identity, policyRevision: 6 };
  const requests: Request[] = [];
  const w = worker({
    state: { ...initialState(), rulesAppliedAt: 123, policyApplied: previousReceipt },
    install() { throw new Error("Safari rejected the rule"); },
    request(req) { requests.push(req); return device(8); },
  });
  await w.send({ type: "sync" });
  assert.equal(w.state.policyRevision, 8, "download may succeed while installation fails");
  assert.equal(w.state.rulesAppliedAt, 123);
  assert.equal(w.state.policyApplied.policyRevision, 6);
  assert.equal(w.state.policyAcknowledged, undefined);
  assert.match(w.state.rulesApplyError, /Safari rejected/);
  assert.equal(requests.length, 1, "must not acknowledge a failed install");
});

test("network failures preserve cached policy and its revision for offline blocking", async () => {
  const state: State = { ...initialState(), policy, policyRevision: 4, policyIdentity: identity, lastSync: 456 };
  const w = worker({ state, request() { throw new Error("offline"); } });
  await w.send({ type: "sync" });
  assert.equal(state.policyRevision, 4);
  assert.deepEqual(state.policy, policy);
  assert.equal(state.lastSync, 456);
  assert.equal(w.rules[0].action.type, "block");
  assert.equal(state.policyApplied.policyRevision, 4);
  assert.equal(state.policyAcknowledged, undefined);
});

test("a lost acknowledgement response is retried from persistent cache after worker restart", async () => {
  const state = initialState();
  let acknowledgements = 0;
  const first = worker({ state, request(req) {
    if (req.path === "/device/policy") return device(5);
    acknowledgements++;
    // The server may have accepted it, but the worker never received the response.
    throw new Error("response lost");
  } });
  await first.send({ type: "sync" });
  assert.equal(state.policyApplied.policyRevision, 5);
  assert.equal(state.policyAcknowledged, undefined);
  const restarted = worker({ state, request(req) {
    if (req.path === "/device/policy") throw new Error("policy download unavailable");
    assert.equal(req.path, "/device/policy-applied");
    assert.equal(req.body.policyRevision, 5);
    acknowledgements++;
    return {};
  } });
  await restarted.send({ type: "sync" });
  assert.equal(acknowledgements, 2);
  assert.equal(restarted.state.policyAcknowledged.policyRevision, 5);
});

test("an unconfirmed install retries without waiting for the next policy download", async () => {
  const state = initialState();
  let calls = 0;
  const w = worker({ state, request(req) {
    if (req.path === "/device/policy") return device(3);
    calls++;
    if (calls === 1) throw new Error("acknowledgement interrupted");
    return {};
  } });
  await w.send({ type: "sync" });
  await w.send({ type: "sync-if-stale" });
  assert.equal(w.installs, 1);
  assert.equal(calls, 2);
  assert.equal(state.policyAcknowledged.policyRevision, 3);
});

test("a server rejection never marks an installed stale revision as acknowledged", async () => {
  const w = worker({
    state: initialState(),
    request(req) { return req.path === "/device/policy" ? device(2) : { error: "Policy revision is no longer current" }; },
    status(path) { return path === "/device/policy-applied" ? 409 : 200; },
  });
  await w.send({ type: "sync" });
  assert.equal(w.state.policyApplied.policyRevision, 2);
  assert.equal(w.state.policyAcknowledged, undefined);
  assert.match(w.state.lastError, /no longer current/);
});

test("older servers without policy revisions keep blocking without claiming applied status", async () => {
  const w = worker({ state: initialState(), request(req) {
    assert.equal(req.path, "/device/policy");
    return device();
  } });
  await w.send({ type: "sync" });
  assert.equal(w.rules[0].action.type, "block");
  assert.equal(w.state.policyRevision, null);
  assert.equal(w.state.policyApplied, null);
  assert.equal(w.state.policyAcknowledged, undefined);
});

test("pairing waits for an in-flight sync and never acknowledges old rules for the new device", async () => {
  const started = deferred<void>();
  const oldPolicy = deferred<ReturnType<typeof device>>();
  const requests: Request[] = [];
  const w = worker({ state: initialState(), request(req) {
    requests.push(req);
    if (req.path === "/pair") return { deviceToken: "device-two", kidName: "Leo" };
    if (req.path === "/catalog") return catalog;
    if (req.path === "/device/policy") {
      if (req.token === identity.deviceToken) { started.resolve(); return oldPolicy.promise; }
      return device(12);
    }
    return {};
  } });
  const oldSync = w.send({ type: "sync" });
  await started.promise;
  const pairing = w.send({ type: "pair", code: "ABC123" });
  await Promise.resolve();
  assert.equal(requests.some((req) => req.path === "/pair"), false);
  oldPolicy.resolve(device(11));
  await Promise.all([oldSync, pairing]);
  const acknowledgements = requests.filter((req) => req.path === "/device/policy-applied");
  assert.deepEqual(acknowledgements.map((req) => [req.token, req.body.policyRevision]), [["device-one", 11], ["device-two", 12]]);
  assert.equal(w.state.policyAcknowledged.deviceToken, "device-two");
  assert.equal(w.state.policyAcknowledged.policyRevision, 12);
});

test("a changed device token discards an old policy download before installation or acknowledgement", async () => {
  const started = deferred<void>();
  const response = deferred<ReturnType<typeof device>>();
  const state = initialState();
  const w = worker({ state, request(req) {
    assert.equal(req.path, "/device/policy");
    started.resolve();
    return response.promise;
  } });
  const syncing = w.send({ type: "sync" });
  await started.promise;
  state.deviceToken = "replacement-device";
  response.resolve(device(9));
  await syncing;
  assert.equal(w.installs, 0);
  assert.equal(state.policyRevision, undefined);
  assert.equal(state.policyAcknowledged, undefined);
});

test("a stalled connection times out so the next sync can recover", async () => {
  let timeout!: () => void;
  const started = deferred<void>();
  let stalled = true;
  const w = worker({
    state: initialState(),
    scheduleTimeout(callback) { timeout = callback; return 0 as unknown as ReturnType<typeof setTimeout>; },
    request(req) {
      if (req.path === "/device/policy" && stalled) {
        return new Promise((_, reject) => {
          req.signal.addEventListener("abort", () => reject(new Error("aborted")));
          started.resolve();
        });
      }
      return req.path === "/device/policy" ? device(10) : {};
    },
  });
  const first = w.send({ type: "sync" });
  await started.promise;
  timeout();
  await first;
  assert.match(w.state.lastError, /timed out/);
  stalled = false;
  await w.send({ type: "sync" });
  assert.equal(w.state.policyAcknowledged.policyRevision, 10);
});
