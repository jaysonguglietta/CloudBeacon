# CloudBeacon security review and remediation

> Historical review snapshot. Implementation has since changed; see [current remediation and verification status](docs/REMEDIATION.md). Original line references identify the reviewed snapshot and may not match current source.

Reviewed and updated November 4, 2026. Scope: all supplied application sources, package manifest, scripts, tests, bundle metadata, and effective entitlements. No Git repository/history, external release service, cloud deployment, or backend was available. This document supersedes the earlier review's claim that no parser vulnerability was found.

## 1. Executive Summary

The adversarial review confirmed a quadratic regex denial of service (Medium), weak RSS hierarchy/date validation (Low), and a conditional public-distribution authenticity risk (Medium for public releases). The source-level fixes are implemented and regression checked. Public-release signing and notarization are implemented as a fail-closed workflow but remain unexecuted without credentials.

No demonstrated RCE, SSRF, credential leakage, authentication bypass, or executable injection was found. This is not assurance against unknown platform defects.

## 2. System Overview and Trust Boundaries

Native macOS SwiftUI menu bar app → ephemeral URLSession → fixed AWS HTTPS RSS endpoint → in-memory XML parser → literal SwiftUI Text and inferred health. A fixed AWS Health link opens on user action. UserDefaults stores only a supported refresh interval; ServiceManagement handles optional login launch. No accounts, sessions, tenant records, database, credentials, or inbound service exists.

Assets: status integrity, application availability, local process integrity, login registration, and network privacy. Boundaries: remote bytes → parser; parsed records → health/UI; build source/tools → installed executable; user consent → login registration.

## 3. Threat Model

- Feed publisher/delivery compromise can supply hostile XML and misleading dates or titles.
- A network attacker can block/slow connections; substitution requires defeating normal TLS or controlling trusted infrastructure. No custom TLS bypass exists.
- A malicious distributor can substitute an app if users run unauthenticated software.
- A same-user local attacker can tamper with local files/preferences; the app holds no secrets.

There is no arbitrary internet submission path to the fixed feed URL. Feed-driven vulnerabilities require influence over its authenticated response.

## 4. Attack Surface Inventory

- `Sources/StatusCore/FeedTransport.swift`: fixed URL, redirect rejection, successful HTTP 200 required, declared and actual byte limits, cancellation checks, non-UI download processing.
- `Sources/StatusCore/Feed.swift`: UTF-8 XML, DTD/entity rejection, external entity resolution disabled, hierarchy validation, field/item/depth/callback limits, cooperative deadline, linear description conversion, date-aware health.
- `Sources/AWSStatus/FeedStore.swift`: ephemeral session, 20/30-second network timeouts, one refresh in flight, cancellation propagation to detached parsing, monotonic refresh/freshness timestamps.
- `Sources/AWSStatus/AWSStatusApp.swift`: literal text, local search, lazy history rendering, fixed browser destination, user-initiated login registration, independent freshness heartbeat.
- `Sources/AWSStatus/StatusIcon.swift`: enum-to-image conversion; no executable input.
- Scripts, manifest, tests, README, entitlements and bundle metadata were inspected. No third-party packages, remote build scripts, or application shell execution exists.

## 5. Prioritized Findings and Fixes

### F1 — Quadratic description regex (Medium, High confidence)

Original evidence: `FeedParser.plainText` used `<[^>]+>` with Foundation regex replacement. Valid CDATA containing repeated `<` took 0.62/2.53/9.73 seconds at 10K/20K/40K characters in the original unoptimized probe. A compromised response could consume CPU and keep refresh pending despite the network timeout. CWE-1333/CWE-400.

Fix: replace regex with one scalar pass, preserving unmatched trailing markup literally. Add 262,144-byte description and 4,096-byte title/GUID limits, 256-byte date limit, 512 items, 16 element levels, 100,000 callbacks, cancellation checks, and a two-second cooperative callback deadline. Maximum total response remains 2 MB. Fields that exceed budgets reject the entire response rather than silently changing status data.

Validation: release-optimized adversarial checks at 10K, 40K, 100K, and 262,144 bytes preserve the payload and complete below the generous two-second regression threshold. Representative post-fix 40K time is 0.003 seconds and 262K time is 0.015 seconds. Absolute timing depends on hardware/build settings; original and new probes used different optimization settings. Limits are tested both inclusively and with rejected overflow. Cooperative deadlines do not preempt arbitrary work inside system frameworks.

### F2 — Invalid hierarchy and undated health (Low, High confidence)

Original evidence: the parser only recorded that `rss` and `channel` appeared anywhere. `<outer><rss/><channel/><item><title>[RESOLVED] spoof</title></item></outer>` was accepted, and undated resolved records could drive the indicator. A malformed or compromised response could produce misleading status. This is not an independent ability to forge AWS content. CWE-20/CWE-345.

