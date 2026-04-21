# Zero DevOps iOS

iOS companion to the Zero DevOps Android app — SwiftUI, AppAuth OIDC/PKCE, Keychain token storage.

## Features

| Tab | Screen | Description |
|-----|--------|-------------|
| Dashboard | DashboardView | KPIs, drift posture, recent deployments, quick links |
| Blueprints | BlueprintsView | List + deploy infrastructure blueprints |
| Cloud | CloudAccountsView | Select tenant-scoped cloud account |
| Analytics | AnalyticsView | DORA metrics, providers, failures, AI insights |
| Drift | DriftView | Posture banner, per-deployment drift checks |
| Alerts | NotificationsView | Notifications with mark-read / delete |
| Profile | ProfileView | User info, logout |

Detail screens: `DeploymentDetailView`, `ResourcesView`, `ResourceDetailView`, `CostView`

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 16+) |
| Auth | [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) — OIDC PKCE |
| Token storage | iOS Keychain (Security framework) |
| Networking | URLSession + async/await |
| Project format | Native Xcode project (`ZeroDevOps.xcodeproj`) |

---

## Setup (Mac + Xcode)

### Prerequisites

Xcode 15+ and an Apple Developer account for device signing.

### Steps

```bash
# 1. Clone
git clone https://github.com/devopsbootcamp-labs/zero-devops-ios.git
cd zero-devops-ios

# 2. Open
open ZeroDevOps.xcodeproj
```

In Xcode:
1. Select the `ZeroDevOps` scheme
2. Set your **Development Team** in *Signing & Capabilities*
3. Choose your iOS device
4. ▶ Run

### SPM dependencies

The project already declares `AppAuth-iOS` in the native Xcode project. Xcode fetches it automatically on first open.

---

## Auth Configuration

All constants are in `App/AppConfig.swift`:

```swift
static let apiBaseURL      = "https://api.devopsbootcamp.dev/"
static let oidcIssuer      = "https://keycloak.devopsbootcamp.dev/realms/zero-devops"
static let oidcClientId    = "zero-devops-mobile"
static let oidcRedirectURI = "com.devopsbootcamp.app://callback"
static let oidcScopes      = ["openid", "profile", "email", "offline_access"]
```

The Keycloak client `zero-devops-mobile` must have `com.devopsbootcamp.app://callback` registered as a valid redirect URI.

---

## Project Structure

```
App/
├── ZeroDevOpsApp.swift           # @main entry point
├── ContentView.swift             # Root login ↔ main router
├── AppContainer.swift            # Session + context manager
└── AppConfig.swift               # OIDC / API constants
Core/
├── Auth/
│   ├── OidcAuthManager.swift     # AppAuth PKCE flow
│   ├── AuthSessionManager.swift  # Token expiry + session
│   ├── TokenStore.swift          # Keychain persistence
│   └── TokenBundle.swift         # Token model
├── Network/
│   └── APIClient.swift           # URLSession HTTP client
└── Model/
    └── Models.swift              # All API data models
Features/
├── Login/
├── Dashboard/
├── Blueprints/
├── CloudAccounts/
├── Analytics/
├── Drift/
├── Notifications/
├── Profile/
├── Deployment/
├── MainShell/
└── Workspace/
Assets.xcassets/
Info.plist
ZeroDevOpsTests/
ZeroDevOps.xcodeproj/
```

---

## Security

- Tokens stored in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- Token expiry enforced with 30-second skew before every API call
- OIDC PKCE flow (no client secret on device)
- ATS enforced — `NSAllowsArbitraryLoads: false`
- No `x-account-id` header injected on aggregate/drift endpoints

---

## Related Repos

| Repo | Description |
|------|-------------|
| [zero-devops-android](https://gitlab.com/devopsbootcamp-dev-group/zero-devops-android) | Android companion app |
| [devopsbootcamp-labs](https://github.com/devopsbootcamp-labs) | Frontend / web apps |
