# Update: Guidance is now category-based AI controls

This explains what changed from the earlier version (the in-app chatbot plus Family Controls) and why.

## What changed and why

**Before:** Guidance had its own AI chatbot, basically a wrapper around OpenAI. Parents picked specific apps to block with Apple's Family Controls, which needs a **paid** Apple Developer account.

**Now:** Guidance doesn't have its own AI. It's a **parent control layer over the AI kids already use**, modeled on school web filters like **Linewize**:

- AI sites are grouped into **categories**: Chatbots (LLMs), Essay & writing AI, AI humanizers, Math solvers, Homework answer sites, AI companions, Image & video AI, and Learning-focused AI.
- Parents set each category to **Allow / Guided / Block** for each kid, like a teacher flipping "AI on/off" for a class.
- There's one **Turn off all AI** switch, plus **schedules** (School nights, Bedtime, custom).
- **Guided** chatbots (ChatGPT, Claude, Gemini, …) get each prompt checked: homework offloading is stopped and turned into a learning prompt, and the parent's instructions ride along on allowed prompts.
- The catalog lives on the server, so **new AI sites get added once and every family is covered**. That's what makes it scale.

It all runs on a **free Apple account**. Enforcement is a Safari Web Extension instead of Family Controls.

## Added since: hidden answers, safety alerts, Ask a parent

- **Hide finished answers.** On Guided chatbots, if the AI answers a schoolwork prompt with a finished essay or worked-out homework, Guidance blurs it and shows hints instead. Answers to schoolwork prompts stay blurred while they load, so they can't be read first. *(Home → Rules for LLMs (Chatbots) → Hide finished answers)*
- **Safety alerts (always on).** When a kid asks any AI site they can use about self-harm, vaping, drugs/alcohol, sexual content, weapons, eating disorders, dangerous challenges, or getting around parental controls, the parent gets an alert in Activity with the kid's message. **Nothing is blocked, and the kid sees nothing different.** The check is passive: it never pauses or changes what the kid sends. Self-harm alerts are marked urgent and include 988 guidance for the parent. *(Home → Safety alerts lists the topics)*
- **Rules apply live.** Open pages re-check the rules every 15 seconds. A parent's change reaches an open tab without a reload, and a blocked page reopens the site by itself when it's allowed again.
- **Ask a parent.** From the blocked page, or when a prompt or answer is stopped, the kid can ask for access with a reason and a length (15/30/60 min). The parent approves (choosing the length) or says "Not now" in Activity. Approval opens just that site, beats every other rule, and ends on its own. The Activity tab shows a badge for pending requests and new alerts.

## Demo accounts

Signing out no longer loses your family: sign back in from the welcome screen (**Sign in** tab). These are **made-up demo accounts** for the competition build, not real Gmail logins. All four use the same password.

| Email | Password | Opens |
|---|---|---|
| MarvesPaztanes@gmail.com | `guidance123` | The original family (kid **Jalen the son??**, already paired on the iPhone 17 simulator) |
| JalenPaztanes@gmail.com | `guidance123` | Its own family, starts empty |
| MiguelPaztanes@gmail.com | `guidance123` | Its own family, starts empty |
| AlaniPaztanes@gmail.com | `guidance123` | Its own family, starts empty |

- The server creates these on startup (`Backend/functions/src/accounts.ts`). Emails aren't case-sensitive. Set `DEMO_PASSWORD` in `.env` to change the password.
- "New family" still works for anyone without an account; that family can't be signed back into after signing out.

## Kid profiles and "All kids"

- **Kid profiles:** kids don't have accounts. A profile is a name plus a pairing code. Add one with **＋** on the kid bar or in Setup. Tap a kid in Setup to rename them, see their code and phone status, follow the phone setup steps, or remove them.
- **All kids:** the chip bar at the top of Rules, Schedules and Activity has **All kids** (when there are two or more) and each kid.
  - With one kid selected, changes apply only to them.
  - With **All kids**, every change (AI off, categories, homework rules, site exceptions, schedules) applies to every kid.
  - If the kids' settings differ, that control shows **Mixed**; choosing a value sets it for all.
  - Schedules added under All kids are shared (same schedule on every kid). Ones only some kids have are marked "Only Jalen".
  - Activity under All kids merges everyone's requests, alerts and events, labeled with each kid's name.
- **Your name (Guardian):** the parent's name is asked on the New family screen. You can also set it from the "What should <kid> call you?" card on Rules (shown until a name is saved) or in **Setup → Your name**. Kids see it as the Guardian in the extension.
- **Phone setup steps:** the numbered steps (turn on the extension, pair it, Screen Time) are on the Setup screen and on each kid's profile, under their pairing code.

## What the kid sees

Screenshots of every screen(light mode unfortunately): [Docs/pages](Docs/pages/README.md).

