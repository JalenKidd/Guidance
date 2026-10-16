# Guidance — Final Recording Plan

Target length: **2:35–2:50**. The Congressional App Challenge limit is three minutes, so leave at least ten seconds of safety margin.

## The story judges should remember

**Guidance does not simply ban AI. It redirects students away from answer-generating tools and toward learning-focused help that gives outlines, hints, explanations, and feedback without replacing their thinking.**

That distinction is the project's strongest idea. Keep the video centered on one simple before-and-after story: a parent chooses the rules, a child reaches a restricted AI tool, and Guidance turns that moment into learning.

## Before recording

1. In Xcode, select the internal **GuideAI Demo** scheme. The installed app will be named **Guidance**.
2. Use the connected iPhone 17 Pro Max or the iPhone 17 Pro Max simulator in portrait orientation.
3. Launch once before recording and dismiss any iOS account or notification pop-ups.
4. Before the final take, confirm Learning Mode, a 45-minute limit, and all three protected tools are selected.
5. Turn on Do Not Disturb, use a clean status bar, and record at 1080p or higher.
6. Do not open debug tools, Xcode, or the iOS app picker in the final cut.

The recording build is self-contained: it starts at 18 of 45 minutes with seven approved requests, shows two selected apps and one website, avoids recording-breaking biometric prompts, and generates the learning response offline.

## Exact shot list and narration

Replace the bracketed names before recording. Speak naturally rather than racing through every word.

| Time | What viewers see | Narration |
|---|---|---|
| **0:00–0:12** | Team on camera, or title card with names and the Guidance logo | “Hi, we’re **[participant names]**, and we created **Guidance**. AI can give students answers in seconds—but an answer is not the same as learning.” |
| **0:12–0:26** | Launch Guidance on the Parent overview | “Guidance helps parents redirect children from unrestricted AI tools into guided, age-appropriate learning. It is designed for families with middle- and high-school students.” |
| **0:26–0:43** | Tap **Manage restricted tools**; toggle one tool off and back on, then save | “From one dashboard, a parent chooses which AI apps and websites to restrict. We block specific answer-generating tools instead of broad categories that could also hide useful learning resources.” |
| **0:43–0:58** | Open **Controls**; tap Restricted Mode, then return to Learning Mode; adjust the daily limit once | “Every control is immediate. Parents can choose learning-focused help, standard assistance, or stricter hints-only support, then set a daily limit.” |
| **0:58–1:12** | Open **Activity**; tap a bar and switch from Minutes to Requests | “Parents can see a privacy-first weekly trend—time, guided requests, and protected redirects—without reading the child’s private conversation.” |
| **1:12–1:26** | Tap **Overview**, then **Child**; briefly show the Home, Learn, and Progress tabs | “The child gets a complete, simple learning space. They can ask for help, understand the active rules, and track their own progress.” |
| **1:26–1:42** | On Child Home, tap **Open ChatGPT** | “When a protected answer-generating tool is opened, Guidance pauses access and explains the learning-focused rule in clear language.” |
| **1:42–1:51** | Tap **Get Guided Help** | “Instead of ending with a dead-end block, Guidance offers a better next step.” |
| **1:51–2:10** | Tap **Help me outline a Civil War essay**, then tap Send | “Here, a student asks for help with an essay. Guidance refuses to write a ready-to-submit assignment, but it does not abandon them.” |
| **2:10–2:30** | Hold on the thesis scaffold, evidence plan, and follow-up question | “It provides a possible thesis, evidence to investigate, and a question that puts the thinking back in the student’s hands.” |
| **2:30–2:46** | Show Progress, then end on the Guidance logo or Parent overview | “We built Guidance with SwiftUI, Apple Family Controls, Managed Settings, and a TypeScript policy backend. Guidance turns an AI shortcut into a teachable moment—so students can use AI without losing the learning.” |

## Editing choices that make the video stronger

- Start with the **problem**, not a list of features.
- Keep taps visible and use a subtle zoom or touch indicator; never speed up the key redirect-to-help moment.
- Add only three short on-screen labels: **Parent chooses**, **Guidance redirects**, **Student still learns**.
- Put the technologies on screen while the architecture sentence is spoken: **SwiftUI • FamilyControls • ManagedSettings • TypeScript**.
- Use captions throughout and lower background music beneath every spoken line.
- Show the response long enough to read the refusal, the evidence plan, and the final question.
- End on the one-line distinction: **Not a ban. A better path.**

## What not to claim

- Guidance restricts tools selected by the parent; it does not automatically detect every AI service on the internet.
- The recording build uses seeded activity so every take is consistent. The full target connects the same interface to Family Controls and Managed Settings.
- The current app uses on-device family-control authorization. Full remote parent/child pairing is a future step.
- Do not say the product is already on the App Store.

## Final export checklist

- [ ] Participant names are stated or shown
- [ ] App name is **Guidance** everywhere viewers can see it
- [ ] One clear purpose sentence and target audience are included
- [ ] Languages and development tools are named
- [ ] The complete parent → child → redirect → guided answer flow is visible
- [ ] No notifications, Apple Account dialogs, debug screens, or long loading gaps appear
- [ ] Captions are readable on a phone screen
- [ ] Runtime is under 3:00
- [ ] Audio is clear on both phone speakers and headphones

## Backup plan

Record the app walkthrough as a clean screen capture first, then add voice-over. If a take goes wrong, return to Parent overview, restore Learning Mode and the 45-minute limit, then begin again. Keep one unedited full walkthrough and one final edited export before submitting.
