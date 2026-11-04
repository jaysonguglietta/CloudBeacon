# Remediation and verification record

Updated November 4, 2026 for CloudBeacon 1.1.0 (2). The [security review](../SECURITY_REVIEW.md) preserves its audit evidence. Product findings F01–F09 are tracked below; review line numbers and original statuses may predate these changes. Use this tracker for current status.

| Review ID | Current implementation | Evidence and remaining gate |
|---|---|---|
| F01 — status contract | Implemented: shared StatusSnapshot, exact regional/latest-report wording, explicit reasons, guide, unknown on missing/future dates/empty/stale/saved/failed data | Deterministic snapshot checks pass. No all-clear claim or invented incident closure; RSS completeness remains an upstream limitation |
| F02 — monitoring/recovery | Implemented: application-owned service, separate freshness heartbeat, injected clocks/transport, monotonic scheduling, retry backoff, wake/network recovery, single-flight guard, dated footer | Deterministic interval/clock/freshness/backoff/concurrency/cancellation checks pass. Actual overnight and OS wake/network UI acceptance remains manual |
| F03 — history/context | Implemented: stable GUID/content hashes, exact duplicate collapse, conflicting GUID rejection, explicit preserved expansion, paragraph/entity handling, optional bounded atomic cache and confirmed clear | Identity/text/cache success/failure checks pass. Cache defaults off. UI focus continuity requires manual verification |
| F04 — accessibility | Implemented: distinct marks plus color, spoken label, primary text colors, status guide, native controls/shortcuts, adaptive scroll viewport, clear-search control | Build passes. VoiceOver, keyboard, contrast, enlarged-text and multi-display matrix remain unverified until exercised on supported Macs |
| F05 — login startup | Implemented: enabled/disabled/approval/unavailable reconciliation on settings open and application activation, OS settings handoff and recovery messages, stable local identity | Compiles. Real approval/revocation/reboot/upgrade checks require OS interaction; no silent permission changes were made |
| F06 — support/handoff | Implemented: app/build version, typed sanitized errors, ten-outcome diagnostics, exact local preview/copy and update summaries, copy failure feedback | Diagnostic privacy/bounds/version checks pass. Clipboard interaction remains manual; no automatic uploads or untrusted deep links |
| F07 — delivery verification | Implemented: default build backend with explicit local workaround, shell/plist checks, parser/security/readiness harnesses, GitHub CI, version metadata, native icon, clean staged bundles, gated Developer ID/notarization mode, full guides | Local release compilation/signature/icon/plist checks pass. Default backend on this development Mac fails initialization; legacy override works. XCTest locally needs full Xcode with an accepted license. Public signing cannot run without a Developer ID identity/notary profile; none was found |
| F08 — notifications | Optional hypothesis, not implemented | No user research established interruption requirements. Do not silently add permissions, persistent deduplication, or notification noise while fixing existing behavior |
| F09 — multi-feed watchlist | Optional hypothesis, not implemented | No additional region/service requirements or validated catalog supplied. Existing feed scope remains explicit; arbitrary outbound feeds would expand trust boundaries |
| Security F1/F2 — parser denial of service and malformed health | Preserved and extended the bounded linear parser, strict hierarchy/date checks, safe transport, cancellation, and regression coverage | Parser and 38 security checks pass, including high-count numeric entities; full platform/parser fuzz assurance remains ongoing |
| Security F3 — publisher identity | Release path implemented and credential-gated; local builds explicitly marked ad-hoc | A local signature is not Developer ID authentication. Actual notarization/Gatekeeper clean-Mac validation requires externally supplied credentials and an actual public release |

## Executed locally

- Parser/classification harness: 14 checks passed.
- Security regression harness: 38 checks passed, including transport fixtures and adversarial parser cases.
- Readiness harness: 43 checks passed, including scheduling, failure recovery, cache boundaries, and diagnostic privacy.
- Release compilation using explicit native backend compatibility override: passed.
- Strict local signature verification and entitlements plist validation: passed.
- The real-network URLSession transport→parser→monitor check passed against AWS: 24 updates, latest report classified as disruption. This exercises the app's core network/state path; it does not prove menu bar rendering or future AWS status.

## Unverified or externally gated

Automated computer-use previously timed out before interacting with the menu bar app. Compilation/process presence is not substituted for a visual pass. Perform the manual acceptance matrix before broad distribution. OS permission approvals and Xcode license acceptance remain user-controlled. This source delivery does not certify compatibility on untested macOS versions or architectures, and does not include an authenticated public binary release.

No accounts, billing, enterprise roles, team collaboration, AI summaries, or unrelated SaaS features were added. Current work repairs and completes the existing single-feed informational utility. Optional new workflows remain separate product decisions.
