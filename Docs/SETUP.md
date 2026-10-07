# GuideAI — Development Device Setup

This beta uses **real** Apple Family Controls, `FamilyActivityPicker`, and `ManagedSettings` shielding. Screen Time behavior must be verified on a **physical iPhone** with Developer Mode enabled. The Simulator is fine for UI and chat development only.

## Prerequisites

- macOS with **Xcode** (current SDK installed)
- Apple Developer account (free or paid)
- Physical iPhone on iOS 17+ (recommended: latest iOS your Xcode supports)
- Node.js 20.6+ for the assistant backend (optional for Screen Time testing; required for AI chat)

## 1. Open the project

```bash
open GuideAI.xcodeproj
```

If `project.pbxproj` is ever corrupted, regenerate it:

```bash
python3 Scripts/generate_xcodeproj.py
```

## 2. Signing and capabilities (Xcode GUI)

For **each** target — `GuideAI`, `GuideAIShieldConfiguration`, `GuideAIShieldAction`, `GuideAIDeviceActivityMonitor`, and `GuideAITests` if you run tests:

1. Select the target → **Signing & Capabilities**
2. Choose your **Team**
3. Enable **Automatically manage signing**
4. Use bundle ID prefix `com.cac.guideai` (or your own; if you change it, update `AppConfig.appGroupIdentifier` to `group.<your-bundle>.shared`)

### Main app (`GuideAI`)

- Capability: **Family Controls**
- Capability: **App Groups** → `group.com.cac.guideai.shared` (must match `GuideAI/GuideAI.entitlements`)

### Each extension

- Capability: **Family Controls**
- Same **App Group** as the main app

Entitlement files are already in the repo:

- `GuideAI/GuideAI.entitlements`
- `Extensions/*/Guide*.entitlements`

**Note:** Family Controls requires Apple’s development entitlement. If authorization fails on device, confirm the capability is enabled and the provisioning profile was refreshed.

## 3. Embed extensions

The main app target should **Embed Foundation Extensions** for:

- `GuideAIShieldConfiguration.appex`
- `GuideAIShieldAction.appex`
- `GuideAIDeviceActivityMonitor.appex`

The generated Xcode project includes this embed phase. After regenerating the project, confirm in **Build Phases → Embed Foundation Extensions**.

## 4. Run on a physical iPhone

1. Connect the iPhone via USB or network debugging
2. On the iPhone: **Settings → Privacy & Security → Developer Mode** (enable if prompted)
3. Trust the developer certificate on first launch
4. In Xcode, select your iPhone as the run destination
5. **Product → Run**

## 5. In-app beta flow (device)

1. Complete onboarding (4 pages)
2. Tap **Enable Parental Controls** → approve Apple’s **individual** authorization (demo model; not full Family Sharing)
3. In **Parent Dashboard**: **Choose Apps & Websites** → pick AI apps/sites in `FamilyActivityPicker`
4. Enable **Block External AI** in Parent Settings
5. Set **Learning Mode**, daily limit, optional custom instructions
6. Switch to **Child Mode** (lock icon returns to Parent Mode)
7. Open a selected external AI app or site → Apple’s shield should appear (custom copy from the Shield Configuration extension)
8. Use **Ask GuideAI** for the controlled assistant

## 6. Assistant backend

From `Backend/functions`:

```bash
cp .env.example .env
# Edit .env: set OPENAI_API_KEY and OPENAI_MODEL
npm install
npm run build
npm start
```

`npm start` loads `Backend/functions/.env` automatically. Do not commit that file.

Default URL in Debug: `http://127.0.0.1:8080`.

For a **physical iPhone**, the phone cannot reach `127.0.0.1` on your Mac unless you use your Mac’s LAN IP:

1. Find your Mac IP (e.g. `192.168.1.10`)
2. In Xcode: **Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables**
   - Add `GUIDEAI_API_BASE_URL` = `http://192.168.1.10:8080`
3. Ensure local network access is allowed (Info.plist already includes local networking for development)

## Simulator limitations

| Feature | Simulator |
|--------|-----------|
| Family Controls authorization | Unreliable / unavailable |
| `FamilyActivityPicker` | Limited |
| Real app/site shields | **No** |
| Parent biometrics | Simulated only |
| Controlled AI chat | Yes (with backend) |
| Usage limits | Yes |

## 7. Debug demo tools

In **Debug** builds, Parent Dashboard includes **Demo Tools**: authorization status, token counts, reapply/clear shields, backend health check, reset onboarding/usage.

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
