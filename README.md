# CloudBeacon

A native macOS menu bar companion for public AWS service reports. Choose the AWS regions and services you care about, see **only the last 24 hours**, and optionally receive native macOS notifications. No AWS account, credentials, server, analytics, or third-party packages are required.

## At a glance

| Indicator | Meaning within your selected feeds |
|---|---|
| Red × | A latest recent report describes disruption |
| Amber ! | A latest recent report describes degradation |
| Green ✓ | No reports were published in the last 24 hours, or latest recent reports indicate resolution |
| Gray ? | Coverage is incomplete, stale, saved/offline, undated, or otherwise unconfirmed |

**Green is scoped to your 24-hour report window, not an AWS-wide all-clear.** An older report aging out is hidden, not marked recovered. AWS [notes that RSS formats may change and may omit relevant event data](https://docs.aws.amazon.com/health/latest/ug/aws-health-dashboard-status.html).

## Features

- **Choose regions and services:** Settings → Choose regions and services. Search the bundled AWS catalog, select service/region pairs, and save. Up to 20 feeds; the original UAE multiple-services feed remains the default on upgrade.
- **Per-feed coverage:** inspect each selected feed's result, source scope, and last successful check. Failed feeds cannot silently become green; known issues remain visible with an incomplete-coverage warning.
- **Rolling 24 hours:** old reports disappear from timeline, summaries, saved snapshots, and notification eligibility, including at the freshness heartbeat without new network data.
- **Native notifications:** opt in from Settings; control resolution alerts and sound. New reports are deduplicated across polls/restarts, one newest eligible report per feed/check. First checks establish a baseline, avoiding a history flood.
- **Notification cleanup:** delivered CloudBeacon alerts expire 24 hours after report publication. Cleanup runs on launch, activation, wake, successful checks, and roughly every minute while running. Removed feeds' delivered alerts are cleared too. Manual clear includes confirmation and does not replay seen reports.
- **Dependable polling:** 1/5/15-minute cadence, bounded three-request concurrency, per-feed retries, cancellation on watchlist changes, wake/reconnect recovery, published freshness, and app-owned lifetime.
- **Readable updates:** searchable timeline with feed labels, stable expansion, safe paragraphs/entities, copy previews, and local diagnostics.
- **Local privacy:** optional offline snapshots (off by default), bounded hashed notification deduplication metadata, launch-at-login reconciliation, App Sandbox, hardened runtime, fixed-host HTTPS RSS, and rejected redirects.

## Build and run

Declared target: macOS 13+. A compatible Apple Swift toolchain is needed; full Xcode is needed for XCTest. Only tested OS/architecture combinations should be advertised as supported.

```sh
bash Scripts/check-all.sh
bash Scripts/build-app.sh --local
open "dist/CloudBeacon.app"
```

CloudBeacon lives in the menu bar without a Dock icon. Quit before replacing the bundle. For regular use, install **one** copy in Applications, then optionally enable Launch at login.

This development Mac's default build backend cannot initialize. Its explicit local workaround is:

```sh
CLOUDBEACON_BUILD_SYSTEM=native bash Scripts/build-app.sh --local
```

The legacy backend is deprecated and is not the default release requirement. Full Xcode may require the user to accept its license; scripts do not accept licenses or change tool selection.

## Verification and documentation

```sh
bash Scripts/check-all.sh      # offline parser, security, monitor, watchlist/alert/window checks
swift test                    # XCTest on a functioning full-Xcode toolchain
bash Scripts/check-live.sh     # optional real AWS request; requires internet
codesign --verify --strict "dist/CloudBeacon.app"
```

[GitHub CI](.github/workflows/ci.yml) runs XCTest, offline checks, a local build, and bundle verification. Native permission prompts, banner display/Focus, keyboard/VoiceOver, and login/reboot behavior require manual acceptance; policy tests do not claim to exercise macOS Notification Center.

- [User guide](docs/USER_GUIDE.md)
- [Architecture and trust boundaries](docs/ARCHITECTURE.md)
- [Testing and manual acceptance](docs/TESTING.md)
- [Signing, notarization, and releases](docs/RELEASING.md)
- [Remediation/feature status](docs/REMEDIATION.md)
- [Security policy](SECURITY.md) and [historical review](SECURITY_REVIEW.md)

## Catalog, privacy, and limits

The bundled catalog contains 5,876 public service/region pairs from [AWS dashboard metadata](https://servicedata-us-east-1-prod.s3.amazonaws.com/services.json), captured November 5, 2026. It reflects that snapshot, not guaranteed future availability. A selected feed that fails is explicitly unconfirmed. Global services are shown in a Global region. Update the catalog with `python3 Scripts/update-catalog.py`, review the diff, and run tests before shipping. App runtime never downloads or executes dashboard JavaScript or accepts arbitrary feed URLs.

AWS sees your public IP during checks. Notification preferences and bounded hashes/expiry times are stored locally for deduplication. Full report bodies are saved by CloudBeacon only if offline copies are enabled; macOS also retains delivered alert titles until cleanup. Disabling saved updates deletes snapshots for currently watched feeds; deselection clears the removed feed's snapshot. Diagnostic previews are copied locally, never automatically uploaded.

macOS controls notification permission, banners, sounds, Focus, and delivery. A queued request is not proof a banner appeared. The app cannot fetch or clean Notification Center while quit/asleep; expired alerts are removed when it runs again. This is an informational RSS monitor, not guaranteed paging or account-specific resource health. Public binary distribution still requires Developer ID signing and notarization; local output is ad-hoc signed.