- **Blocked page:** a plain, browser-style page (not a card), centered on the screen:
  - "**quillbot.com is blocked by your family's AI rules**", then a gray reason line: "All AI is off right now.", "<Schedule> is on right now.", "Your parent blocked this site.", or "<Category> is off."
  - Plain **Ask for permission** and **Go back** buttons. Ask for permission opens a reason box, a 15 min / 30 min / 1 hour picker and **Send**, then shows "Asked. Waiting for your parent…". When the parent approves (or unblocks the site), the page opens the site by itself.
- **Extension popup** (Safari page menu → Guidance):
  - **Guardian: <parent's name>** with a status dot: green when the rules are fresh, orange when it's running on saved rules because the server can't be reached.
  - **Last update** (how long ago the rules refreshed), and a red **Pair with a different code** button.
  - The popup refreshes the rules by itself when it opens, so there's no refresh button.
  - "Guidance can't see websites yet" appears only when Guidance hasn't run on any website for 24 hours (Safari's own permission check isn't reliable).
- **Guided chatbots:** a "Try it yourself first" panel when a prompt is stopped, and a blurred answer with hints when an answer is hidden. Both have an **Ask a parent** option.

## What was removed

| Removed | Why |
|---|---|
| In-app assistant (`AssistantView`, `ChatBubbleView`, `AIService`, `ChatMessage`) and backend `/chat`, `chat.ts`, `promptBuilder.ts`, `policy.ts` | Guidance no longer runs its own chatbot |
| Learning/Standard/Restricted modes, daily minute limits (`AIMode`, `ParentalPolicy`, `DailyUsage`, `UsageTracker`, `PolicyStore`) | Replaced by per-category rules, schedules and homework rules |
| Family Controls app code (`FamilyControlsManager`, `ShieldManager`, `AppGroupStore`, `AISelectionView`, `AuthorizationView`) | Needs a paid account; replaced by the Safari extension |
| Old screens (`AppRouter`, `AppEnvironment`, `ParentDashboardView`, `ChildHomeView`, `ParentSettingsView`, …) | Replaced by the new parent console |
| Video-recording fake data (`-recordingDemo`, seeded usage, scripted replies) | Everything is real now |

All of it is still in git history. The Family Controls **extensions** (`Extensions/GuideAIShield*`, `GuideAIDeviceActivityMonitor`) are kept for the paid-account roadmap.

## New architecture

```
Parent app (iOS, Face ID) ──PUT policy──► Guidance server ◄──GET policy + catalog── Safari extension (kid's phone)
                          ◄─kids/activity─  Backend/functions  ──prompt checks──►     blocks sites, guides prompts
```

| Piece | Files |
|---|---|
| Server | `Backend/functions/src/app.ts` (routes), `catalog.ts` + `catalog.json` (categories), `classifier.ts` (homework-offloading check), `store.ts` (JSON storage), `validation.ts` (schemas) |
| Rules engine | `Extensions/GuidanceSafari/Resources/shared/resolver.js`, used by the extension and tested by the server tests. Swift mirror: `GuideAI/Models/PolicyResolver.swift` |
| Safari extension | `Extensions/GuidanceSafari/Resources/`: `background.js` (sync + blocking rules), `content/guard.js` (blocked-site backup + prompt checks), `content/adapters.js` (chatbot selectors), `blocked.html`, `popup.html` (pairing + Guardian status). Safari on iOS shows a blank tab for a `declarativeNetRequest` redirect to an extension page, so `guard.js` sends blocked pages to `blocked.html`, and the DNR rules block everything a blocked site loads or embeds |
| Parent app | `GuideAI/App/FamilyStore.swift` (state), `RootView.swift`. Screens in `GuideAI/Features/`: `Rules/`, `Schedules/`, `Activity/`, `Setup/`, `Onboarding/WelcomeView`, `Shared/LockView` |

