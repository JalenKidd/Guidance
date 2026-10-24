/*
 * Guidance background script.
 * - Pulls this kid's rules and the AI category catalog from the Guidance server.
 * - Turns them into Safari declarativeNetRequest rules (blocked sites redirect to blocked.html).
 * - Answers prompt checks from the content script on Guided chatbot sites.
 * - Queues activity events and sends them when the server is reachable.
 *
 * The last rules are kept when the server can't be reached, so blocking keeps working offline.
 */
"use strict";

const DEFAULT_SERVER_URL = "http://127.0.0.1:8080";
const SYNC_ALARM = "guidance-sync";
// Open pages ask every 15 s; anything older than this gets a fresh copy from the server.
const STALE_AFTER_MS = 10 * 1000;
const MAX_PENDING_EVENTS = 200;
const API_TIMEOUT_MS = 15 * 1000;

function storageGet(keys) {
  return browser.storage.local.get(keys);
}

function storageSet(values) {
  return browser.storage.local.set(values);
}

async function api(path, options = {}) {
  // A rule sync keeps the same server and device throughout, even if pairing changes.
  const { serverURL = DEFAULT_SERVER_URL, deviceToken } = options.identity || await storageGet(["serverURL", "deviceToken"]);
  // A stalled connection must release the queue so cached rules and retries can run.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  try {
    const res = await fetch(serverURL.replace(/\/+$/, "") + path, {
      method: options.method || "GET",
      headers: {
        "content-type": "application/json",
        ...(deviceToken && !options.anonymous ? { authorization: `Bearer ${deviceToken}` } : {}),
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: controller.signal,
    });
    const text = await res.text();
    const json = text ? JSON.parse(text) : {};
    if (!res.ok) {
      const error = new Error(json.error || `Server error (${res.status})`);
      error.status = res.status;
      throw error;
    }
    return json;
  } catch (err) {
    if (controller.signal.aborted) throw new Error("Guidance server request timed out");
    throw err;
  } finally {
    clearTimeout(timeout);
  }
}

// ---- Rules ----

function ruleSetFor(policy, catalog) {
  if (!policy || !catalog) return [];
  const resolved = GuidanceResolver.resolveAll(policy, catalog, new Date());
  const rules = [];
  let id = 1;

  for (const r of resolved) {
    if (r.state === "block") {
      // Pages themselves are sent to blocked.html by content/guard.js: Safari on iOS shows a
      // blank tab for a declarativeNetRequest redirect to an extension page. These rules stop
      // everything a blocked site loads or embeds, so it can't work even before the redirect.
      rules.push({
        id: id++,
        priority: 1,
        action: { type: "block" },
        condition: { requestDomains: [r.domain], resourceTypes: ["sub_frame", "xmlhttprequest", "script", "websocket"] },
      });
    } else if (r.source === "override" || r.source === "approved") {
      // "Allow claude.ai" and approved requests must win over a block rule on a parent domain.
      rules.push({
        id: id++,
        priority: 2,
        action: { type: "allow" },
        condition: { requestDomains: [r.domain] },
      });
    }
  }
  return rules;
}

// Safari may wake the worker from several pages at once. Keep downloads, installs,
// acknowledgements and re-pairing ordered so one operation cannot confirm another's rules.
let rulesOperation = Promise.resolve();
function withRulesOperation(operation) {
  const next = rulesOperation.then(operation, operation);
  rulesOperation = next.catch(() => {});
  return next;
}

function identityFrom(state) {
  return { serverURL: (state.serverURL || DEFAULT_SERVER_URL).replace(/\/+$/, ""), deviceToken: state.deviceToken };
}

function sameIdentity(a, b) {
  return a.serverURL === b.serverURL && a.deviceToken === b.deviceToken;
}

async function isCurrentIdentity(identity) {
  return sameIdentity(identity, identityFrom(await storageGet(["serverURL", "deviceToken"])));
}

function sameReceipt(a, b) {
  return a && b && a.policyRevision === b.policyRevision && sameIdentity(a, b);
}

async function recordSyncError(err, identity) {
  if (await isCurrentIdentity(identity)) {
    await storageSet({ lastError: err.message || String(err), lastErrorAt: Date.now() });
  }
}

