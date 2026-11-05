# Architecture and trust boundaries — 1.2

## Components

- `Feed.swift`: bounded RSS parser, stable hashed identity, safe linear plain-text/entity conversion, date handling, conservative title-prefix inference.
- `FeedCatalog.swift` and bundled `Resources/aws-feeds.json`: validated AWS metadata snapshot, fixed-host feed descriptors, and shared 24-hour `RecentWindow` policy.
- `FeedTransport.swift`: fixed HTTPS host/path construction, validated ASCII feed ID, ephemeral URLSession, rejected redirects, timeouts, cancellation, declared/actual response limits.
- `StatusSnapshot.swift`: per-feed confidence/health and sanitized error categories.
- `FeedMonitor.swift`: independent per-feed scheduling, injected wall/elapsed clocks and transport, published freshness, retry state, filtered items, optional bounded snapshots.
- `WatchStore.swift`: persisted selection (maximum 20), three-worker task group, cancellation/generation isolation, per-feed coverage, scoped timeline and aggregate indicator.
- `SnapshotCache.swift`: atomic versioned JSON snapshots with size/item/identity limits; the original feed's filename is preserved for migration, other feeds have independent files.
- `NotificationPolicy.swift`: pure baseline/deduplication/coalescing policy, bounded persisted fingerprints, and publication-age/deselection retention decisions.
- `NotificationController.swift`: user-initiated macOS permission, serialized native delivery, safe fixed-dashboard click, cleanup and recovery/status messages.
- `FeedStore.swift`: application-owned monitoring service, separate freshness heartbeat, wake/connectivity hooks, app delegate.
- `SettingsController.swift`: OS login-item reconciliation and version metadata.
- `AWSStatusApp.swift`, `WatchlistEditor.swift`, `StatusIcon.swift`: native menu bar/popover, shared status marks/colors, staged region/service picker, coverage, recent timeline, settings, local copy previews and confirmations.

All core files are under `Sources/StatusCore`; app integration/UI is under `Sources/AWSStatus`. Apple frameworks supply networking, cryptography, notifications, and UI. No third-party dependencies or backend are present.

## State and scheduling

The watchlist defaults to the original UAE feed only when no selection has been saved. An explicit empty selection persists and does not fetch. Selected IDs must occur in the bundled catalog and satisfy the 20-feed bound. Staged edits apply only on Save. A selection change cancels the active generation, deletes removed feeds' optional snapshots, and creates the new monitor set; late results cannot publish into it.

Each monitor uses an elapsed clock based on ContinuousClock for cadence and the wall clock for dates/display. Success resets retry state and schedules the chosen interval. Failures preserve recent history, produce unconfirmed coverage, and back off at 30/60/120/240/300 seconds. Recovery has a 15-second attempt cooldown. One request is active per monitor and three per watchlist batch. A separate five-second freshness heartbeat continues during network requests and closed-popover use. Stop/cancellation propagates to transport and detached parsing.

Snapshots evaluate raw parsed dates conservatively, but published timeline/cache items are filtered to the last 24 hours. Undated or far-future items block confidence. Empty/old-only successful feeds become quiet green with explicit no-recent-reports wording. Aging out is not incident resolution. Aggregate known disruption/degradation wins but discloses incomplete coverage; without a known issue, any unconfirmed feed blocks green. Quiet and resolved states never claim global/account health.

## Notifications and retention

Alerts are opt-in, with OS authorization requested only by the toggle. OS authorization and the app's enabled preference are separate and rechecked on activation. The pure ledger baselines the first check, fingerprints GUID/title/body/date plus feed scope, ignores older/future reports, respects resolution preference, and coalesces to one newest eligible report per feed/check. It persists bounded hashes/expiries, not report bodies. Restart does not replay seen reports. Disabling/re-enabling baselines again.

The controller serializes deliveries to avoid ledger races, checks selection/time eligibility before and after native submission, and records deduplication success only after acceptance. Failure remains retryable. macOS/Focus control actual banners; acceptance is not a presentation receipt. Notification clicks use a fixed AWS Health destination, not feed-provided URLs.

Delivered notices carry source feed ID and publication-plus-24-hour expiry. Cleanup queries this app's own notices and removes expired/deselected ones. It runs on launch, activation, wake, successful-check callbacks and a minute heartbeat. Confirmed manual clear does not reset deduplication. While quit/asleep, no process code can run; cleanup catches up afterward.

## Parsing, identity, and resource bounds

Feed IDs are catalog-derived lowercase ASCII letters/digits/hyphens, never arbitrary URLs. TLS uses system validation and redirects are rejected. Responses are capped at 2 MB; parser limits are 512 unique items, 16 levels, 100,000 callbacks, a two-second cooperative callback budget, 4,096-byte titles/GUIDs, 256-byte dates, and 262,144-byte descriptions. DTD/entities, invalid RSS hierarchy, duplicate recognized fields, conflicting GUIDs, and ambiguous nested field markup are rejected. These are cooperative bounds, not immunity to framework defects.

GUID hashes remain stable across prepend/reorder; length-prefixed content hashes handle absent GUIDs. Exact duplicates collapse; conflicting reuse fails closed. Scoped timeline IDs add the feed identity. Description conversion preserves safe block/line structure and decodes bounded entities in a linear scan. It never executes HTML, JavaScript, external resources, shell code, or file paths.

## Storage, catalog, and distribution

Preferences hold selection, cadence, offline-copy choice, notification options, and bounded deduplication state. Optional recent snapshots live in the sandboxed Application Support/CloudBeacon folder; saved-only data is always unconfirmed. Cache corruption/limits fail safely with recovery messaging. Disabling storage clears watched snapshots; removal clears the removed feed's copy. Diagnostic text is sanitized and copied only by explicit user action.

The 5,876-entry catalog snapshot comes from AWS dashboard public metadata, captured November 5, 2026. Runtime prioritizes the catalog in the signed app Resources directory, with SwiftPM/developer fallback. Missing resources expose a fallback notice and only the original feed. Maintainers can refresh through the fixed-source `update-catalog.py` tool and review/test the diff; there is no runtime dashboard script scraping or arbitrary endpoint configuration. Individual feed availability remains an observed per-feed outcome.

App Sandbox permits outbound networking only; hardened runtime remains on. `com.local.awspulse` preserves existing local settings/login/notification identity. Local ad-hoc packaging is not publisher authentication. Developer ID signing, notarization, and clean-Mac checks are required for public binary distribution; credentials remain external to source control.
