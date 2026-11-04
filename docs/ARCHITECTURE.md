# Architecture and trust boundaries

## Components

- `Sources/StatusCore/Feed.swift`: bounded UTF-8 RSS parsing, safe plain text conversion, stable identity, date handling, and conservative title-prefix inference.
- `Sources/StatusCore/FeedTransport.swift`: fixed-endpoint HTTPS client, ephemeral URLSession, redirect rejection, response/stream limits, cancellation, and no cookies/credential storage.
- `Sources/StatusCore/StatusSnapshot.swift`: one authoritative status interpretation and sanitized error categories.
- `Sources/StatusCore/FeedMonitor.swift`: observable application state, injected transport and wall/elapsed clocks, retry scheduling, published freshness, preferences, bounded diagnostics, and optional snapshot persistence.
- `Sources/StatusCore/SnapshotCache.swift`: versioned JSON snapshot, atomic write, read/size/schema checks, and explicit clear.
- `Sources/AWSStatus/FeedStore.swift`: application delegate and monitoring service. The delegate starts/stops monitoring; neither menu label appearance nor popover visibility owns the polling lifetime. Separate heartbeat and fetch tasks keep freshness observable during requests. Wake and network path changes request bounded recovery.
- `Sources/AWSStatus/SettingsController.swift`: reconciles ServiceManagement state on activation/settings access and exposes version/support metadata.
- `Sources/AWSStatus/AWSStatusApp.swift`: native SwiftUI menu bar label, status guide, lazy history, search, stable expansion state, settings, copy preview, and confirmation UI.
- `Sources/AWSStatus/StatusIcon.swift`: one shared color/symbol presentation with original-color menu bar drawing and non-color state marks.

## State transitions

Launch starts unconfirmed; if opted in, a valid saved snapshot is readable but unconfirmed. A successful fetch parses first, then atomically replaces the visible item collection and records a successful check. Snapshot evaluation returns the latest dated report's inferred health only when freshness, transport outcome, and all publication dates permit it. Any missing/future date blocks a healthy interpretation because ordering cannot be trusted. Resolution refers to the latest report only, never all AWS incidents.

Normal requests follow the selected 1/5/15 minute interval, measured with an elapsed clock derived from `ContinuousClock`. Human-readable times use the wall clock. The normal schedule resets after success. Failed requests preserve items, become unconfirmed, and retry after 30/60/120/240/300 seconds. A successful request resets failure backoff. Manual refresh is available when no request is active; changing the interval explicitly reschedules normal cadence. Wake/reconnect recovery has a 15-second attempt cooldown, and all paths share the single-flight guard.

The monitor's transport and clock are injected in tests. Parser work runs in a cancellation-propagating detached task, while UI state updates remain on the main actor. Network byte accumulation is outside the UI actor. Freshness is republished at a five-second heartbeat. Status never expires from disruption to resolved just because a report is old.

## Stable updates and text safety

Item IDs hash the normalized GUID with SHA-256; no-GUID items hash length-prefixed title, raw date, and body content. A prepend does not change existing identities. Exact duplicate GUID entries are collapsed; conflicting reuse is rejected as ambiguous. Duplicate-free item IDs let expansion survive refresh; items removed from the feed release their expansion state.

Descriptions are rendered as literal Text, never HTML. Bounded linear tag stripping preserves block/line boundaries and unmatched markup; common and numeric entities are decoded without WebKit, resource loading, or script execution. Output is never used as code, a shell argument, a filename, or an outbound URL.

## Limits and storage

Parser: at most 2,000,000 response bytes, 512 unique items, 16 XML levels, 100,000 delegate callbacks, a two-second callback budget, 4,096-byte titles/GUIDs, and 262,144-byte descriptions. DTD/entity declarations, non-RSS roots, duplicate channels, ambiguous nested item fields, and malformed XML are rejected. Input is untrusted even when served by AWS.

Preferences contain refresh interval and the offline-copy choice. Offline content is opt-in and stays in one JSON file under the sandboxed Application Support/CloudBeacon directory. A saved snapshot has schema version 1 and a retrieval timestamp. It is bounded to 2 MB and 512 items; corrupt/unsupported data is discarded with visible recovery guidance. It cannot confer fresh status. In-memory diagnostics retain ten sanitized outcomes. No analytics or automatic uploads exist.

## Boundaries and distribution

Only the fixed HTTPS AWS RSS endpoint is fetched, with system certificate checks. The user-invoked dashboard link is fixed. The app has App Sandbox and outbound networking entitlements; no filesystem expansion, inbound server, AWS keys, tenant boundary, or backend exists.

Local bundles retain `com.local.awspulse` to preserve preferences/login continuity through the CloudBeacon rename. A public release identity is a deliberate deployment decision with migration implications. Ad-hoc signing is local integrity packaging, not publisher authentication. Release mode requires external Developer ID credentials and notarization and fails closed without them.
