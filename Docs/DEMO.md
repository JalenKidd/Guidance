# Guidance — Video Demo Script

Target length **2:30–2:50** (the Congressional App Challenge limit is 3:00).

## The one idea judges should remember

**Parents shouldn't have to choose between banning AI and letting it do their kid's homework. Guidance lets them control AI by category, like a school filter, and keeps the big chatbots in "learning mode."**

## Before recording

1. Server running (`npm start`). The app and Safari extension are paired (see SETUP).
2. Rules set to the defaults: Chatbots = Guided, Essay & writing AI = Block, AI off = off. No schedule active right now.
3. Screen Time set up so the ChatGPT app is limited (in case judges ask).
4. Safari tabs ready: `quillbot.com` and `chatgpt.com` (signed in, or the logged-out chat page).
5. Do Not Disturb on, clean status bar, portrait, 1080p+.

## Shot list

| Time | On screen | Narration |
|---|---|---|
| 0:00–0:12 | Team / title card | "Hi, we're **[names]**, and we built **Guidance**. AI can answer any homework question in seconds, but an answer isn't the same as learning." |
| 0:12–0:30 | Guidance → Face ID → **Rules** tab, scroll the categories | "Parents shouldn't have to ban AI. Guidance works like the filters schools use: AI is sorted into categories like chatbots, essay writers, math solvers and homework answer sites, and parents choose what each one does." |
| 0:30–0:45 | Set **Essay & writing AI** to Block (already is; tap Allow then Block) | "One tap blocks every essay-writing AI we know about, and as new ones appear, we add them to the catalog for every family." |
| 0:45–1:00 | Safari → `quillbot.com` → Guidance blocked page | "On the kid's phone, the essay tool is simply off, with a clear explanation." |
| 1:00–1:12 | Back to app → **Chatbots** shows **Guided** → open Homework rules | "Chatbots like ChatGPT can stay on in Guided mode. Parents can add their own instructions too." |
| 1:12–1:35 | Safari → chatgpt.com → type "write my 5 paragraph essay on the Civil War" → send → "Try it yourself first" panel | "When a prompt tries to hand off the homework, Guidance stops it before ChatGPT ever sees it, and offers a better question." |
| 1:35–1:50 | Tap **Use this instead** → send → ChatGPT responds with outline help | "The student still gets help, just the kind that keeps them thinking." |
| 1:50–2:05 | App → **Schedules** → show Bedtime and School nights | "Schedules make it automatic: stricter on school nights, no AI at bedtime." |
| 2:05–2:15 | Rules → **Turn off all AI** → Safari → chatgpt.com blocked | "And when a parent needs it, one switch turns off all AI." |
| 2:15–2:30 | **Activity** tab | "Parents see what was blocked and stopped, not their kid's private conversations." |
| 2:30–2:45 | Logo / team | "We built Guidance with SwiftUI, a Safari Web Extension and a TypeScript server. Guidance: not a ban, a better path." |

## What not to claim

- Guidance enforces rules **in Safari**. Native AI apps are blocked with iOS Screen Time, not by Guidance. Don't say Guidance blocks the ChatGPT *app*.
- The catalog covers known AI sites. It isn't every AI site on the internet, but it grows.
- It isn't on the App Store.

## Final checklist

- [ ] Names, app name and purpose are stated
- [ ] Category control, blocked page, guided prompt, schedule, AI-off and Activity are all shown
- [ ] Languages and tools are named
- [ ] No Xcode, debug screens or notifications visible
- [ ] Under 3:00

## If a take goes wrong

Turn **AI off** back off, reset Essay to Block, clear the ChatGPT prompt, and start again from 0:12.