async function acknowledgeRules(identity) {
  const { policyApplied, policyAcknowledged } = await storageGet(["policyApplied", "policyAcknowledged"]);
  if (!identity.deviceToken || !policyApplied || !sameIdentity(policyApplied, identity) ||
      sameReceipt(policyApplied, policyAcknowledged) || !(await isCurrentIdentity(identity))) return;
  try {
    await api("/device/policy-applied", {
      method: "POST", body: { policyRevision: policyApplied.policyRevision }, identity,
    });
    // Persist only after the server accepts the acknowledgement. A lost response retries.
    if (await isCurrentIdentity(identity)) await storageSet({ policyAcknowledged: policyApplied });
  } catch (err) {
    await recordSyncError(new Error(`Could not confirm installed rules: ${err.message || String(err)}`), identity);
  }
}

// Called only inside withRulesOperation. The receipt describes this exact snapshot,
// never a newer policy that happened to arrive while Safari was installing rules.
async function applyRulesNow(expectedIdentity) {
  const state = await storageGet(["serverURL", "deviceToken", "policy", "catalog", "policyRevision", "policyIdentity"]);
  const identity = identityFrom(state);
  if (expectedIdentity && !sameIdentity(identity, expectedIdentity)) return;
  const addRules = ruleSetFor(state.policy, state.catalog);
  try {
    const existing = await browser.declarativeNetRequest.getDynamicRules();
    if (!(await isCurrentIdentity(identity))) return;
    await browser.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: existing.map((r) => r.id),
      addRules,
    });
    if (!(await isCurrentIdentity(identity))) return;
    const revision = state.policyRevision;
    const policyApplied = state.policy && state.catalog && Number.isSafeInteger(revision) && revision > 0 &&
      state.policyIdentity && sameIdentity(state.policyIdentity, identity)
      ? { ...identity, policyRevision: revision } : null;
    await storageSet({
      rulesAppliedAt: Date.now(),
      rulesApplyError: null,
      blockedRuleCount: addRules.filter((r) => r.action.type === "block").length,
      policyApplied,
    });
    await acknowledgeRules(identity);
  } catch (err) {
    // Keep the last successful install time and receipt. A failed installation must
    // never be reported to the parent as applied, even if the policy was downloaded.
    console.warn("Guidance: could not update blocking rules", err);
    if (await isCurrentIdentity(identity)) {
      await storageSet({ rulesApplyError: err.message || String(err) });
      await recordSyncError(new Error(`Could not apply blocking rules: ${err.message || String(err)}`), identity);
    }
  }
}

function applyRules() {
  return withRulesOperation(() => applyRulesNow());
}

// ---- Sync ----

let syncing = null;

async function syncCurrentPairing() {
  const state = await storageGet(["serverURL", "deviceToken", "catalogVersion", "catalog"]);
  const identity = identityFrom(state);
  if (!identity.deviceToken) {
    await applyRulesNow(identity);
    return;
  }
  try {
    const device = await api("/device/policy", { identity });
    const updates = {
      policy: device.policy,
      // Older servers have no revision; keep their rules working without claiming delivery.
      policyRevision: Number.isSafeInteger(device.policyRevision) && device.policyRevision > 0 ? device.policyRevision : null,
      policyIdentity: identity,
      kidName: device.kidName,
      guardianName: device.guardianName || null,
      lastSync: Date.now(),
      lastError: null,
    };
    if (!state.catalog || device.catalogVersion !== state.catalogVersion) {
      const fresh = await api("/catalog", { anonymous: true, identity });
      updates.catalog = fresh;
      updates.catalogVersion = fresh.version;
    }
    if (!(await isCurrentIdentity(identity))) return;
    await storageSet(updates);
  } catch (err) {
    await recordSyncError(err, identity);
  }
  // A network outage retains and re-installs cached rules. It also retries an
  // installed-but-unconfirmed revision after a worker restart or a lost response.
  await applyRulesNow(identity);
  if (await isCurrentIdentity(identity)) {
    try { await flushEvents(); } catch (err) { await recordSyncError(err, identity); }
  }
}

function sync() {
  if (syncing) return syncing;
  syncing = withRulesOperation(syncCurrentPairing).finally(() => { syncing = null; });
  return syncing;
}