Fix: require an RSS root with exactly one direct channel; items must be direct channel children. Reject nested items, duplicate recognized fields, and nested element content within recognized item fields. Missing dates remain visible as history but yield unknown health. Dates more than five minutes in the future also yield unknown. Normal-status wording requires exact equality rather than an unrestricted prefix. The newest sorted item still determines overall health; ambiguous future entries fail conservatively rather than falling back to an older resolution.

Validation: malformed-root, misplaced-item, duplicate-channel/title, nested-field/item, undated-resolution and future-date regressions. Valid CDATA, Unicode, empty feeds, original AWS date format, and chronological sorting remain supported.

### F3 — Public release authenticity (conditional Medium, High confidence)

Original evidence: `Scripts/build-app.sh` used `codesign --sign -`, and the inspected bundle had no TeamIdentifier. Ad-hoc signatures authenticate no publisher. A malicious distributor could supply a counterfeit application if users execute it; no Gatekeeper or updater bypass was demonstrated. CWE-345.

Fix: explicit local/release modes, fresh temporary bundle staging, separate release output, and no ad-hoc fallback for public releases. Release mode requires a Developer ID Application identity, notarytool Keychain profile, and stable owned bundle identifier; signs with timestamp/hardened runtime; submits for notarization; staples/validates the ticket; assesses Gatekeeper; and verifies the signature before publication. See Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Validation: local packaging and strict signature verification pass; missing release configuration fails before compilation. Credentialed notarization, certificate identity and a downloaded/quarantined clean-Mac launch remain unverified. Local output intentionally remains ad-hoc signed.

## 6. Combined-Risk Scenarios

Feed compromise can still supply plausible false status even after structural validation. Independent monitoring is required for critical operational decisions. Resource budgets reduce feed-driven CPU/UI pressure but do not promise immunity to platform parser bugs. A malicious distributor remains dangerous if users bypass OS checks or obtain an app through a compromised channel.

## 7. Dependency and Configuration Risks

No third-party packages are declared. Foundation, AppKit, SwiftUI, XMLParser, and ServiceManagement require an OS/toolchain patch policy; a complete platform CVE assessment was not performed. Effective local bundle entitlements are App Sandbox and outbound networking only, with hardened runtime and no broad file-access exceptions. Endpoint confinement is in code; the outbound entitlement itself is not hostname-specific.

The package targets macOS 13+ and builds the host architecture. No CI, containers, cloud IAM, updater, repository history, or external artifact provenance was available for audit.

## 8. Secure Design Gaps

- Cooperative deadlines are not process-level isolation or hard CPU limits.
- Public RSS remains an inferred regional history, not account-specific or cryptographically signed incident state.
- No persisted content or forensic event trail exists; this minimizes retention but limits diagnosis.
- Network timeout/offline and runtime sandbox behavior need broader integration testing.
- Monotonic clocks and separate freshness publication address wall-clock/stalled-request concerns, but sleep/wake and accessibility still need manual verification.
- A supplied signing identity and successful notarization cannot guarantee the absence of all malicious or vulnerable code.

## 9. Remediation Roadmap

Implemented: F1/F2 source fixes, resource bounds, cancellation propagation, off-main downloading, monotonic scheduling/freshness, lazy history, clean packaging, fail-closed public release workflow, regression tests and documentation.

Remaining: run full XCTest with Xcode; execute credentialed notarization; verify downloaded release on a clean Mac; test sleep/wake, login registration and VoiceOver; extend deterministic transport timeout/cancellation coverage; fuzz the bounded parser in isolated processes.

## 10. Security Test Plan and Results

Executed during remediation:

- Original 14 standalone parser/classifier checks passed.
- Optimized security suite passed: invalid structures, field/item/depth/callback budgets, UTF-16 rejection, Unicode handling, date policy, pathological descriptions, cancellation, and in-memory URLProtocol transport fixtures.
- Transport fixtures verify successful fetch, non-200 rejection, oversized declared length, oversized actual bytes without Content-Length, and the redirect delegate's nil decision. No private-address connection is made.
- Release compilation, local bundle assembly, and strict signature verification passed.
- Shell syntax checks passed; release invocation without credentials fails closed.

The selected Command Line Tools lack XCTest. In this restricted environment compiler caches were redirected into `.build`; SwiftPM's nested sandbox could not initialize, so build checks explicitly disabled that build-tool sandbox. Packaged App Sandbox entitlements remain enabled. No OS exploitation, AWS attack traffic, GUI penetration test, or credentialed public release was performed.

