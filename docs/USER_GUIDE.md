# CloudBeacon user guide — 1.2

## Choose AWS regions and services

Open CloudBeacon and click **AWS** in the menu bar. Open Settings with the gear button or **⌘,**, then **Choose regions and services**. Select a region (or Global), search service names, and tick the service/region feeds you want. Changing the region filter keeps choices made elsewhere. Expand **Selected feeds** to review/remove them.

**Save watchlist** commits the draft and refreshes. **Cancel** discards it. At most 20 feeds can be selected. Saving no feeds pauses monitoring and displays setup guidance; Refresh is disabled until you choose a feed. Your choices survive restart. Upgrading from the original version defaults to the existing UAE multiple-services feed, not a new selection of other regions.

The catalog is a bundled snapshot from AWS's public dashboard metadata. Not every published feed is guaranteed to remain available. A failed selected feed is shown as unconfirmed; it is not silently dropped from coverage.

## Read the status and timeline

The indicator uses color and shape:

- **Red ×:** a selected feed's latest recent report describes disruption.
- **Amber !:** a selected feed's latest recent report describes degradation.
- **Green ✓:** no reports were published in the last 24 hours, or latest recent selected-feed reports indicate resolution.
- **Gray ?:** coverage is incomplete, stale/offline, saved-only, undated, or otherwise unconfirmed.

Green is scoped to your selected feeds and 24-hour report window. Aging out is not proof that an incident recovered, and a public RSS feed is not account-specific AWS resource health. Known issues take precedence over failed coverage with an explicit warning; otherwise any unconfirmed feed blocks green. Expand **Feed coverage** to inspect each feed's state, reason, and last check. **Status guide** explains the indicator.

Only reliably dated reports within the last 24 hours appear. Older reports age out automatically, including without new network data. Missing/far-future dates block confidence but are not displayed as dated recent reports. Publication times use your Mac's time zone and show its abbreviation.

Search matches titles and descriptions in the current window. Expand a report to read/select its text. Its service and region are shown on the row. Timeline counts are updates, not independently identified incidents. **Open AWS Health** opens a fixed dashboard destination for broader context; if your browser is signed in, AWS may show account-specific views there. CloudBeacon does not read browser credentials.

## Refresh and recover

**Refresh** or **⌘R** checks selected feeds. The cadence is 1, 5, or 15 minutes (default 5), with up to three network requests active. Each feed tracks its own success/retry state. Failed checks retry after 30, 60, 120, 240, then at most 300 seconds. Wake and connectivity recovery can request an additional due check with a short cooldown. A separate freshness heartbeat updates state while the popover is closed or requests are pending.

The footer shows the oldest success across the complete selected scope and the next planned check. Inspect individual coverage if one feed is failing. Previous recent updates remain readable during failure, but unavailable coverage is never counted as confirmed. Check network/date settings for connection/TLS problems; certificate validation remains enabled. Diagnostic previews can help support without exposing raw responses or credentials.

## Enable and manage notifications

In Settings enable **Notify me about new AWS reports**. CloudBeacon requests macOS permission at that time. If denied, choose **Open notification settings**, allow CloudBeacon under System Settings → Notifications, and return. The enabled preference and OS permission are shown separately; the app rechecks permission on activation. Monitoring continues if notifications are denied.

**Include resolution reports** defaults on; **Play notification sound** defaults off. A feed's first successful check establishes a baseline and does not flood you with history. Subsequent new/materially changed reports in the 24-hour window may alert. Each feed/check submits at most one newest eligible report. Fingerprint deduplication survives restart. Turning alerts off stops future submissions; turning them back on establishes a new baseline without replaying existing history.

Alerts identify the service and region. Clicking opens the fixed AWS Health dashboard. macOS controls banner placement, Focus, permission, and actual delivery; a submitted request does not guarantee a visible banner. A failed submission is reported and can retry later without recording a false success.

### Remove older notifications

Delivered CloudBeacon notifications expire 24 hours after **report publication**, not 24 hours after delayed delivery. Cleanup also removes alerts for deselected feeds. It runs on launch, activation, wake, check callbacks, and about once a minute while running. CloudBeacon cannot clean Notification Center while quit/asleep; it catches up when able to run again.

**Clear delivered CloudBeacon notifications** asks for confirmation and clears only this app's delivered notices. It does not reset seen-history or replay old reports. Recent delivered alerts remain when alerts are turned off, until normal expiry or manual clear.

## Other settings and privacy

- **Launch at login:** install one stable copy in Applications. Enable, approve in macOS Login Items if requested, and return. CloudBeacon re-reads actual OS approval/revocation state. Registration failures provide recovery guidance.
- **Remember updates for offline viewing:** off by default. When enabled, each feed saves a bounded, recent snapshot in the app container. Saved-only data is unconfirmed until a live check succeeds. Snapshots are pruned to the time window. Turning remembering off removes watched snapshots; deselecting a feed clears its snapshot. Storage errors are visible and retryable.
- **Clear saved updates:** asks for confirmation. Current in-memory recent updates remain. A later successful check may save a new copy if remembering stays on.
- **Support and sharing:** expanded reports offer **Preview update summary**; Settings offers **Preview support diagnostics**. Review the exact text and choose Copy. Nothing is uploaded. Diagnostics contain public scope, state reasons, app/OS version, and times, not usernames, home paths, AWS credentials, or raw response bodies. Clipboard managers remain outside this app's control.

AWS receives your public IP during feed checks. Notification preferences and bounded hashes/expiry times are stored locally by default; full report bodies are saved only when offline copies are enabled. No analytics, account system, remote push service, or automatic diagnostic upload exists.

## Quit, upgrade, remove

Quit with **⌘Q** or **Quit**. Before upgrading, quit all copies, replace the bundle at the stable Applications location, and confirm the version in Settings. Preserve its bundle identifier to retain settings/login/notification identity. To remove, disable alerts and login launch, clear delivered alerts and saved snapshots, quit, then move the app to Trash. Deleting the bundle alone may leave macOS-owned container preferences.

This is an informational monitor, not guaranteed paging or an availability SLA. See [TESTING.md](TESTING.md) for manual VoiceOver, keyboard, permission, reboot, Focus, sleep/wake, and display checks; automated policy tests do not replace those OS interactions.
