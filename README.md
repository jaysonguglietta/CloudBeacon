# CloudBeacon

A native macOS menu bar companion for public AWS service reports. CloudBeacon watches **Multiple services in Middle East (UAE), `me-central-1`**, using the supplied [AWS RSS feed](https://status.aws.amazon.com/rss/multipleservices-me-central-1.rss). No AWS account, credentials, backend, or third-party packages are required.

## At a glance

| Indicator | Meaning |
|---|---|
| Red × | The latest regional report describes a disruption |
| Amber ! | The latest regional report describes degradation |
| Green ✓ | The latest report says **its issue** is resolved |
| Gray ? | Status is unconfirmed: connection failure, stale check, saved copy, empty feed, unfamiliar wording, or unreliable publication date |

**Green is not an all-clear for AWS.** This is one public regional RSS feed, not account-specific resource health or an availability measurement. Old unresolved reports never become green just because time passes. AWS notes that RSS formats can change and may omit relevant event data; see the [AWS Health documentation](https://docs.aws.amazon.com/health/latest/ug/aws-health-dashboard-status.html).

## Features

- Colored menu bar indicator with distinct glyphs, accessible state text, and a built-in status guide.
- Application-owned polling, independent of the popover, at 1, 5, or 15 minutes (default: 5).
- Retry backoff of 30, 60, 120, 240, then 300 seconds after failures; wake/connectivity recovery; one active request at a time.
- Published freshness state, dated last-success information, and visible next-check time.
- Searchable chronological update timeline, stable item identities, preserved expansion, readable paragraphs, and text selection.
- Optional offline saved copy, **off by default**, with explicit unconfirmed state and a confirmed clear action.
- Launch-at-login controls that reconcile external approval/revocation when the app activates or settings opens.
- Preview-and-copy update summaries and bounded, privacy-safe support diagnostics.
- Native app icon, sandboxing, hardened runtime, bounded parsing, fixed HTTPS destinations, and redirect rejection.

## Requirements and build

Declared target: macOS 13 or newer. A compatible Apple Swift toolchain is required; full Xcode is needed for XCTest. The minimum OS and Intel compatibility require manual release testing; compilation on one development Mac is not a compatibility certification.

```sh
bash Scripts/check-all.sh
bash Scripts/build-app.sh --local
open "dist/CloudBeacon.app"
```

The app runs in the menu bar without a Dock icon. Quit before replacing it. Move one copy to Applications for regular use, then optionally enable **Launch at login** in Settings. Do not run duplicate copies.

On this development Mac, the default Swift build backend fails to initialize with `Unknown error parsing property list`. The explicit compatibility workaround is:

```sh
CLOUDBEACON_BUILD_SYSTEM=native bash Scripts/build-app.sh --local
```

The legacy backend is deprecated by Swift. It is an opt-in local workaround, not the default release requirement. Full Xcode on this Mac also requires the user to review/accept its license before use; scripts do not accept licenses or change developer-tool selection.

## Verification

```sh
bash Scripts/check-all.sh      # offline parser, security, and monitor checks
swift test                    # XCTest, with a functioning full-Xcode toolchain
bash Scripts/check-live.sh     # optional real AWS request; needs internet
codesign --verify --strict "dist/CloudBeacon.app"
```

The check suite is also configured in [GitHub Actions](.github/workflows/ci.yml). Do not infer that a workflow passed merely because its configuration exists. Current executed results and manual verification limits are recorded in [remediation notes](docs/REMEDIATION.md).

## Documentation

- [User guide](docs/USER_GUIDE.md) — everyday use, settings, status interpretation, and recovery.
- [Architecture](docs/ARCHITECTURE.md) — state, scheduling, parser, trust boundaries, and storage.
- [Testing](docs/TESTING.md) — automated checks and the macOS manual acceptance matrix.
- [Release guide](docs/RELEASING.md) — versioning, signing, notarization, upgrade checks, and local builds.
- [Remediation tracker](docs/REMEDIATION.md) — findings addressed, evidence, and remaining gates.
- [Security policy](SECURITY.md) and [security review and remediation](SECURITY_REVIEW.md).

## Privacy and limits

AWS receives your network's public IP during checks. No analytics or automatic diagnostic uploads are implemented. Without offline storage enabled, incident content stays in memory. When enabled, one bounded snapshot is saved in the sandboxed app container; disabling the option attempts to delete it, and any failure is shown with a retryable Clear action. Diagnostics contain app/OS version, public feed scope, timestamps, and sanitized outcomes, not credentials or local paths.

The app cannot poll while the Mac sleeps and is not a paging service. It does not send notifications or monitor additional feeds. Those were review hypotheses, not confirmed defects; they remain optional future work pending actual user requirements. Public distribution requires a Developer ID identity and successful notarization; the local bundle is ad-hoc signed.