Run `bash Scripts/check-parser.sh`, `bash Scripts/check-security.sh`, `swift test --build-system native`, and `bash Scripts/build-app.sh --local`. For credentialed release instructions see README. Continue with isolated parser fuzzing and clean-Mac release/runtime checks before broad distribution.

## 11. Open Questions and Assumptions

The fixed regional public feed is intentional. No AWS keys are needed. Feed history may be old; old incident dates do not automatically resolve incidents. Five minutes is the permitted publication clock skew. Parser limits deliberately fail closed and may require adjustment if AWS legitimately expands its feed. No Developer ID identity, owned public bundle ID, or notarization profile was supplied. No guarantee is made about unseen infrastructure or a pre-existing distributed binary matching source; the local app was rebuilt from the remediated source.

## 12. Product Review Executive Summary

CloudBeacon is a single-user macOS companion for noticing public AWS reports from the supplied UAE multiple-services feed. Its primary inferred user is a developer/operator who wants to glance at a menu bar light and read the source update. It is not a global AWS all-clear, account-health integration, or paging service. There are no teams, billing, hosted records, or administrative roles to complete.

Following the product review, source changes address status ambiguity, polling lifetime/recovery, unstable history identities, text readability, non-color indicators, startup-state reconciliation, optional offline context, local diagnostics, and repeatable verification. The current state is an automated-tested local build with remaining OS-interaction and public-release gates, not a fully certified production distribution. See [remediation evidence](docs/REMEDIATION.md).

## 13. Existing Feature Inventory

| Feature | Current status | Evidence | Limitation |
|---|---|---|---|
| Regional RSS parsing/classification | Verified for tested fixtures and live core path | `FeedParser`, `StatusSnapshot`, parser/security/readiness harnesses, live check | Latest report only; upstream RSS completeness cannot be guaranteed |
| Monotonic scheduling/retry/freshness | Verified in deterministic monitor tests; OS lifecycle integration unverified | `FeedMonitor`, application-owned `MonitoringService` | Overnight wake/connectivity behavior needs manual acceptance |
| Colored indicator and non-color marks | Implemented but visual behavior unverified | `StatusIcon`, `MenuLabel` | VoiceOver, grayscale and display matrix not exercised |
| History/search/expansion/copy previews | Parser/model behavior verified; UI interaction unverified | `FeedParser`, `StatusView`, readiness checks | No permanent archive; clipboard/focus behavior needs manual testing |
| Optional offline copy | Verified at storage/monitor level | `SnapshotCache`, readiness checks | Defaults off; saved copy is always unconfirmed until live success |
| Login startup | Partial verification | `SettingsController`, ServiceManagement | Approval/revocation/reboot must be exercised on installed bundle |
| Version/diagnostics | Bounded privacy-safe text verified; copy UI unverified | `FeedMonitor.diagnostics`, `StatusView` | No automatic uploads or external support destination |
| Local packaging | Verified locally | `build-app.sh`, signature verification | Ad-hoc signature; default local toolchain backend is broken |
| Public distribution | Credential-gated workflow implemented | release mode, release guide | Signing/notarization and clean-Mac Gatekeeper tests not executed |
| Notifications/additional feed watchlist | Not found, intentionally outside implemented scope | Complete current source inventory | Product hypotheses requiring user requirements, not repair blockers |

No mock integration is shipped. “Verified” is scoped to the named tests; source presence is not a substitute for UI exercise.

## 14. User Journey Review

The implemented journey is launch → scheduled regional check → glance at scoped status → expand/search source updates → optionally refresh/open AWS Health/copy a preview. Failure preserves history, explains uncertainty, and schedules retry. Settings provide cadence, OS login registration, optional offline retention, clear confirmation, and diagnostic preview.

Core journeys still requiring end-to-end OS verification are first launch, keyboard/VoiceOver reading, settings return from approval, overnight sleep/wake recovery, clipboard feedback, and upgrade/reboot continuity. See the explicit [manual matrix](docs/TESTING.md). A user leaves the app for full AWS Health context by design; reproducing that entire dashboard is not a missing core workflow.

## 15. Prioritized Feature Backlog

This is the current disposition of the original product-review recommendations. The implementation and evidence for each ID are tracked in [REMEDIATION.md](docs/REMEDIATION.md); testable acceptance outcomes and failure/recovery scenarios are in [TESTING.md](docs/TESTING.md).

