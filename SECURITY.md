# Security policy

CloudBeacon reads selected public AWS service/region RSS feeds from a bundled validated catalog. It does not accept AWS credentials or host a server. Its public-report indicator is not an availability guarantee or a substitute for account-specific monitoring.

## Reporting

Do not post secrets, personal data, or exploit details that would endanger users in a public issue. Contact the repository owner privately; if GitHub private vulnerability reporting is enabled, use the repository's Security → Report a vulnerability flow. That feature's availability is not assumed by this document.

Include the affected commit/version, OS, a minimal safe reproduction/fixture, observed impact, and proposed mitigation if available. Do not test against AWS infrastructure or other people's systems without authorization.

## Controls and release requirements

- Fixed HTTPS host and validated RSS feed identifiers with normal system certificate validation and rejected redirects.
- Ephemeral networking with bounded response/stream sizes, timeouts, and cancellation.
- Bounded parser depth, items, fields, callbacks, and time; no DTD/external entities.
- Literal text rendering, stable hashed identities, and no feed-provided executable actions or destinations.
- App Sandbox with outbound networking only; hardened runtime.
- Offline content is optional and bounded; diagnostics are sanitized and copied only by user action.
- Local signing is ad-hoc. Authenticated public distribution requires Developer ID signing and notarization; release mode fails without credentials.

See [architecture](docs/ARCHITECTURE.md), [testing](docs/TESTING.md), [release guide](docs/RELEASING.md), and [remediation status](docs/REMEDIATION.md). The original [review](SECURITY_REVIEW.md) is a historical snapshot, not a claim that all listed issues still exist or that all runtime paths have been certified.

Version 1.2 adds a bounded watchlist, native user-authorized notifications, and locally persisted hashed deduplication metadata. No arbitrary URLs or remote push service are accepted. Every feed retains transport/parser limits; aggregate coverage cannot hide failed checks behind green. Notification Center cleanup is limited to this app’s notices and runs only while the process can execute.
