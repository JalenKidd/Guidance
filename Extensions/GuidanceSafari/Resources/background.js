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

function storageGet(keys) {
  return browser.storage.local.get(keys);
}

function storageSet(values) {
  return browser.storage.local.set(values);
}

async function api(path, options = {}) {
  const { serverURL = DEFAULT_SERVER_URL, deviceToken } = await storageGet(["serverURL", "deviceToken"]);
  const res = await fetch(serverURL.replace(/\/+$/, "") + path, {
    method: options.method || "GET",
    headers: {
      "content-type": "application/json",
      ...(deviceToken && !options.anonymous ? { authorization: `Bearer ${deviceToken}` } : {}),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) {
    const error = new Error(json.error || `Server error (${res.status})`);
    error.status = res.status;
    throw error;
  }
  return json;
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

async function applyRules() {
  const { policy, catalog } = await storageGet(["policy", "catalog"]);
  const addRules = ruleSetFor(policy, catalog);
  try {
    const existing = await browser.declarativeNetRequest.getDynamicRules();
    await browser.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: existing.map((r) => r.id),
      addRules,
    });
  } catch (err) {
    // Older Safari versions may reject redirect rules; content/guard.js still blocks pages.
    console.warn("Guidance: could not update blocking rules", err);
  }
  await storageSet({ rulesAppliedAt: Date.now(), blockedRuleCount: addRules.filter((r) => r.action.type === "block").length });
}

// ---- Sync ----

let syncing = null;

async function sync() {
  if (syncing) return syncing;
  syncing = (async () => {
    const { deviceToken, catalogVersion, catalog } = await storageGet(["deviceToken", "catalogVersion", "catalog"]);
    if (!deviceToken) {
      await applyRules();
      return;
    }
    try {
      const device = await api("/device/policy");
      const updates = {
        policy: device.policy,
        kidName: device.kidName,
        guardianName: device.guardianName || null,
        lastSync: Date.now(),
        lastError: null,
      };
      if (!catalog || device.catalogVersion !== catalogVersion) {
        const fresh = await api("/catalog", { anonymous: true });
        updates.catalog = fresh;
        updates.catalogVersion = fresh.version;
      }
      await storageSet(updates);
      await flushEvents();
    } catch (err) {
      await storageSet({ lastError: err.message || String(err), lastErrorAt: Date.now() });
    }
    await applyRules();
  })().finally(() => {
    syncing = null;
  });
  return syncing;
}

async function syncIfStale() {
  const { lastSync = 0, rulesAppliedAt = 0 } = await storageGet(["lastSync", "rulesAppliedAt"]);
  const now = Date.now();
  if (now - lastSync > STALE_AFTER_MS) return sync();
  // Even without a server round trip, re-apply so schedules switch on time.
  if (now - rulesAppliedAt > STALE_AFTER_MS) return applyRules();
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

async function pair(code, serverURL) {
  if (serverURL) await storageSet({ serverURL });
  const result = await api("/pair", { method: "POST", body: { code }, anonymous: true });
  await storageSet({
    deviceToken: result.deviceToken,
    kidName: result.kidName,
    guardianName: result.guardianName || null,
    lastSync: 0,
    catalogVersion: null,
  });
  await sync();
  return { kidName: result.kidName, guardianName: result.guardianName };
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
