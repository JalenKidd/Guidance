# Troubleshooting

## “Personal development teams do not support Family Controls”

This is an Apple account restriction, not a Swift error. A free Personal Team cannot create a provisioning profile containing the Family Controls entitlement.

- For the competition video now: choose the **GuideAI Demo** scheme and run it on the iPhone
- For real app/site shields: enroll or sign in with an active Apple Developer Program team, then assign that same team to the app and all three extensions

Do not remove the entitlements from the full `GuideAI` target; that would make the build install while silently removing the feature the app is meant to demonstrate.

## App installs but iPhone says the developer is not trusted

On iPhone, open **Settings → General → VPN & Device Management → Developer App**, select the Apple ID, and tap **Trust**. Keep Developer Mode enabled, reconnect the phone, then Run again.

## iPhone is unavailable in Xcode

- Unlock the phone and leave it on the Home Screen
- Confirm **Trust This Computer** if prompted
- Keep the cable connected until Xcode finishes preparing developer support
- Open **Window → Devices and Simulators** and wait until the device shows as ready
- Use the iPhone 11 for the current demo if the other phone still reports that developer services are unavailable

## Xcode: “Signing requires a development team”

For the full build, select the same paid Team on **every** target: main app and all three extensions. The `GuideAI Demo` target is already configured for the local Personal Team.

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

## “Open Guidance” on shield does nothing (older iOS)

`openParentalControlsApp` requires **iOS 26.5+**. On earlier OS versions the primary action falls back to **Close**; user opens Guidance manually.

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