More detail: [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

## The category catalog

`Backend/functions/catalog.json`. Each category has an id, a name, a description, an SF Symbol icon, `supportsGuided`, a `defaultState` and `domains`.

**To add a site:** add its domain to the right category and **bump `version`**. Phones pull the new catalog on their next sync (about a minute). Subdomains are covered automatically (`quillbot.com` also covers `www.quillbot.com`). The server refuses to start if a domain is listed in two categories.

**To add a category:** add an entry and bump `version`. It shows up in the app automatically. Set `supportsGuided: true` only for chatbots that `content/adapters.js` can handle.

Parents can also:
- add **site exceptions** (always allow / always block one site, even one outside the catalog)
- **report a missing site** from the app. Reports land in the server's `suggestions` list for someone to review and add.

## How rules are decided

From strongest to weakest: **approved "Ask a parent" request → Turn off all AI → site exception → active schedule → category setting.**

Examples:
- Chatbots = Guided, plus an exception "claude.ai → Always block" → ChatGPT is guided, Claude is blocked.
- Math = Allow, plus a "School nights 4–9 PM: Math = Block" schedule → math solvers are blocked from 4–9 PM on Sun–Thu, and allowed otherwise.
- "Bedtime 9:30 PM–7 AM: Turn off all AI" → every AI site is blocked overnight, including Allowed ones and exceptions.
- Two schedules at once, one setting Math to Allow and one to Block → Block wins.

## Setup and run

1. **Server:** `cd Backend/functions && npm install && npm run build && npm start`. An OpenAI key is optional (`.env.example`). Without one, the built-in rules handle the prompt checks.
2. **App:** open `GuideAI.xcodeproj`, choose the **GuideAI** scheme, and Run. **Sign in** with a demo account (see the table above), or create a **New family**. On an iPhone, enter your Mac's Wi-Fi address under Server address first.
3. **Kid's phone:** turn on the Guidance extension in Settings → Apps → Safari → Extensions (All Websites → Allow). Pair it from Safari's page menu with the kid's code: in the app, Setup → tap the kid.
4. **Screen Time:** set a Screen Time passcode, put 1-minute App Limits on the native AI apps and other browsers, and block deleting apps.

Step by step: [Docs/SETUP.md](Docs/SETUP.md).

## Demo script

1. The parent sets Essay & writing AI to **Block** and Chatbots to **Guided**.
2. The kid opens `quillbot.com` → the Guidance blocked page appears.
3. The kid asks ChatGPT "write my 5 paragraph essay on the Civil War" → the prompt is stopped and a learning prompt is offered.
4. The parent taps **Turn off all AI** → chatgpt.com is blocked too.
5. **Activity** shows all of it.

Full script with narration: [Docs/DEMO.md](Docs/DEMO.md).

## Known limits

- **Safari only.** Native AI apps and other browsers are closed off with Screen Time. A kid with the Screen Time passcode could undo that.
- **The extension can be turned off** in Settings. The parent's Activity tab warns when the phone hasn't checked in for a day, but it can't stop it.
- **Chatbot page changes** can break prompt checks until the selectors in `content/adapters.js` are updated. Blocking whole categories doesn't depend on page layout.
- **Demo-grade server:** JSON file storage, a bearer token per family and per device, and made-up demo accounts that share one password. There's no real account system or HTTPS setup.
- **After installing a new build, quit and reopen Safari once** on the kid's phone. Safari keeps running the old extension code until then.
- **The extension needs All Websites → Allow.** Per-site or "Allow for One Day" permission runs out, and reinstalling can reset it.
- **The extension is paired per device.** With several simulators, check you're testing on the one you paired (in our setup: iPhone 17 = kid, iPhone 18 Pro = parent).

## Roadmap

1. Paid Apple Developer account → Family Controls to block native apps and lock settings (the old extensions are still in the repo)
2. A real database (Firebase or Postgres) and hosting
3. A parent app on the parent's own phone (the server already supports this; it needs accounts)
4. Teacher/school mode, like Linewize Classwize: class rules during school hours, with locked rules

## Status checklist

| Step | Status |
|---|---|
| Catalog, rules engine (AI off, exceptions, schedules incl. overnight), blocking extension | ✅ Built. ✅ Rules engine covered by server tests. ✅ Blocking checked in Safari in the simulator (not yet on a real iPhone) |
| Live rule updates | ✅ Checked in the simulator both ways without reloading: unblocking reopened the site, blocking switched the open tab to the blocked page (~15 s) |
| Blocked page and popup redesign, Guardian name | ✅ Blocked page checked in the simulator. ✅ Guardian name sent to the extension (API tested). ⚠️ Popup not screenshotted (opening it needs a tap) |
| Parent console: categories, AI-off switch, exceptions, report a site | ✅ Built and compiles. ✅ Welcome screen checked in the Simulator. ⚠️ Other screens not yet clicked through |
| Schedules (presets, editor, "on now") | ✅ Built. ✅ Swift and JS schedule logic tested |
| Guided prompt checks on ChatGPT (plus Claude, Gemini, generic) | ✅ Server check tested (patterns, AI judge, fallback). ⚠️ The in-page interception hasn't been tried against the live sites yet; selectors may need tuning |
| Activity and heartbeat | ✅ API tested end to end. ✅ Guided prompt events from your simulator tests reached the server |
| Hide finished answers | ✅ Server rules and AI-judge fallback tested. ⚠️ Blurring on the live chatbot pages not yet tried |
| Safety alerts | ✅ 8 topics with pattern tests (including false-positive checks), moderation fallback, API tested. ⚠️ Not yet seen in the app with a real alert |
| Ask a parent | ✅ Request → approve → temporary allow → expiry tested in the API and rules engine. ⚠️ Blocked-page and app flow not yet clicked through |
| Demo accounts | ✅ Sign-in, seeding (Marves keeps the existing family) and wrong-password rejection tested; seeded on the real server data |
| Kid profiles and All kids | ✅ Builds; rename tested in the API. ⚠️ All kids editing not yet clicked through in the app |
| Docs (README, SETUP, DEMO, ARCHITECTURE, TROUBLESHOOTING, this file) | ✅ |

Tests: `npm test` in `Backend/functions` (84 passing). The iOS unit tests in `GuideAITests` (10 passing).