async function syncIfStale() {
  const { lastSync = 0, rulesAppliedAt = 0, policyApplied, policyAcknowledged } =
    await storageGet(["lastSync", "rulesAppliedAt", "policyApplied", "policyAcknowledged"]);
  const now = Date.now();
  if (now - lastSync > STALE_AFTER_MS) return sync();
  // Even without a server round trip, re-apply so schedules switch on time.
  if (now - rulesAppliedAt > STALE_AFTER_MS) return applyRules();
  if (policyApplied && !sameReceipt(policyApplied, policyAcknowledged)) {
    return withRulesOperation(async () => {
      const identity = identityFrom(await storageGet(["serverURL", "deviceToken"]));
      await acknowledgeRules(identity);
    });
  }
}

// ---- Events ----

async function queueEvent(event) {
  const { pendingEvents = [] } = await storageGet(["pendingEvents"]);
  pendingEvents.push({ ...event, at: new Date().toISOString() });
  await storageSet({ pendingEvents: pendingEvents.slice(-MAX_PENDING_EVENTS) });
  flushEvents().catch(() => {});
}

async function flushEvents() {
  const { pendingEvents = [], deviceToken } = await storageGet(["pendingEvents", "deviceToken"]);
  if (!deviceToken || pendingEvents.length === 0) return;
  const batch = pendingEvents.slice(0, 50);
  await api("/device/events", { method: "POST", body: { events: batch } });
  const { pendingEvents: latest = [] } = await storageGet(["pendingEvents"]);
  await storageSet({ pendingEvents: latest.slice(batch.length) });
}

// ---- Pairing ----

function pair(code, serverURL) {
  return withRulesOperation(async () => {
    const current = identityFrom(await storageGet(["serverURL", "deviceToken"]));
    const identity = { serverURL: (serverURL || current.serverURL).replace(/\/+$/, "") };
    const result = await api("/pair", { method: "POST", body: { code }, anonymous: true, identity });
    await storageSet({
      serverURL: identity.serverURL,
      deviceToken: result.deviceToken,
      kidName: result.kidName,
      guardianName: result.guardianName || null,
      policy: null,
      policyRevision: null,
      policyIdentity: null,
      policyApplied: null,
      policyAcknowledged: null,
      rulesAppliedAt: 0,
      lastSync: 0,
      catalogVersion: null,
    });
    await syncCurrentPairing();
    return { kidName: result.kidName, guardianName: result.guardianName };
  });
}

// ---- Messages from content scripts, blocked.html and the popup ----

browser.runtime.onMessage.addListener((message) => {
  switch (message && message.type) {
    case "check":
      return api("/device/check", {
        method: "POST",
        body: { site: message.site, prompt: message.prompt, mode: message.mode || "guided" },
      }).catch((err) => ({ error: err.message }));
    case "check-response":
      return api("/device/check-response", {
        method: "POST",
        body: { site: message.site, prompt: message.prompt, response: message.response },
      }).catch((err) => ({ error: err.message }));
    case "request":
      return api("/device/requests", {
        method: "POST",
        body: {
          domain: message.domain,
          categoryId: message.categoryId || undefined,
          kind: message.kind,
          reason: message.reason,
          minutes: message.minutes,
        },
      }).catch((err) => ({ error: err.message }));
    case "request-status":
      return api(`/device/requests/${encodeURIComponent(message.id)}`)
        .then(async (request) => {
          // Pull the new temporary allow right away so the site opens without waiting for the next sync.
          if (request.status === "approved") await sync();
          return request;
        })
        .catch((err) => ({ error: err.message, status: err.status }));
    case "event":
      return queueEvent(message.event).then(() => ({ ok: true }));
    case "sync-if-stale":
      return syncIfStale().then(() => ({ ok: true }));
    case "sync":
      return sync().then(() => ({ ok: true }));
    case "pair":
      return pair(message.code, message.serverURL).catch((err) => ({ error: err.message }));
    default:
      return undefined;
  }
});

browser.alarms.create(SYNC_ALARM, { periodInMinutes: 1 });
browser.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === SYNC_ALARM) sync();
});
browser.runtime.onStartup.addListener(() => sync());
browser.runtime.onInstalled.addListener(() => sync());
