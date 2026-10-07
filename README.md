# GuideAI

**GuideAI** helps families control **how** children use artificial intelligence—not whether AI exists at all. Parents choose external AI apps and websites to restrict with Apple Screen Time APIs, set learning modes and daily limits, and give children a **controlled in-app assistant** whose behavior is enforced by a secure backend.

Built for the **Congressional App Challenge** as a real development-device beta (not App Store distribution yet).

## Problem

Students can access powerful AI through many apps and websites. Parents often have only two options: unrestricted access or total prohibition—neither supports guided learning.

## Solution

1. Parent configures policy (mode, limits, custom instructions)
2. Parent authorizes Family Controls (individual authorization for this beta)
3. Parent selects external AI apps/sites in Apple’s `FamilyActivityPicker`
4. When blocking is enabled, `ManagedSettings` shields those selections
5. Child uses GuideAI’s assistant; the backend applies Learning / Standard / Restricted behavior
6. Daily approved-AI usage is tracked; limits block further assistant use until the next day

**Important:** This MVP restricts **parent-selected** apps and websites. It does **not** block every AI service on the Internet.

## Architecture

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

```
ParentalPolicy → ShieldManager / UsageTracker / AIService
FamilyActivitySelection → ManagedSettingsStore → iOS shield
Chat → Backend promptBuilder → OpenAI Responses API
```

## Current beta features

- Onboarding with individual Family Controls authorization
- Real `FamilyActivityPicker` and persistent selection (App Group)
- Real `ManagedSettings` shield apply/clear with policy restore on launch
- Custom Shield Configuration + Shield Action extensions
- Parent Dashboard (mode, usage, external AI status)
- Parent Mode gated by Face ID / Touch ID / device passcode
- Child home + chat UI with mode badge and remaining time
- Node/TypeScript backend; API key never in the iOS app
- Daily usage limits with limit-reached UI
- DEBUG demo tools

## Technology stack

| Layer | Stack |
|-------|--------|
| iOS | Swift, SwiftUI, async/await, MVVM-style services |
| Screen Time | FamilyControls, ManagedSettings, ManagedSettingsUI, DeviceActivity, LocalAuthentication |
| Backend | Node.js, TypeScript, Express, OpenAI JavaScript SDK (Responses API) |

## Setup

- **iOS device:** [Docs/SETUP.md](Docs/SETUP.md)
- **Backend:** `Backend/functions` — copy `.env.example` to `.env`, `npm install`, `npm start`
- **Demo script:** [Docs/DEMO.md](Docs/DEMO.md)
- **Issues:** [Docs/TROUBLESHOOTING.md](Docs/TROUBLESHOOTING.md)

Regenerate Xcode project if needed:

```bash
python3 Scripts/generate_xcodeproj.py
```

## Physical device requirements

Family Controls authorization, app/site picking, and shields require a **development-enabled iPhone**. Simulator is suitable for UI and chat-only work.

## Known limitations

- Parent-selected blocking only (no global AI URL filter)
- Individual authorization demo—not full Family Sharing parent/child pairing
- Policy and usage stored locally (Firebase-ready architecture, not required for beta)
- Device Activity monitor scaffolded; AI-free bedtime schedule not required for MVP
- Child conversation text not exposed in parent analytics by default

## Future roadmap

- Family Sharing `.child` authorization and multi-device pairing
- Cloud policy sync (Firebase)
- Temporary “ask parent” approvals and schedules
- Network Extension URL filtering for large-scale web coverage
- Production privacy/consent review for minors

## License / competition

Prototype for Congressional App Challenge demonstration. Not legal advice regarding COPPA or other child-privacy regulations.
