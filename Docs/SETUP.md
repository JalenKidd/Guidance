# Guidance — Setup

Everything here works with a **free Apple account** (Personal Team). Plan on about 15 minutes.

## Prerequisites

- Mac with Xcode (current SDK)
- Node.js **22.9+**
- An iPhone on iOS 17+ for the full experience. The Simulator is fine for the parent app and for testing the extension in Simulator Safari.

## 1. Start the server

```bash
cd Backend/functions
npm install
npm run build
npm start
```

You should see `Guidance backend listening on 0.0.0.0:8080`. Check it with `curl http://localhost:8080/health`.

**Optional AI judge:** copy `.env.example` to `.env` and set `OPENAI_API_KEY` and `OPENAI_MODEL`. Without them, prompt checks use Guidance's built-in homework-offloading rules, which cover the common cases ("write my essay", "solve these for me", "just give me the answer", "humanize this"). With them, prompts the rules don't catch are also judged by the AI.

Data is saved in `Backend/functions/data/store.json` (git-ignored).

## 2. Run the app

```bash
open GuideAI.xcodeproj
```

1. In the toolbar, choose the **GuideAI Demo** scheme. It builds the app plus the Guidance Safari extension, and is signed with the free Personal Team.
2. Choose your iPhone or a simulator → **Run**.
3. On iPhone, if the first launch is blocked: **Settings → General → VPN & Device Management → Developer App → Trust**, then Run again.

> The `GuideAI` scheme is the older Family Controls build, which needs a paid Apple Developer Program team. You don't need it.

If the project ever looks broken, regenerate it (this adds new source files automatically):

```bash
python3 Scripts/generate_xcodeproj.py
```

## 3. Sign in or create a family (parent)

**Demo accounts:** on the welcome screen, choose **Sign in** and use one of the made-up accounts with password `guidance123`: MarvesPaztanes@gmail.com (the original family), JalenPaztanes@gmail.com, MiguelPaztanes@gmail.com or AlaniPaztanes@gmail.com. Tap **Demo accounts** to fill in the email. Details are in `UPDATE_README.md`.

Or choose **New family**:

1. Open Guidance, type your kid's name → **Create family**.
2. **On an iPhone:** open **Server address** first and enter your Mac's Wi-Fi address, e.g. `http://192.168.1.10:8080` (find it with `ipconfig getifaddr en0`). Tap **Test connection**. In the Simulator you can leave it empty.
3. The **Rules** tab shows every AI category. Defaults: Chatbots = Guided, Essay / Humanizers / Math / Homework / Companions = Block, Image and Learning-focused AI = Allow.

The app locks whenever it goes to the background. Unlocking needs Face ID or the passcode, so a kid who opens it sees only "AI is guided on this phone."

## 4. Set up the kid's phone (Safari extension)

Do this on the phone the kid uses. For a demo with one phone, that's the same phone.

1. **Turn on the extension:** Settings → Apps → Safari → Extensions → **Guidance** → on. Under permissions, set **All Websites → Allow**. This matters: with only "Ask" or one-day permissions, sites won't be blocked. The extension popup shows a warning when access is missing.
2. **Pair it:** in Safari, open any website, tap the page menu (left of the address bar) → **Guidance**. Enter the 6-character code from the app's **Setup** tab. If the server isn't on this device, open **Server address** and enter the same address as in step 3.
3. **Close the gaps with Screen Time** (free, built into iOS):
   - Settings → Screen Time → **Lock Screen Time Settings** (set a passcode the kid doesn't know)
   - **App Limits → Add Limit**: pick the ChatGPT, Gemini, Claude and Copilot apps and any browsers other than Safari, set to 1 minute (the shortest iOS allows), and turn on Block at End of Limit
   - **Content & Privacy Restrictions → iTunes & App Store Purchases → Deleting Apps → Don't Allow**

Check it: open `quillbot.com` in Safari. You should get the Guidance blocked page.

## 5. Try the rules

| Try this | Expected |
|---|---|
| Open `quillbot.com` | Blocked page ("Essay & writing AI") |
| Rules → Essay & writing AI → **Allow**, wait about 15 seconds (an open blocked page reopens the site by itself) | Site loads |
| On chatgpt.com, send "write my 5 paragraph essay on the Civil War" | Prompt is stopped; "Ask this instead" offers an outline prompt |
| Send "Explain what caused the Civil War" | Goes through with "(Parent rules from Guidance: …)" attached |
| Rules → **Turn off all AI** | chatgpt.com and every other AI site show the blocked page |
| Schedules → + → Bedtime, set it to start a few minutes from now | AI is blocked when it starts |
| Homework rules → turn **Stop homework offloading** off (leave **Hide finished answers** on). On chatgpt.com, send "write a 5 paragraph essay on the Civil War for my class" | ChatGPT writes it, but the answer stays blurred and a panel shows hints instead |
| Send "how do i hide a vape from my parents" | Goes through normally; a Vaping alert appears in the app's Activity tab (badge on the tab) |
| On the blocked quillbot page, tap **Ask for permission**, give a reason, send | Request appears in Activity → **Approve** → the page opens quillbot within a few seconds |
| Activity tab | Shows requests, safety alerts, blocked sites, stopped prompts, hidden answers, last check-in |

## How rules are decided

From strongest to weakest:

1. **Turn off all AI** (or a schedule with "Turn off all AI") → every AI site is blocked
2. **Site exception** (Always allow / Always block for one site)
3. **Active schedule** (when schedules overlap, the stricter setting wins)
4. **Category setting**

Sites not in the catalog are untouched unless you add an exception for them.

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
