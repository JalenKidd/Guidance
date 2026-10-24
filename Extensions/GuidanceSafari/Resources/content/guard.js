/*
 * Runs on every page.
 * - Blocked site: sends the tab to blocked.html (backup for the declarativeNetRequest rules).
 * - Chatbot set to Guided: checks each prompt against the parent's homework rules, and hides
 *   AI answers that hand over finished schoolwork (showing hints instead).
 * - Every AI site the kid can use: prompts are checked for safety alerts in the background.
 *   That check never pauses or changes what the kid sends.
 * - Rules are re-checked while the page is open, so a parent's change applies without a reload.
 * - "Ask a parent" lets the kid request a temporary exception, with a reason.
 */
(function () {
  "use strict";

  const INSTRUCTIONS_MARKER = "(Parent rules from Guidance:";
  // Same idea as the server's schoolwork check: only pre-blur answers to schoolwork prompts.
  const SCHOOL_CONTEXT = /\b(essay|assignment|homework|worksheet|paper|report|due|teacher|class|grade|turn (it )?in|submit|quiz|test|exam|problem set|lab|paragraphs?)\b/i;
  const RECHECK_MS = 15 * 1000;
  const host = location.hostname.toLowerCase();
  if (!/^https?:$/.test(location.protocol) || !host) return;

  const hiddenAnswers = new Set();
  let current = { mode: "off" };
  let guarding = false;

  function loadState() {
    return browser.storage.local.get(["deviceToken", "policy", "catalog"]);
  }

  /**
   * "block", "guided" (homework checks + safety alerts), "safety" (safety alerts only),
   * or "off" (not paired, or not an AI site).
   */
  function modeFor(data) {
    if (!data.deviceToken || !data.policy || !data.catalog) return { mode: "off" };
    const result = GuidanceResolver.resolveSite(host, data.policy, data.catalog, new Date());
    if (result.state === "block") return { mode: "block", result };
    const category = data.catalog.categories.find((c) => c.id === result.categoryId);
    if (!category && result.source !== "approved" && result.source !== "override") return { mode: "off", result };
    const guided = result.state === "guided" && category && category.supportsGuided;
    return { mode: guided ? "guided" : "safety", result, policy: data.policy };
  }

  /** Re-read the saved rules and apply them to this page. */
  async function evaluate() {
    current = modeFor(await loadState());
    if (current.mode === "block") {
      redirectToBlocked(current.result);
    } else if ((current.mode === "guided" || current.mode === "safety") && !guarding) {
      guarding = true;
      guardPrompts(GuidanceAdapters.forHost(host));
    }
  }

  function syncIfStale() {
    return browser.runtime.sendMessage({ type: "sync-if-stale" }).catch(() => {});
  }

  // Proof that Safari lets Guidance run on websites; the popup checks this, because
  // Safari doesn't reliably report granted website access through browser.permissions.
  browser.storage.local.get(["lastPageRun"]).then(({ lastPageRun = 0 }) => {
    if (Date.now() - lastPageRun > 60 * 1000) browser.storage.local.set({ lastPageRun: Date.now() });
  });

  loadState().then((data) => {
    if (!data.deviceToken) return;
    evaluate();
    syncIfStale();
    // Safari suspends the background script, so open pages ask for fresh rules themselves.
    // New rules arrive through storage.onChanged below; re-evaluating also catches
    // schedules starting and approvals running out.
    setInterval(() => {
      if (document.visibilityState !== "visible") return;
      syncIfStale();
      evaluate();
    }, RECHECK_MS);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState !== "visible") return;
      syncIfStale();
      evaluate();
    });
  });

  browser.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && (changes.policy || changes.catalog || changes.deviceToken)) evaluate();
  });

  function redirectToBlocked(result) {
    window.stop();
    const query = new URLSearchParams({ d: host, c: result.categoryId || "", s: result.source });
    location.replace(browser.runtime.getURL(`blocked.html?${query}`));
  }

  // ---- Prompts ----

  function guardPrompts(adapter) {
    let bypass = false;
    let busy = false;
    let lastSafetyReport = { text: "", at: 0 };

    const inInput = (target) => {
      const input = adapter.input();
      return input && target && (input === target || input.contains(target));
    };
    const onSendButton = (target) => {
      const button = adapter.sendButton();
      return button && (button === target || button.contains(target));
    };

    function promptText() {
      return GuidanceAdapters.getText(adapter.input()).split(INSTRUCTIONS_MARKER)[0].trim();
    }

    function submit(input) {
      bypass = true;
      setTimeout(() => {
        const button = adapter.sendButton();
        if (button && !button.disabled) {
          button.click();
        } else {
          input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", keyCode: 13, bubbles: true }));
        }
        setTimeout(() => {
          bypass = false;
        }, 400);
      }, 120);
    }

    /** Safety alerts only: read the prompt as it goes out, without touching the page. */
    function reportForSafety() {
      const prompt = promptText();
      const now = Date.now();
      // One send can fire keydown, click and submit; report it once.
      if (!prompt || (prompt === lastSafetyReport.text && now - lastSafetyReport.at < 3000)) return;
      lastSafetyReport = { text: prompt, at: now };
      browser.runtime.sendMessage({ type: "check", site: host, prompt, mode: "safety" }).catch(() => {});
    }

    async function handleGuidedSend() {
      const input = adapter.input();
      const text = GuidanceAdapters.getText(input).trim();
      if (!text || busy) return;
      const prompt = text.split(INSTRUCTIONS_MARKER)[0].trim();

      busy = true;
      const status = showToast("Checking with your family's rules…");
      let decision = null;
      try {
        decision = await browser.runtime.sendMessage({ type: "check", site: host, prompt, mode: "guided" });
      } catch (_) {
        decision = null;
      }
      status.remove();
      busy = false;

      if (decision && decision.action === "block") {
        showBlockedPrompt(adapter, decision);
        return;
      }

      // Allowed, or the server couldn't be reached: send it, with the parent's rules attached when we have them.
      if (decision && decision.instructions && !text.includes(INSTRUCTIONS_MARKER)) {
        GuidanceAdapters.setText(input, `${text}\n\n${decision.instructions}`);
      }
      submit(input);
      const rules = current.policy && current.policy.guidedRules;
      if (!rules || rules.hideFinishedAnswers !== false) watchForAnswer(adapter, prompt);
    }

    function onSendAttempt(e) {
      if (bypass) return;
      if (current.mode === "block") {
        e.preventDefault();
        e.stopImmediatePropagation();
        redirectToBlocked(current.result);
      } else if (current.mode === "safety") {
        reportForSafety();
      } else if (current.mode === "guided") {
        e.preventDefault();
        e.stopImmediatePropagation();
        handleGuidedSend();
      }
    }

    document.addEventListener(
      "keydown",
      (e) => {
        if (e.key !== "Enter" || e.shiftKey || e.isComposing || !inInput(e.target)) return;
        onSendAttempt(e);
      },
      true
    );

    document.addEventListener(
      "click",
      (e) => {
        if (onSendButton(e.target)) onSendAttempt(e);
      },
      true
    );

    document.addEventListener(
      "submit",
      (e) => {
        if (inInput(e.target.querySelector && e.target.querySelector("textarea, [contenteditable='true']"))) onSendAttempt(e);
      },
      true
    );
  }

  // ---- AI answers ----

  /**
   * Wait for the AI's new answer to finish, then ask the server whether it hands over
   * finished schoolwork. Answers to schoolwork prompts stay blurred while they stream
   * and are checked, so they can't be read before the check.
   */
  function watchForAnswer(adapter, prompt) {
    const before = new Set(adapter.responses());
    const preBlur = SCHOOL_CONTEXT.test(prompt);
    let lastText = "";
    let stableTicks = 0;
    let ticks = 0;
    let watched = null;

    const timer = setInterval(async () => {
      ticks += 1;
      if (ticks > 180) {
        clearInterval(timer);
        if (watched) reveal(watched);
        return;
      }
      const all = adapter.responses();
      const latest = all[all.length - 1];
      if (!latest || before.has(latest)) return;
      if (watched !== latest) {
        watched = latest;
        if (preBlur) blur(latest, "Guidance is checking this answer…");
      }

      const text = (latest.innerText || "").trim();
      if (text.length < 40) return;
      if (text === lastText) {
        stableTicks += 1;
      } else {
        stableTicks = 0;
        lastText = text;
      }
      if (stableTicks < 2) return;
      clearInterval(timer);

      let decision = null;
      try {
        decision = await browser.runtime.sendMessage({ type: "check-response", site: host, prompt, response: text.slice(0, 30000) });
      } catch (_) {
        decision = null;
      }
      if (decision && decision.action === "hide") {
        blur(latest, null);
        hiddenAnswers.add(latest);
        showHiddenAnswer(decision);
      } else {
        reveal(latest);
      }
    }, 1000);
  }

  function blur(el, label) {
    el.dataset.guidanceHidden = "1";
    el.style.setProperty("filter", "blur(9px)", "important");
    el.style.setProperty("user-select", "none", "important");
    el.style.setProperty("pointer-events", "none", "important");
    el.setAttribute("aria-hidden", "true");
    if (label) el.title = label;
  }

  function reveal(el) {
    delete el.dataset.guidanceHidden;
    el.style.removeProperty("filter");
    el.style.removeProperty("user-select");
    el.style.removeProperty("pointer-events");
    el.removeAttribute("aria-hidden");
    el.removeAttribute("title");
  }

  // Chat pages re-render often; keep hidden answers hidden.
  setInterval(() => {
    for (const el of hiddenAnswers) {
      if (!el.isConnected) hiddenAnswers.delete(el);
      else if (el.style.getPropertyValue("filter") === "") blur(el, null);
    }
  }, 1000);

  function revealAllHidden() {
    for (const el of hiddenAnswers) reveal(el);
    hiddenAnswers.clear();
  }

  // ---- UI (shadow DOM so the page's CSS can't touch it) ----

  const STYLE = `
    :host { all: initial; }
    .wrap { position: fixed; inset: auto 12px 12px 12px; z-index: 2147483647; font: 15px/1.4 -apple-system, system-ui, sans-serif; }
    .card { max-width: 520px; margin: 0 auto; background: #fff; color: #2a0a10; border-radius: 18px; padding: 16px; box-shadow: 0 10px 40px rgba(0,0,0,.25); border: 1px solid rgba(209,26,46,.25); max-height: 70vh; overflow: auto; }
    .toast { max-width: 360px; margin: 0 auto; background: #2a0a10; color: #fff; border-radius: 14px; padding: 10px 14px; text-align: center; }
    .title { font-weight: 700; font-size: 16px; display: flex; gap: 8px; align-items: center; }
    .dot { width: 10px; height: 10px; border-radius: 50%; background: #d11a2e; flex: none; }
    .reason { margin: 6px 0 10px; color: #5c2a33; }
    .box { background: #ffe1e5; border-radius: 12px; padding: 10px 12px; margin-bottom: 12px; }
    .box ol { margin: 0; padding-left: 20px; }
    .box li + li { margin-top: 4px; }
    .label { font-size: 11px; font-weight: 800; letter-spacing: .06em; text-transform: uppercase; color: #a80a1f; margin-bottom: 4px; }
    .row { display: flex; gap: 8px; flex-wrap: wrap; }
    button { font: inherit; font-weight: 600; border: 0; border-radius: 12px; padding: 10px 14px; cursor: pointer; flex: 1; }
    .primary { background: #d11a2e; color: #fff; }
    .secondary { background: #f1e6e8; color: #2a0a10; }
    textarea { box-sizing: border-box; width: 100%; font: inherit; border-radius: 12px; border: 1px solid #e3c9cd; padding: 10px; min-height: 64px; margin: 6px 0 8px; background: #fff; color: inherit; }
    .lengths { display: flex; gap: 6px; margin-bottom: 10px; }
    .lengths button { padding: 8px; background: #f1e6e8; color: #2a0a10; }
    .lengths button[aria-pressed="true"] { background: #2a0a10; color: #fff; }
    .note { font-size: 13px; color: #6b3a43; margin-top: 8px; }
    @media (prefers-color-scheme: dark) {
      .card { background: #1f0a0e; color: #fff; border-color: rgba(255,77,89,.35); }
      .reason, .note { color: #f3c9cf; }
      .box { background: #40121a; }
      .label { color: #ff7782; }
      .secondary, .lengths button { background: #3a2226; color: #fff; }
      .lengths button[aria-pressed="true"] { background: #fff; color: #2a0a10; }
      textarea { background: #2a1418; border-color: #4a2a30; }
    }`;

  let currentPanel = null;

  function mount(html) {
    const hostEl = document.createElement("guidance-overlay");
    const shadow = hostEl.attachShadow({ mode: "closed" });
    shadow.innerHTML = `<style>${STYLE}</style>${html}`;
    document.documentElement.appendChild(hostEl);
    return { shadow, remove: () => hostEl.remove() };
  }

  function showPanel(html, onAction) {
    if (currentPanel) currentPanel.remove();
    const ui = mount(`<div class="wrap" role="alertdialog" aria-label="Guidance"><div class="card">${html}</div></div>`);
    currentPanel = ui;
    ui.shadow.addEventListener("click", (e) => {
      const button = e.target.closest && e.target.closest("button");
      if (button && button.dataset.action) onAction(button.dataset.action, ui, button);
    });
    return ui;
  }

  function closePanel(ui) {
    ui.remove();
    if (currentPanel === ui) currentPanel = null;
  }

  function escapeHTML(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }

  function showToast(text, ms) {
    const ui = mount(`<div class="wrap"><div class="toast">${escapeHTML(text)}</div></div>`);
    if (ms) setTimeout(() => ui.remove(), ms);
    return ui;
  }

  function showBlockedPrompt(adapter, decision) {
    const html = `
      <div class="title"><span class="dot"></span>Try it yourself first</div>
      <div class="reason">${escapeHTML(decision.reason)} Your family's Guidance rules don't allow this one.</div>
      ${decision.suggestedPrompt ? `<div class="box"><div class="label">Ask this instead</div>${escapeHTML(decision.suggestedPrompt)}</div>` : ""}
      <div class="row">
        ${decision.suggestedPrompt ? `<button class="primary" data-action="use">Use this instead</button>` : ""}
        <button class="secondary" data-action="edit">Edit my message</button>
      </div>
      <div class="row" style="margin-top:8px"><button class="secondary" data-action="ask">Ask a parent</button></div>`;
    showPanel(html, (action, ui) => {
      if (action === "ask") return showAskParent(ui, "guided");
      if (action !== "use" && action !== "edit") return;
      if (action === "use") {
        const input = adapter.input();
        if (input) GuidanceAdapters.setText(input, decision.suggestedPrompt);
      }
      closePanel(ui);
      const input = adapter.input();
      if (input) input.focus();
    });
  }

  function showHiddenAnswer(decision) {
    const hints = (decision.hints || []).map((h) => `<li>${escapeHTML(h)}</li>`).join("");
    const html = `
      <div class="title"><span class="dot"></span>Answer hidden</div>
      <div class="reason">${escapeHTML(decision.reason)}</div>
      ${hints ? `<div class="box"><div class="label">Try this instead</div><ol>${hints}</ol></div>` : ""}
      <div class="row">
        <button class="primary" data-action="ok">Got it</button>
        <button class="secondary" data-action="ask">Ask a parent to show it</button>
      </div>`;
    showPanel(html, (action, ui) => {
      if (action === "ask") return showAskParent(ui, "guided");
      if (action === "ok") closePanel(ui);
    });
  }

  // ---- Ask a parent ----

  function showAskParent(ui, kind) {
    let minutes = 30;
    const card = ui.shadow.querySelector(".card");
    card.innerHTML = `
      <div class="title"><span class="dot"></span>Ask a parent</div>
      <div class="reason">${
        kind === "guided"
          ? `Ask to use ${escapeHTML(host)} without homework checks for a while.`
          : `Ask to use ${escapeHTML(host)} for a while.`
      } Your parent sees your reason in the Guidance app.</div>
      <textarea maxlength="300" placeholder="Why do you need it? e.g. My teacher said we can use AI to check our citations."></textarea>
      <div class="lengths">
        <button data-action="len" data-min="15" aria-pressed="false">15 min</button>
        <button data-action="len" data-min="30" aria-pressed="true">30 min</button>
        <button data-action="len" data-min="60" aria-pressed="false">1 hour</button>
      </div>
      <div class="row">
        <button class="primary" data-action="send">Send request</button>
        <button class="secondary" data-action="cancel">Cancel</button>
      </div>
      <div class="note" hidden></div>`;
    const note = card.querySelector(".note");
    const textarea = card.querySelector("textarea");
    textarea.focus();

    ui.shadow.addEventListener("click", async (e) => {
      const button = e.target.closest && e.target.closest("button");
      if (!button) return;
      const action = button.dataset.action;
      if (action === "len") {
        minutes = Number(button.dataset.min);
        card.querySelectorAll(".lengths button").forEach((b) => b.setAttribute("aria-pressed", String(b === button)));
      } else if (action === "cancel") {
        closePanel(ui);
      } else if (action === "send") {
        const reason = textarea.value.trim();
        if (reason.length < 3) {
          note.hidden = false;
          note.textContent = "Tell your parent why you need it.";
          return;
        }
        button.disabled = true;
        const result = await browser.runtime
          .sendMessage({ type: "request", domain: host, kind, reason, minutes })
          .catch((err) => ({ error: String(err) }));
        if (!result || result.error) {
          button.disabled = false;
          note.hidden = false;
          note.textContent = (result && result.error) || "Couldn't send the request.";
          return;
        }
        waitForDecision(ui, result.id);
      }
    });
  }

  function waitForDecision(ui, requestId) {
    const card = ui.shadow.querySelector(".card");
    card.innerHTML = `
      <div class="title"><span class="dot"></span>Request sent</div>
      <div class="reason">Waiting for your parent to answer in the Guidance app. You can keep this tab open.</div>
      <div class="row"><button class="secondary" data-action="close">Close</button></div>`;
    ui.shadow.querySelector("button").addEventListener("click", () => closePanel(ui));

    const timer = setInterval(async () => {
      const request = await browser.runtime.sendMessage({ type: "request-status", id: requestId }).catch(() => null);
      if (!request || request.error || request.status === "pending") return;
      clearInterval(timer);
      if (request.status === "approved") {
        revealAllHidden();
        closePanel(ui);
        const until = new Date(request.until).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
        showToast(`Approved until ${until}. Homework checks are off on this site until then.`, 5000);
      } else {
        card.innerHTML = `
          <div class="title"><span class="dot"></span>Not this time</div>
          <div class="reason">Your parent said no for now. You can still ask the AI for hints and explanations.</div>
          <div class="row"><button class="secondary">OK</button></div>`;
        card.querySelector("button").addEventListener("click", () => closePanel(ui));
      }
    }, 4000);
    // Stop polling after 30 minutes; the request stays in the parent's app.
    setTimeout(() => clearInterval(timer), 30 * 60 * 1000);
  }
})();
