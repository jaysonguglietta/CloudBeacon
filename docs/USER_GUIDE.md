# CloudBeacon user guide

## Start and inspect a report

Open CloudBeacon and look for **AWS** beside a small status light in the menu bar. Click it to open the popover. The header identifies the watched UAE region and explains the current result. Expand **Status guide** for the red ×, amber !, green ✓, and gray ? meanings.

Expand a timeline update to read its complete description. Publication times use your Mac's time zone and include the zone abbreviation. Search matches titles and descriptions. Clear the search to restore all current-feed updates. The timeline contains updates, not independently counted incidents.

Green means the latest report says its issue was resolved. It does not prove all services are healthy. Unknown titles, missing/future dates, stale checks, empty responses, saved copies, or failed requests remain gray. An old disruption stays a warning until the feed provides newer evidence; time alone does not resolve it.

Choose **Open AWS Health** for broader context. The fixed dashboard link may open an account-specific view if your browser is already signed in. CloudBeacon never reads those browser credentials or account events.

## Refresh and recover

**Refresh** or **⌘R** starts a check. While a request is active, Refresh is disabled; no overlapping request is started. The footer shows the last successful check with its date and time zone, and the next scheduled check.

After failure, earlier updates remain readable and the status becomes unconfirmed. Automatic retries back off from 30 seconds to a maximum of five minutes. A successful request clears the error. Wake and a connectivity transition can trigger a recovery check, with a short cooldown to prevent a request burst. A freshness heartbeat runs independently of the popover and pending fetches.

If gray persists, read the reason in the header. Check connectivity and your Mac's date for TLS problems; certificate validation remains enabled. Open AWS Health to corroborate the report. If needed, copy support diagnostics from Settings.

## Settings

Click the gear button or use **⌘,**.

- **Check every:** choose 1, 5, or 15 minutes. Your choice survives restart. Changing it reschedules the next normal check.
- **Launch at login:** enable only after installing one stable copy in Applications. If macOS requires approval, use **Open Login Items settings**, approve CloudBeacon, and return. The app re-reads OS state on activation and settings opening. Registration errors explain how to recover.
- **Remember updates for offline viewing:** off by default. When enabled, the latest successful snapshot is stored in the app container. Offline launch marks it **Saved copy**, always gray until a live check succeeds. Turning the option off deletes the saved snapshot if possible; any storage error is displayed. **Clear saved updates** is available to retry deletion and asks for confirmation. Clearing does not erase currently displayed in-memory updates. If remembering remains enabled, the next success may save a new copy.

## Copy an update or support diagnostics

Within an expanded update, select **Preview update summary**. Settings offers **Preview support diagnostics**. Read the preview, then choose **Copy to clipboard**. Nothing is uploaded or sent to anyone. Copy success/failure is shown in the popover. Close the preview when done.

Diagnostics include public feed scope, app/OS version, state reason, last attempt/success, next check, and up to ten sanitized outcomes held in memory. They intentionally omit your username, home directory, credentials, and raw network response bodies. Clipboard content remains subject to your normal system/clipboard-manager behavior.

## Stop, upgrade, or remove

**Quit** or **⌘Q** stops monitoring. Before upgrading, quit all copies, replace the app at its stable Applications location, and verify the version in Settings. Preserve the bundle identifier when building upgrades; renaming its display name does not require a new identifier.

To remove: disable login launch, turn off remembered updates and confirm any storage error is resolved, quit, then move the app to Trash. Deleting the bundle alone may leave sandbox preferences; macOS owns those container files. If you need to remove them manually, first make sure they belong to this app and no app instance is running.

CloudBeacon's core workflows support native buttons, disclosures, search, and keyboard shortcuts. VoiceOver, grayscale distinctions, enlarged text, small-screen layouts, and login behavior still require the manual acceptance checks documented in [TESTING.md](TESTING.md); their presence in code is not a claim that all configurations have been exercised.
