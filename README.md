# Guidance

**Guidance** lets parents decide **how** their kids use AI, instead of choosing between "anything goes" and "AI banned." Parents control AI **by category**, the way school filters like Linewize do: Chatbots, Essay & writing AI, Math solvers, Homework answer sites, AI humanizers and more. Each one is set to **Allow**, **Guided** or **Block**. There's also one **Turn off all AI** switch, plus schedules.

On **Guided** chatbots (ChatGPT, Claude, Gemini and others), Guidance checks each prompt before it's sent. Prompts that try to offload homework ("write my essay", "solve these for me") are stopped, and the kid is offered a learning-style prompt instead. Allowed prompts carry the parent's own instructions to the AI.

Built for the **Congressional App Challenge**. It runs on a **free Apple account**: no paid Developer Program needed.

> Coming from the earlier version with the built-in chatbot? Read **[UPDATE_README.md](UPDATE_README.md)**.

## How it works

```
Parent app (Face ID) ──► Guidance server ◄── Safari extension on the kid's phone
  categories, schedules,     rules, catalog,      • blocks AI sites in blocked categories
  AI-off switch, exceptions  prompt checks,       • checks prompts on Guided chatbots
                             activity             • reports what it blocked
```

| Piece | Where | What it does |
|---|---|---|
| Parent console (iOS app) | `GuideAI/` | Kids, category settings, schedules, site exceptions, homework rules, activity, pairing |
| Safari Web Extension | `Extensions/GuidanceSafari/` | Enforces the rules in Safari: blocks sites, checks Guided prompts |
| Server | `Backend/functions/` | Stores families and rules, serves the AI-site catalog, judges prompts, collects activity |
| AI-site catalog | `Backend/functions/catalog.json` | Categories and their domains. Add a site here and every phone picks it up. |

Native AI apps (the ChatGPT app and others) and other browsers are closed off with iOS **Screen Time**, which is free and set up once in Settings. That keeps AI use in Safari, where Guidance applies the rules.

## Quick start

```bash
# 1. Server
cd Backend/functions
npm install
npm run build && npm start        # http://localhost:8080 (OpenAI key optional, see .env.example)

# 2. App (from the repo root)
open GuideAI.xcodeproj            # choose the "GuideAI" scheme → Run
```

Full steps, including the iPhone and Safari extension setup: **[Docs/SETUP.md](Docs/SETUP.md)**. Screenshots of every screen: **[Docs/pages](Docs/pages/README.md)**. Video script: **[Docs/DEMO.md](Docs/DEMO.md)**. Problems: **[Docs/TROUBLESHOOTING.md](Docs/TROUBLESHOOTING.md)**.

## Tests

```bash
cd Backend/functions && npm test                 # rules, schedules, catalog, prompt checks, API
xcodebuild test -project GuideAI.xcodeproj -scheme GuideAI \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

## Technology

| Layer | Stack |
|---|---|
| iOS app | Swift, SwiftUI, async/await, LocalAuthentication |
| Enforcement | Safari Web Extension (Manifest V3, `declarativeNetRequest`, content scripts) |
| Server | Node.js, TypeScript, Express, zod; optional OpenAI Responses API for prompt judging |

## Known limits

- Rules apply in **Safari**. Native AI apps and other browsers have to be blocked with Screen Time, and a kid who knows the Screen Time passcode could undo that.
- A kid could turn the extension off in Settings. The parent's Activity tab shows when the phone last checked in.
- Prompt checks rely on each chatbot's page layout. When a site redesigns, its selectors in `content/adapters.js` may need updating.
- The demo server stores data in a JSON file and has no accounts beyond a family token.

## Roadmap

- Apple **Family Controls** (paid Developer Program) to block native apps and lock settings
- Cloud database and a parent app on the parent's own phone
- Teacher/school mode, like Linewize Classwize
- "Ask a parent" requests from the blocked page

Prototype for Congressional App Challenge demonstration. Not legal advice regarding COPPA or other child-privacy regulations.
