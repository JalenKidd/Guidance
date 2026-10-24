# Guidance Architecture

## Idea

Parents control AI **by category** instead of one site at a time, the way school web filters such as Linewize do. Guidance owns a catalog of AI sites grouped into categories. Parents set each category to Allow, Guided or Block for each kid, and the kid's phone enforces it. New AI sites get added to the catalog once and every family is covered.

## Components

```
┌─────────────────────┐   PUT policy    ┌──────────────────────────┐   GET policy / catalog   ┌──────────────────────────┐
│ Parent app (iOS)    │ ──────────────► │ Guidance server          │ ◄─────────────────────── │ Safari extension (kid)   │
│ GuideAI/            │ ◄────────────── │ Backend/functions        │ ──────────────────────► │ Extensions/GuidanceSafari│
│ FamilyStore,        │  kids, activity │ app.ts  catalog.json     │  POST /device/check      │ background.js            │
│ PolicyResolver      │                 │ classifier.ts store.ts   │  POST /device/events     │ shared/resolver.js       │
└─────────────────────┘                 └──────────────────────────┘                          │ content/guard.js         │
                                                                                               └──────────────────────────┘
```

### Server (`Backend/functions/src`)

| File | Role |
|---|---|
| `app.ts` | Express routes. Parent routes use the family's bearer token; device routes use the token issued at pairing. |
| `catalog.ts` + `../catalog.json` | Versioned category catalog. Validated at startup: no duplicate ids or domains. |
| `classifier.ts` | Homework-offloading check. Fast regex rules first; an optional OpenAI judge for the rest (4 s timeout, fails open). Builds the parent instructions added to allowed prompts. |
| `store.ts` | JSON-file store (families, kids, pairing codes, events, site reports). Replace with a database later. |
| `validation.ts` | zod schemas for every request, including the `KidPolicy` shape. |

### Safety alerts, hidden answers, Ask a parent

- `safety.ts` has eight topics (self-harm, vaping/smoking, drugs/alcohol, sexual content, weapons/violence, eating disorders, dangerous challenges, getting around parental controls). Each is matched by local patterns, plus OpenAI's free moderation endpoint when a key is set. All topics are always on, on every AI site in the catalog the kid can use. Alerts **never** change what the kid sees: outside Guided mode the check listens passively and never delays the send. Self-harm alerts are urgent.
- `checkResponse` in `classifier.ts` decides whether an AI answer on a Guided chatbot hands over finished schoolwork. The local rule: a schoolwork prompt plus a long, paragraph-shaped, third-person answer, or several "final answers". The optional AI judge also writes hints. The extension keeps answers to schoolwork prompts blurred while they stream and are checked.
- "Ask a parent": the kid sends `POST /device/requests` (a reason plus 15/30/60 min) from the blocked page or the chatbot panels. The parent approves in Activity, which adds a `temporaryAllows` entry to the kid's policy. That entry beats every other rule until it expires.

### Policy shape

```ts
KidPolicy {
  masterAIOff: boolean
  categories: { [categoryId]: "allow" | "guided" | "block" }
  siteOverrides: { [domain]: "allow" | "block" }
  schedules: [{ id, name, enabled, days: 0–6 (Sun=0), start: "HH:MM", end: "HH:MM",
                masterAIOff, categories: { [categoryId]: state } }]
  guidedRules: { blockHomeworkOffloading, requireAttemptFirst, hideFinishedAnswers, globalInstructions: string[] }
  safetyAlerts: { [topicId]: boolean }          // missing = on; self_harm always on
  temporaryAllows: [{ domain, until, requestId }] // approved "Ask a parent" requests
}
```

### Resolver (one set of rules, two copies)

`Extensions/GuidanceSafari/Resources/shared/resolver.js` decides a site's state. Precedence: **approved request → AI off → site override → active schedule → category**. Overlapping schedules use the strictest state. Windows with `end < start` run past midnight.

- The extension runs it on the phone's clock, so schedules switch on time even offline.
- The server test suite runs the same file (`src/resolver.test.ts`).
- `GuideAI/Models/PolicyResolver.swift` mirrors it so the app can show what's in effect right now. Keep the two in step.

### Safari extension (`Extensions/GuidanceSafari/Resources`)

- `background.js` syncs the policy and catalog when asked (Safari suspends it, so open pages ask every 15 s) and on its alarm. It rebuilds `declarativeNetRequest` dynamic rules: a `block` rule for everything a blocked domain loads or embeds, and an `allow` rule for exceptions and approvals. (Safari on iOS shows a blank tab for a DNR redirect to an extension page, so the page itself is sent to `blocked.html` by `guard.js`.) It also answers prompt checks and queues events. When the server can't be reached, it keeps the last rules.
- `content/guard.js` runs on every page. It sends blocked pages to `blocked.html` and re-checks the rules every 15 s while the page is open, so changes apply without a reload. On Guided chatbots it intercepts Enter and the send button, asks the server, then either shows the "Try it yourself first" panel or sends the prompt with the parent's instructions attached.
- `content/adapters.js` holds the per-site selectors (ChatGPT, Claude, Gemini, plus a generic fallback).
- `popup.html` handles pairing and status. `blocked.html` is the blocked page, and it logs the event.
- `SafariWebExtensionHandler.swift` is the required native stub.

### iOS app (`GuideAI`)

- `FamilyStore` is the single observable store. It caches kids, policy and catalog in `UserDefaults`, and debounces policy saves (500 ms).
- Tabs: **Rules** (AI-off switch, categories, homework rules, site exceptions), **Schedules**, **Activity**, **Setup** (pairing code, phone checklist, kids, server).
- `LockView` with `ParentAuthenticationService` re-locks when the app goes to the background.

## Data and privacy

- The server stores rules and **events**: blocked site, stopped or guided prompt, hidden answer, the reason, and the time. It does not store AI responses, or prompt text in general.
- **Safety alerts are the exception:** they store the kid's message that triggered them (first 500 characters), so the parent knows what to talk about.
- The parent sees what was blocked or checked, not conversations.
- Prompt text is sent to the server on chatbot sites (Guided or Allowed) to run the checks. AI answers are sent only on Guided sites when "Hide finished answers" is on. With an OpenAI key set, prompts and answers the built-in rules don't flag are sent to OpenAI for judging, and prompts go to OpenAI's moderation endpoint.

## Not used in the free build

`Extensions/GuideAIShield*` and `GuideAIDeviceActivityMonitor` are the Apple Family Controls extensions from the earlier version. They build only in the `GuideAI` scheme, which needs a paid team, and are kept for the roadmap.
