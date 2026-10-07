# GuideAI — Congressional App Challenge Demo (1–3 min)

Record on a **physical iPhone** with external AI apps installed (e.g. ChatGPT, Gemini, Claude) and the backend running if showing live AI.

## Script

| Time | Action |
|------|--------|
| **0:00** | **Problem:** Kids have powerful AI everywhere; parents often only choose allow or ban. |
| **0:15** | Open GuideAI → Parent Dashboard (after onboarding + authorization). |
| **0:25** | **Choose Apps & Websites** → Apple picker → select AI apps and sites. |
| **0:40** | Parent Settings → **Block External AI** on. |
| **0:50** | **Learning Mode**, 45-minute limit, optional custom instruction (e.g. “Attempt math before full explanations”). |
| **1:00** | Switch to Child Mode → try opening a blocked AI app or site. |
| **1:10** | Show **real** system shield: “External AI Restricted” / use approved assistant. |
| **1:20** | Open GuideAI → **Ask GuideAI**. |
| **1:25** | Ask a homework-style question (e.g. “Write my essay on the Civil War” or a math word problem). |
| **1:40** | Highlight **Learning Mode**: hints, questions, outline—not instant full submission. |
| **2:00** | Parent Dashboard: usage minutes, mode, external AI status. |
| **2:20** | One sentence architecture: Apple shields parent-selected apps; GuideAI backend applies policy to the approved assistant; future Family Sharing pairing. |
| **2:40** | Close: *“We aren’t removing AI from education—we’re giving families control over how it participates.”* |

## Pre-demo checklist

- [ ] All targets signed with same team; Family Controls + App Group enabled
- [ ] Authorization approved on device
- [ ] At least one app and one website selected
- [ ] Block External AI enabled
- [ ] Backend reachable from phone (`GUIDEAI_API_BASE_URL` = Mac LAN IP if needed)
- [ ] Daily limit not already exhausted (or reset in Parent Settings)

## Honest limitations to mention if asked

- Restricts **selected** services, not every AI on the Internet
- Beta uses **individual** on-device authorization, not full parent/child remote pairing
- No large-scale URL filter / Network Extension in this version
