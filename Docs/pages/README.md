# Guidance — every screen

Screenshots from the iOS Simulator (iPhone 18 Pro for the parent app, iPhone 17 for the kid's Safari), taken with real demo data.

> To retake them: Debug builds accept launch arguments that open a screen directly, so no tapping is needed. See `GuideAI/App/DebugScreens.swift` (`-unlocked`, `-tab <rules|schedules|activity|setup>`, `-screen <name>`).

## Parent app

| | |
|---|---|
| **Sign in** — demo accounts and password sign-in<br><img src="01-sign-in.png" width="260"> | **New family** — your name and your first kid<br><img src="02-new-family.png" width="260"> |
| **Lock screen** — what a kid sees if they open the app<br><img src="03-lock-screen.png" width="260"> | **Rules** — kid selector (All kids / each kid), AI-off switch, categories<br><img src="04-rules.png" width="260"> |
| **Category detail** — setting plus per-site exceptions<br><img src="05-category-detail.png" width="260"> | **Homework rules** — offloading check, hide finished answers, instructions<br><img src="06-homework-rules.png" width="260"> |
| **Safety alerts** — the 8 always-on topics<br><img src="07-safety-alerts.png" width="260"> | **Site exceptions** — always allow / always block one site<br><img src="08-site-exceptions.png" width="260"> |
| **Schedules** — school nights, bedtime, custom<br><img src="09-schedules.png" width="260"> | **Schedule editor** — days, times, what changes<br><img src="10-schedule-editor.png" width="260"> |
| **Activity** — requests, safety alerts, protection status, history<br><img src="11-activity.png" width="260"> | **Setup** — kids, phone setup steps, your name, server<br><img src="12-setup.png" width="260"> |
| **Kid profile** — name, pairing code, phone setup steps<br><img src="13-kid-profile.png" width="260"> | |

## Kid's phone (Safari)

| | |
|---|---|
| **Blocked page** — reason, Ask for permission, Go back<br><img src="14-safari-blocked-page.png" width="260"> | **Extension popup** — not captured: iOS won't open the popup from outside Safari, and it needs a tap on the page menu. It shows "Guardian: <name>" with a status dot, Last update, and Pair with a different code. |

Not shown: the "Try it yourself first" and hidden-answer panels on chatbots (they need a live chatbot conversation) and the Ask-for-permission form (needs a tap).
