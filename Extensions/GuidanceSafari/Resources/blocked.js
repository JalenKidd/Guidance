"use strict";

const params = new URLSearchParams(location.search);
const domain = params.get("d") || "";
const categoryId = params.get("c") || "";
const source = params.get("s") || "";
const $ = (id) => document.getElementById(id);

$("site").textContent = domain || "This site";

function explain(source, categoryName) {
  if (source === "master") return "All AI is off right now.";
  if (source.startsWith("schedule:")) {
    const name = source.slice("schedule:".length);
    return name ? `${name} is on right now.` : "A schedule is on right now.";
  }
  if (source === "override") return "Your parent blocked this site.";
  return categoryName ? `${categoryName} is off.` : "";
}

browser.storage.local.get(["catalog"]).then(({ catalog }) => {
  const category = catalog && catalog.categories.find((c) => c.id === categoryId);
  $("why").textContent = explain(source, category && category.name);
});

browser.runtime.sendMessage({ type: "event", event: { type: "blocked", domain: domain || undefined, categoryId: categoryId || undefined } }).catch(() => {});

$("back").addEventListener("click", () => {
  if (history.length > 1) history.back();
  else window.close();
});

// ---- Ask a parent ----

$("askButton").addEventListener("click", () => {
  $("askButton").hidden = true;
  $("askForm").hidden = false;
  $("reason").focus();
});

$("askForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const reason = $("reason").value.trim();
  const minutes = Number($("minutes").value);
  $("askError").hidden = true;
  $("send").disabled = true;
  const result = await browser.runtime
    .sendMessage({ type: "request", domain, categoryId, kind: "site", reason, minutes })
    .catch((err) => ({ error: String(err) }));
  $("send").disabled = false;
  if (!result || result.error) {
    $("askError").textContent = (result && result.error) || "Couldn't send the request.";
    $("askError").hidden = false;
    return;
  }
  await rememberPending(result.id);
  wait(result.id);
});

async function rememberPending(id) {
  const { pendingRequests = {} } = await browser.storage.local.get(["pendingRequests"]);
  if (id) pendingRequests[domain] = id;
  else delete pendingRequests[domain];
  await browser.storage.local.set({ pendingRequests });
}

function wait(id) {
  $("askButton").hidden = true;
  $("askForm").hidden = true;
  $("waiting").hidden = false;

  const check = async () => {
    const request = await browser.runtime.sendMessage({ type: "request-status", id }).catch(() => null);
    if (request && request.status === 404) {
      // The request no longer exists (for example the server was reset): let them ask again.
      await rememberPending(null);
      $("waiting").hidden = true;
      $("askButton").hidden = false;
      return true;
    }
    if (!request || request.error || request.status === "pending") return false;
    await rememberPending(null);
    if (request.status === "approved") {
      const until = new Date(request.until).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      $("statusText").textContent = `Approved until ${until}. Opening ${domain}…`;
      setTimeout(() => location.replace(`https://${domain}/`), 800);
    } else {
      $("statusText").textContent = "Your parent said not right now.";
    }
    return true;
  };

  const timer = setInterval(async () => {
    if (await check()) clearInterval(timer);
  }, 4000);
  check().then((done) => done && clearInterval(timer));
}

// Coming back to this page while a request is still waiting.
browser.storage.local.get(["pendingRequests"]).then(({ pendingRequests = {} }) => {
  if (pendingRequests[domain]) wait(pendingRequests[domain]);
});

// ---- Unblocked while this page is open ----
// If a parent allows the site (or a schedule ends), go back to it without the kid reloading.

async function stillBlocked() {
  const { policy, catalog } = await browser.storage.local.get(["policy", "catalog"]);
  if (!policy || !catalog || !domain) return true;
  return GuidanceResolver.resolveSite(domain, policy, catalog, new Date()).state === "block";
}

async function recheck() {
  if (document.visibilityState !== "visible") return;
  await browser.runtime.sendMessage({ type: "sync-if-stale" }).catch(() => {});
  if (!(await stillBlocked())) {
    $("waiting").hidden = false;
    $("askButton").hidden = true;
    $("askForm").hidden = true;
    $("statusText").textContent = `${domain} is allowed now. Opening it…`;
    setTimeout(() => location.replace(`https://${domain}/`), 800);
    return true;
  }
  return false;
}

const unblockTimer = setInterval(async () => {
  if (await recheck()) clearInterval(unblockTimer);
}, 15000);
document.addEventListener("visibilitychange", recheck);
