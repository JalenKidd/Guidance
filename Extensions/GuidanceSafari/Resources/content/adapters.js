/*
 * Per-site hooks for Guided chatbots: where the prompt box and send button are.
 * These sites change their markup often. When guidance stops catching prompts on
 * a site, update the selectors here first (each list is tried in order).
 */
(function (root) {
  "use strict";

  function first(selectors) {
    for (const s of selectors) {
      const el = document.querySelector(s);
      if (el) return el;
    }
    return null;
  }

  function adapter(id, hosts, inputSelectors, sendSelectors, responseSelectors) {
    return {
      id,
      hosts,
      input: () => first(inputSelectors),
      sendButton: () => first(sendSelectors),
      /** The AI's answers on the page, oldest first. Empty when we don't know how to find them. */
      responses: () => {
        for (const s of responseSelectors || []) {
          const found = document.querySelectorAll(s);
          if (found.length) return Array.from(found);
        }
        return [];
      },
    };
  }

  const ADAPTERS = [
    adapter(
      "chatgpt",
      ["chatgpt.com", "chat.openai.com"],
      ["#prompt-textarea", "form [contenteditable='true']", "form textarea"],
      ["[data-testid='send-button']", "#composer-submit-button", "form button[aria-label*='Send' i]"],
      ["[data-message-author-role='assistant']"]
    ),
    adapter(
      "claude",
      ["claude.ai"],
      ["div.ProseMirror[contenteditable='true']", "fieldset [contenteditable='true']", "[contenteditable='true'][role='textbox']"],
      ["button[aria-label='Send message']", "button[aria-label*='Send' i]"],
      ["[data-is-streaming] .font-claude-response", "[data-is-streaming] .font-claude-message", "[data-is-streaming]"]
    ),
    adapter(
      "gemini",
      ["gemini.google.com"],
      ["rich-textarea .ql-editor", "div.ql-editor[contenteditable='true']", "[contenteditable='true'][role='textbox']"],
      ["button.send-button", "button[aria-label*='Send' i]"],
      ["model-response message-content", "model-response"]
    ),
  ];

  /** Best effort for other Guided chatbots (Copilot, Perplexity, …). */
  const GENERIC = adapter(
    "generic",
    [],
    ["textarea:not([readonly])", "[contenteditable='true'][role='textbox']", "[contenteditable='true']"],
    ["button[aria-label*='Send' i]", "button[aria-label*='Submit' i]", "button[type='submit']"]
  );

  function forHost(host) {
    for (const a of ADAPTERS) {
      if (a.hosts.some((h) => host === h || host.endsWith("." + h))) return a;
    }
    return GENERIC;
  }

  function getText(input) {
    if (!input) return "";
    return "value" in input && typeof input.value === "string" ? input.value : input.innerText || "";
  }

  /** Replace the prompt text in a way React / ProseMirror / Quill editors notice. */
  function setText(input, text) {
    input.focus();
    if (input instanceof HTMLTextAreaElement || input instanceof HTMLInputElement) {
      const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(input), "value").set;
      setter.call(input, text);
      input.dispatchEvent(new Event("input", { bubbles: true }));
      return;
    }
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(input);
    selection.removeAllRanges();
    selection.addRange(range);
    if (!document.execCommand("insertText", false, text)) {
      input.textContent = text;
      input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
    }
  }

  root.GuidanceAdapters = { forHost, getText, setText };
})(globalThis);
