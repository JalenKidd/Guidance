# Guidance Architecture

## Problem space

Parents need control over **how** AI participates in learning—not a binary allow/ban. Guidance combines Apple Screen Time APIs for **parent-selected** external AI apps/sites with an in-app assistant whose behavior is governed by a **parental policy** enforced on the server.

## Policy and parent settings

```
Parent Settings (UI, behind LocalAuthentication)
        ↓
ParentalPolicy (mode, limits, block flag, custom instructions)
        ↓
PolicyStore (LocalPolicyStore → App Group UserDefaults)
        ↓
AppEnvironment.syncShieldsFromPolicy()
```

`ParentalPolicy` is the source of truth on device for the beta. A future `RemotePolicyStore` can sync from Firebase without changing UI contracts.

## External AI restriction (Apple-enforced)

```
FamilyActivityPicker (parent selects apps & web domains)
        ↓
FamilyActivitySelection (opaque tokens, Codable → App Group)
        ↓
ShieldManager → ManagedSettingsStore.shield
        ↓
iOS system shield (+ custom Shield Configuration / Action extensions)
```

When `blockExternalAI` is true and authorization is approved, the app sets:

- `store.shield.applications = selection.applicationTokens`
- `store.shield.webDomains = selection.webDomainTokens`

When blocking is off or authorization is revoked, shields are cleared.

**Boundary:** Apple enforces blocking of **selected** tokens only. Guidance does not claim Internet-wide AI detection in this MVP.

## Controlled assistant (Guidance-enforced)

```
Child message
        ↓
Guidance iOS (chat UI, local history, usage timer)
        ↓
POST /chat { conversation, policy snapshot }
        ↓
Backend promptBuilder (mode + safety + parent instructions)
        ↓
OpenAI Responses API (key only on server)
        ↓
Response text → child
```

**Boundary:** Learning/Standard/Restricted behavior is enforced by **server-built system instructions**, not client-editable prompts. Daily time limits are enforced on device by `UsageTracker` (foreground time on the Assistant screen).

## Authorization model (beta)

- `AuthorizationCenter.shared.requestAuthorization(for: .individual)` for one-device demos
- Code paths are structured so `.child` Family Sharing authorization can be added later

## Extensions

| Extension | Role |
|-----------|------|
| `GuideAIShieldConfiguration` | Custom shield UI copy |
| `GuideAIShieldAction` | Primary button → open parental controls app (iOS 26.5+) or close |
| `GuideAIDeviceActivityMonitor` | Scaffold for future AI-free schedules |

## Data storage

| Data | Location |
|------|----------|
| Policy, selection, usage, onboarding flag | App Group UserDefaults |
| Chat messages | App Group UserDefaults (local beta; not shown in parent dashboard) |
| API keys | Backend environment only |

## Privacy defaults

- Parent dashboard emphasizes **usage and mode**, not message surveillance
- Production child-data handling requires separate legal/product review
