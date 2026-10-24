# Troubleshooting

## App: "Can't reach the Guidance server"

- Is the server running? `npm start` in `Backend/functions`, then `curl http://localhost:8080/health`.
- On an iPhone, `localhost` is the phone itself. In the app go to **Setup → Server** and enter your Mac's Wi-Fi address, e.g. `http://192.168.1.10:8080` (`ipconfig getifaddr en0`). Phone and Mac must be on the same Wi-Fi.
- If iOS asks to allow local network access for Guidance, tap **Allow**.

## Extension popup: "This device isn't paired" or pairing fails

- Use the code from the app's **Setup** tab for the right kid. Codes are 6 characters with no 0/O or 1/I.
- Open **Server address** in the popup and enter the same address as the app.
- Pairing again replaces the old pairing for that kid.

## A blocked site still loads

- The extension must be on with **All Websites → Allow** (Settings → Apps → Safari → Extensions → Guidance). Per-site or "Allow for One Day" permissions run out, and reinstalling the app can reset them. The extension popup shows "Guidance can't see websites yet" when this is the problem.
- Open pages pick up rule changes within about 15 seconds. Opening the extension popup also refreshes the rules.
- **After installing a new build of the app, quit and reopen Safari once.** Safari keeps the old extension code running until then.
- Testing with several simulators? The extension is paired per device. Make sure you're looking at the one you paired.
- Check the site is in the catalog (Rules → the category → site list), or add it under **Site exceptions → Always block**.
- Native apps aren't covered by the extension. Block them with Screen Time (see SETUP step 4).

## Guided prompts aren't being checked on a chatbot

The chatbot probably changed its page layout. Update its selectors in `Extensions/GuidanceSafari/Resources/content/adapters.js` (prompt box and send button), rebuild, and reinstall.

## Activity says "Haven't heard from … lately"

The extension checks in when Safari is used. If Safari has been used and it still says this, the extension was probably turned off in Settings.

## Face ID unlock fails

The parent lock needs a device passcode. In the Simulator, use **Features → Face ID → Enrolled** (if no passcode is available, the Simulator build unlocks without one).

## "Personal development teams do not support Family Controls"

You picked the old `GuideAI` scheme. Use **GuideAI Demo**. Family Controls needs a paid Apple Developer Program team.

## App installs but iPhone says the developer is not trusted

**Settings → General → VPN & Device Management → Developer App → Trust**, then Run again.

## Regenerate the Xcode project

```bash
python3 Scripts/generate_xcodeproj.py
```