| ID | Recommendation | Category / type | Priority | Relative effort | Confidence | Dependency/current gate |
|---|---|---|---|---|---|---|
| F01 | Explicit regional/latest-report status contract | Core workflow / complete | P1 | Medium | High | Implemented; retain conservative inference |
| F02 | Dependable application-owned monitoring and recovery | Existing feature / improve | P1 | Medium | High | Implemented/tested model; manual lifecycle gate |
| F03 | Stable readable timeline and optional saved context | Existing feature / improve | P2 | Medium | High | Implemented/tested IDs/text/storage; UI continuity gate |
| F04 | Equivalent interpretation without color or mouse | Existing feature / improve | P1 | Medium | High | Implemented marks/labels; assistive-tech gate |
| F05 | Reconcile actual login-item approval state | Existing feature / complete | P1 | Small | High | Implemented; installed OS-state transition tests |
| F06 | Privacy-safe support and incident handoff | Production readiness / add | P2 | Small | High | Implemented/tested diagnostic model; clipboard gate |
| F07 | Repeatable builds, tests, signing and release checks | Production readiness / complete | P1 | Medium | High | CI configured; credentials/manual compatibility gates |
| F08 | Validate opt-in incident notifications | Strategic hypothesis / add | P2 hypothesis | Medium | Medium | Validate interruption needs before permission/dedup implementation |
| F09 | Validate curated additional AWS feeds | Strategic hypothesis / add | P3 | Large | Low | Obtain actual region/service list and aggregation requirements |

There is no established P0 for continued personal informational use. Public-release authenticity is a separate security finding (F3), not evidence that local RSS reading is unusable. Do not turn exploratory features into release blockers.

For F08, validate with intended users which reports merit interruption; first fetch must baseline history, repeated polls/restarts must not duplicate alerts, denied permission must leave monitoring usable, and notifications must retain scoped wording. For F09, validate real region/service demand before building a catalog; each feed needs independent freshness, bounded concurrency, cancellation on removal, and aggregate wording that cannot hide unknown coverage behind green. Neither feature should add arbitrary outbound URLs or account credentials to the present trust boundary without a new design review.

## 16. Features to Simplify, Consolidate, or Remove

Status meaning now comes from one `StatusSnapshot`; menu and popover use the same presentation helpers. Diagnostics reuse sanitized monitor outcomes rather than a second independent health light. Timeline counts remain updates, not invented incident counts. Keep the fixed dashboard handoff, explicit scope, and readable source text.

No evidence justifies removing refresh, search, history, cadence settings, or optional login startup. Accounts, billing, AI summaries, team chat, and cloud sync remain unrelated. Internal `AWSStatus` executable naming and the existing local bundle ID are retained to avoid needless migration risk through the CloudBeacon rename.

## 17. Recommended Delivery Sequence

1. Use the implemented status/scheduler/history repairs with automated regression checks.
2. Complete installed-app accessibility, login, sleep/wake, clipboard, and upgrade acceptance; fix observed failures before expanding claims.
3. Verify the exact pushed commit's CI result and resolve failures; local build success alone does not validate hosted toolchains.
4. If distributing publicly, supply Developer ID/notarization credentials and complete clean-Mac release testing before binary publication.
5. Validate notifications and additional-feed demand before taking on their new state, permissions, storage, and maintenance costs.

No calendar estimate is implied; delivery capacity and target distribution remain unspecified.

## 18. Product Validation and Acceptance Test Plan

Current automated checks cover parser, transport safety fixtures, identity/readability, conservative snapshots, every interval, clock changes, freshness, failures/backoff/recovery, concurrent requests, cancellation, optional cache lifecycle/corruption/limits, and diagnostic privacy/bounds. A separate opt-in live check covers the actual network→parser→monitor path. GitHub CI additionally runs XCTest and builds/verifies a local bundle.

Manual acceptance must cover the one local-user role with OS login permission enabled/disabled/pending/revoked, clean start, empty/loading/error/stale/saved states, failed request recovery, repeated refresh, closed-popover monitoring, search/no-results, long descriptions, copy preview, clear confirmation, and installed upgrade. Test keyboard navigation, VoiceOver, grayscale, light/dark/increased contrast, larger text, small and multiple displays, and realistic near-limit data. See [TESTING.md](docs/TESTING.md) for observable pass conditions. UI and minimum-OS compatibility remain unverified until exercised.

## 19. Product Open Questions and Assumptions

The supplied UAE feed remains intentional unless the owner specifies otherwise. Local informational use is the working assumption; public release audience, supported Intel Macs, signing team, and support destination are unspecified. Saved content is opt-in; cache schema and reset behavior are documented. No notification permission or additional-feed choice is silently introduced. RSS state does not promise complete AWS incident lifecycle data.

Highest-value next actions: (1) close real OS monitoring/recovery acceptance (F02); (2) exercise keyboard/VoiceOver and history continuity (F04/F03); (3) verify login approval/reboot/upgrade (F05); (4) run the exact release/CI compatibility gate and supply credentials only if shipping binaries (F07/F3); (5) validate notification demand before implementation (F08). These close evidence gaps and operational risk before adding speculative breadth.
