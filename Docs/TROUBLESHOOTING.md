# Troubleshooting

## Xcode: “Signing requires a development team”

Select a Team on **every** target: main app and all three extensions.

## Authorization fails or status stays “Needs Authorization”

- Use a **physical device** (not Simulator)
- Settings → Screen Time → confirm no conflicting MDM/profile restrictions
- Delete app, reinstall, request authorization again
- Confirm **Family Controls** capability on app + extensions

## Shields do not appear

- Authorization must be **approved**
- `FamilyActivityPicker` selection must be **saved**
- **Block External AI** must be on in Parent Settings
- Open the **same** app/site you selected (tokens are opaque—only selected items are shielded)
- Try **Demo Tools → Reapply Shields**
- Reboot device if ManagedSettings state seems stuck (rare)

## Custom shield shows default Apple UI

- Confirm `GuideAIShieldConfiguration` and `GuideAIShieldAction` are embedded in the app
- Reinstall after changing extension bundles
- Extensions must share App Group and Team with the main app

## “Open GuideAI” on shield does nothing (older iOS)

`openParentalControlsApp` requires **iOS 26.5+**. On earlier OS versions the primary action falls back to **Close**; user opens GuideAI manually.

## Assistant: “Could not reach the assistant service”

- Backend running (`npm start` in `Backend/functions`)
- Phone and Mac on same Wi‑Fi
- Set `GUIDEAI_API_BASE_URL` to `http://<Mac-LAN-IP>:8080` in the Xcode scheme
- The app's Info.plist allows local HTTP only for local-network development; prefer HTTPS for any deployed backend

## Assistant: “Assistant service is not configured”

Set `OPENAI_API_KEY` and `OPENAI_MODEL` in `Backend/functions/.env`.

## Daily limit reached unexpectedly

Usage counts **foreground time** while the Assistant screen is open. Parent can **Reset Today’s Usage** in Parent Settings.

## App Group / defaults not shared

Bundle ID change without updating `AppConfig.appGroupIdentifier` and entitlements breaks shared storage. Keep app group IDs aligned across targets.

## Regenerate Xcode project

```bash
python3 Scripts/generate_xcodeproj.py
```

Then re-select your Development Team in Xcode.
