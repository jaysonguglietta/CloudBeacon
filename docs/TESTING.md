# Testing and acceptance

## Automated entry points

Run `bash Scripts/check-all.sh` on macOS. It syntax-checks every shell script, compiles/runs parser, security, and readiness harnesses, and validates entitlements. These harnesses need Apple's Swift compiler but not XCTest, allowing testing on Command Line Tools installations. They make no external requests. `swift test` additionally runs the package XCTest cases with a functioning full-Xcode toolchain.

The deterministic readiness suite exercises stable IDs after prepends, duplicate handling, readable paragraphs/entities, conservative resolution wording, empty/missing/future dates, preference validation, every polling interval, monotonic time, freshness without UI access, wake/reconnect recovery, failure backoff, cache opt-in/restart/clear/corruption/oversize handling, concurrent refresh suppression, cancellation, typed failure summaries, and diagnostic bounds/privacy.

Security regressions exercise hostile/ambiguous XML, depth/field/item limits, DTD/entity rejection, cancellation, adversarial description performance, HTTP status handling, declared and streamed response limits, and redirect rejection using in-memory fixtures. They are not a penetration test of Apple frameworks or AWS.

Run `bash Scripts/check-live.sh` separately to exercise the actual AWS URLSession client through parsing and monitor state. It needs internet, uses a disposable preference suite, and writes no offline snapshot. Upstream failure makes it fail; do not gate every pull request on AWS being reachable.

`Scripts/GenerateIcon.swift` creates native assets during bundle assembly. `codesign --verify --strict dist/CloudBeacon.app` and `plutil -lint dist/CloudBeacon.app/Contents/Info.plist` check the built artifact. GitHub Actions runs XCTest, offline checks, build, and artifact integrity on a hosted Mac; it does not perform OS interaction or publish releases.

## Manual acceptance gate

Record OS, architecture, app version/build, display configuration, and actual outcome for every release candidate. Do not mark a path passed based on source inspection or process existence.

| Journey | Acceptance |
|---|---|
| First launch | One AWS menu item appears; a first check produces a source-scoped result or explained failure; no credential prompt |
| Status | Red ×, amber !, green ✓, gray ? remain distinct in grayscale; header/tooltip/spoken label agree; green never claims global health |
| Fetch lifetime | Leave the popover closed through two intervals; last success advances; no duplicate network request on rapid Refresh/timer overlap |
| Recovery | Offline causes gray with retained history; manual retry works; reconnect/wake starts at most one due recovery check; check next-check/dated timestamps after midnight and time-zone change |
| Reading | Expand/select long text; search title/body, no result, clear; new update preserves existing expansion and keyboard focus |
| Copy | Preview exact summary/diagnostics; Copy produces the displayed text and accessible success feedback; preview can close; no outbound send |
| Offline copy | Off on clean install; opt in → success → restart offline shows Saved copy + gray; clear asks confirmation, removes disk copy, preserves current view; disabling removes snapshot or shows recoverable error |
| Login | Test enabled/disabled/approval pending/unavailable/error; approve/revoke in System Settings, return and observe actual state; reboot starts one stable Applications copy |
| Accessibility | Keyboard opens/escapes popover and completes search/disclosure/settings/refresh/quit; VoiceOver announces controls/reasons; no focus trap; increased contrast and large text remain readable |
| Displays | Small laptop workspace, light/dark menu bars, Retina/non-Retina, multiple displays; no overlap or unreachable footer/control; 20,000-character update scrolls/selects |
| Volume | 24 real-format updates, 500 unique synthetic updates, near-2 MB response; profile responsiveness on declared reference Mac; reject safety-limit excess without UI hang |
| Upgrade | Quit → replace at same path and identity → reopen; settings, cache schema, version, and login registration remain correct; one process only |
| Public release | Developer ID signature, notarization, stapled ticket, Gatekeeper on clean Mac; separately verify each advertised OS/architecture |

Current minimum supported OS is declared as macOS 13, not yet independently exercised. Intel builds are not produced/tested by the current host build. Local XCTest/default backend limitations and executed results are recorded in [REMEDIATION.md](REMEDIATION.md).

## Version 1.2 acceptance additions

`bash Scripts/check-features.sh` is included in check-all and exercises catalog loading/path rejection, exact 24-hour boundaries, age-out semantics, notification baseline/deduplication/restart/content changes/preferences, expiry/deselection cleanup decisions, bounded concurrency, partial failure, recovery, scoped report identity, watchlist persistence/limits, deliberate empty selection, and cancellation/late-result suppression.

Existing readiness assertions now expect a successful empty/recently quiet feed to report **No reports in the last 24 hours**, rather than unconfirmed simply because history is empty. Failed/stale/saved/ambiguous checks still cannot yield fresh green. Historical test counts above apply to version 1.1 only.

Manual additions: edit feeds across two regions, search and remove selections, Cancel versus Save, enforce 20-feed limit, restart, remove a feed mid-request, inspect mixed-success coverage, and check that the timeline/source summaries are correctly scoped. Verify the catalog loads from the installed app without the checkout/build directory present.

For notifications, exercise macOS not-determined/allowed/denied/revoked states with explicit opt-in, first-fetch baseline without a history flood, one new issue, one resolution preference change, no duplicate across polls/restart, and no alert for a report older than 24 hours. Check actual banner text, optional sound, fixed-dashboard click, and Focus suppression without a false delivery guarantee. Seed only this app's test notices to check publication-time expiry, deselection removal, confirmed manual clear, and cleanup after wake/relaunch. These system-level permission/delivery paths are not exercised by pure policy tests or CI, and the agent does not auto-enable notifications.
