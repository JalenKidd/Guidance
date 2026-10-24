"use strict";

const $ = (id) => document.getElementById(id);

function timeAgo(ms) {
  if (!ms) return "never";
  const seconds = Math.round((Date.now() - ms) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  return `${Math.round(minutes / 60)} hr ago`;
}

const ALL_SITES = { origins: ["<all_urls>"] };

/**
 * Only warn when Guidance clearly can't run on websites. Safari often answers
 * permissions.contains() with false even when "All Websites: Allow" is on, so a
 * recent run of the page script (content/guard.js) counts as proof of access.
 */
async function renderAccess() {
  const { lastPageRun = 0 } = await browser.storage.local.get(["lastPageRun"]);
  if (Date.now() - lastPageRun < 24 * 60 * 60 * 1000) {
    $("access").hidden = true;
    return;
  }
  let granted = false;
  try {
    granted =
      (await browser.permissions.contains(ALL_SITES)) ||
      (await browser.permissions.contains({ origins: ["*://*/*"] }));
  } catch (_) {
    granted = true; // Can't tell; don't nag.
  }
  $("access").hidden = granted;
}

$("grantAccess").addEventListener("click", async () => {
  try {
    await browser.permissions.request(ALL_SITES);
  } catch (_) {
    // Safari may only allow this from Settings; the hint below the button covers it.
  }
  renderAccess();
  browser.runtime.sendMessage({ type: "sync" }).catch(() => {});
});

async function render() {
  renderAccess();
  const s = await browser.storage.local.get(["deviceToken", "guardianName", "lastSync", "lastError", "serverURL"]);
  $("server").value = s.serverURL || "";
  const paired = Boolean(s.deviceToken);
  $("paired").hidden = !paired;
  $("pairForm").hidden = paired;
  $("dot").hidden = !paired;
  if (!paired) {
    $("subtitle").textContent = "Not paired yet";
    return;
  }
  $("subtitle").textContent = `Guardian: ${s.guardianName || "your parent"}`;
  $("lastSync").textContent = timeAgo(s.lastSync);
  // Green when rules are fresh; orange when running on saved rules because the server can't be reached.
  const stale = !s.lastSync || Date.now() - s.lastSync > 10 * 60 * 1000;
  $("dot").classList.toggle("warn", stale);
  $("dot").title = stale ? `Using saved rules (last update ${timeAgo(s.lastSync)})` : "Rules active";
  $("syncError").hidden = !s.lastError;
  $("syncError").textContent = s.lastError ? `Couldn't reach the Guidance server: ${s.lastError}` : "";
}

$("pairForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("pairError").hidden = true;
  $("pairButton").disabled = true;
  $("pairButton").textContent = "Pairing…";
  const serverURL = $("server").value.trim() || undefined;
  const result = await browser.runtime.sendMessage({ type: "pair", code: $("code").value.trim(), serverURL });
  $("pairButton").disabled = false;
  $("pairButton").textContent = "Pair this phone";
  if (!result || result.error) {
    $("pairError").textContent = (result && result.error) || "Couldn't pair. Check the code and the server address.";
    $("pairError").hidden = false;
    return;
  }
  $("code").value = "";
  render();
browser.runtime.sendMessage({ type: "sync-if-stale" }).then(render).catch(() => {});
});

$("showPair").addEventListener("click", () => {
  $("paired").hidden = true;
  $("pairForm").hidden = false;
});

render();
browser.runtime.sendMessage({ type: "sync-if-stale" }).then(render).catch(() => {});
