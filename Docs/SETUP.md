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

1. In the toolbar, choose the **GuideAI** scheme. It builds the app plus the Guidance Safari extension, and is signed with the free Personal Team.
2. Choose your iPhone or a simulator → **Run**.
3. On iPhone, if the first launch is blocked: **Settings → General → VPN & Device Management → Developer App → Trust**, then Run again.

> On your own Apple account, set **Signing & Capabilities → Team** for the GuideAI and GuidanceSafari targets. If the bundle ID is taken, change `com.cac.guideai` (and the extension's `com.cac.guideai.Safari`) to something unique. The Simulator needs no signing.

If the project ever looks broken, regenerate it (this adds new source files automatically):

```bash
python3 Scripts/generate_xcodeproj.py
```

## 3. Sign in or create a family (parent)

**Demo accounts:** on the welcome screen, choose **Sign in** and use one of the made-up accounts with password `guidance123`: MarvesPaztanes@gmail.com (the original family), JalenPaztanes@gmail.com, MiguelPaztanes@gmail.com or AlaniPaztanes@gmail.com. Details are in `UPDATE_README.md`.

Or choose **New family**:

1. Open Guidance, type your kid's name → **Create family**.
2. **On an iPhone:** before running, set your Mac's Wi-Fi address in Xcode: **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables**, add `GUIDEAI_API_BASE_URL` = e.g. `http://192.168.1.10:8080` (find it with `ipconfig getifaddr en0`). After signing in you can also change it in **Setup → Server**. The Simulator needs nothing.
3. The **Home** tab shows every AI category, with its apps in a row underneath. Tap an app for who it's for, its own rule, and custom instructions. Defaults: Chatbots = Guided, Essay / Humanizers / Math / Homework / Companions = Block, Image and Learning-focused AI = Allow.

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
| Home → Essay & writing AI → **Allow**, wait about 15 seconds (an open blocked page reopens the site by itself) | Site loads |
| On chatgpt.com, send "write my 5 paragraph essay on the Civil War" | Prompt is stopped; "Ask this instead" offers an outline prompt |
| Send "Explain what caused the Civil War" | Goes through with "(Parent rules from Guidance: …)" attached |
| Home → **Turn off all AI** | chatgpt.com and every other AI site show the blocked page |
| Schedules → + → Bedtime, set it to start a few minutes from now | AI is blocked when it starts |
| Home → Rules for LLMs (Chatbots) → turn **Stop homework offloading** off (leave **Hide finished answers** on). On chatgpt.com, send "write a 5 paragraph essay on the Civil War for my class" | ChatGPT writes it, but the answer stays blurred and a panel shows hints instead |
| Send "how do i hide a vape from my parents" | Goes through normally; a Vaping alert appears in the app's Activity tab (badge on the tab) |
| On the blocked quillbot page, tap **Ask for permission**, give a reason, send | Request appears in Activity → **Approve** → the page opens quillbot within a few seconds |
| Activity tab | Shows requests, safety alerts, blocked sites, stopped prompts, hidden answers, last check-in |

### Check rule delivery and recovery

Install matching updated versions of the **parent app, backend, and Safari extension** before testing. An older extension can download rules but cannot confirm installation, so the parent continues to see **Saved · waiting for phone**.

1. **Save while the kid's phone is offline.** Put only the kid's phone in Airplane Mode, then change a category on the online parent phone. Expect **Saving rules…**, then **Saved · waiting for phone**. It must not say Applied merely because the save succeeded.
2. **Confirm installation.** Reconnect the kid's phone and open Safari. After the next sync (normally about 15 seconds with a page open), the parent should show **Applied on [kid]'s phone**. Open the affected website and check that the changed rule works. The status confirms that Safari installed the current version; website permissions and actual site behavior still need this check. It does not cover native AI apps.
3. **Recover an unsaved edit after restart.** Stop the backend, change a rule, and expect **Waiting to save** with **Retry**. Close and reopen the parent app while the server is still stopped: the edit must remain visible and pending. Restart the backend; automatic retries back off from 2 seconds to a maximum of 30 seconds. Expect Saved, then Applied after Safari syncs. Pending edits are kept for their original family/server, so reconnect to the same account and address.
4. **Keep the final rapid edit.** With the server stopped, change the same setting several times and finish on a known value. Restart the server and verify that the final value is saved and reaches Safari. Retrying an edit uses its original change identifier, so a lost response does not create another revision or undo a newer confirmed save.
5. **Reset confirmation when re-pairing.** Pair the kid again with the same code. The earlier Applied confirmation must clear; it returns only after the newly paired extension installs and acknowledges the current rules.

## How rules are decided

From strongest to weakest:

1. **Turn off all AI** (or a schedule with "Turn off all AI") → every AI site is blocked
2. **Site exception** (Always allow / Always block for one site)
3. **Active schedule** (when schedules overlap, the stricter setting wins)
4. **Category setting**

Sites not in the catalog are untouched unless you add an exception for them.

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
