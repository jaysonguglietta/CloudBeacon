import Foundation
import Combine

/// Application-owned state. The clock and transport are injectable for deterministic tests.
@MainActor public final class FeedMonitor: ObservableObject {
    @Published public private(set) var items: [FeedItem] = []
    @Published public private(set) var loading = false
    @Published public private(set) var failure: MonitorFailure?
    @Published public private(set) var checked: Date?
    @Published public private(set) var lastAttempt: Date?
    @Published public private(set) var nextCheck: Date?
    @Published public private(set) var stale = true
    @Published public private(set) var savedCopy = false
    @Published public private(set) var snapshot = StatusSnapshot(health: .unknown, reason: "Waiting for the first successful check.")
    @Published public private(set) var outcomes: [CheckOutcome] = []
    @Published public private(set) var storageMessage: String?
    @Published public var interval: Int {
        didSet {
            guard [1, 5, 15].contains(interval) else { interval = oldValue; return }
            preferences.set(interval, forKey: "refreshMinutes")
            due = lastAttemptElapsed.map { $0 + Double(interval * 60) } ?? elapsedNow()
            updateFreshness()
        }
    }
    @Published public var remembersUpdates: Bool {
        didSet {
            preferences.set(remembersUpdates, forKey: "rememberUpdates")
            if remembersUpdates { saveSnapshot() } else { clearSavedUpdates() }
        }
    }
    private let fetcher: FeedFetching
    private let preferences: UserDefaults
    private let cache: SnapshotCache?
    private let wallNow: () -> Date
    private let elapsedNow: () -> TimeInterval
    private var due: TimeInterval
    private var lastAttemptElapsed: TimeInterval?
    private var successElapsed: TimeInterval?
    private var failures = 0
    private var sourceItems: [FeedItem] = []
    public var isDue: Bool { elapsedNow() >= due }
    public var health: Health { snapshot.health }
    public var error: String? { failure?.message }

    public init(fetcher: FeedFetching = FeedHTTPClient(), preferences: UserDefaults = .standard,
                cache: SnapshotCache? = SnapshotCache.applicationCache(),
                wallNow: @escaping () -> Date = Date.init,
                elapsedNow: (() -> TimeInterval)? = nil) {
        self.fetcher = fetcher; self.preferences = preferences; self.cache = cache; self.wallNow = wallNow
        let origin = ContinuousClock.now
        self.elapsedNow = elapsedNow ?? {
            let duration = origin.duration(to: ContinuousClock.now).components
            return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        }
        due = self.elapsedNow()
        let savedInterval = preferences.integer(forKey: "refreshMinutes")
        interval = [1, 5, 15].contains(savedInterval) ? savedInterval : 5
        remembersUpdates = preferences.bool(forKey: "rememberUpdates")
        if remembersUpdates {
            do {
                if let saved = try cache?.load() {
                    sourceItems = saved.items; items = saved.items; checked = saved.checked; savedCopy = true
                }
            } catch {
                storageMessage = "The saved copy could not be read. Refresh to download a new copy."
                try? cache?.clear()
            }
        }
        updateFreshness()
    }

    public func updateFreshness() {
        stale = successElapsed.map { elapsedNow() - $0 >= Double(interval * 120) } ?? true
        nextCheck = wallNow().addingTimeInterval(max(0, due - elapsedNow()))
        let recent = RecentWindow.items(sourceItems, now: wallNow())
        if recent != items {
            items = recent
            if remembersUpdates, let checked {
                do { try cache?.save(SavedSnapshot(checked: checked, items: recent)) }
                catch { storageMessage = "Couldn’t prune the saved copy. Live monitoring continues; try clearing saved updates." }
            }
        }
        snapshot = .evaluate(items: sourceItems, checked: checked, stale: stale, savedCopy: savedCopy, failure: failure?.message, now: wallNow())
    }

    public func poll() async {
        updateFreshness()
        if elapsedNow() >= due { await refresh() }
    }

    public func recoverAfterWake() async {
        updateFreshness()
        guard lastAttemptElapsed.map({ elapsedNow() - $0 >= 15 }) ?? true else { return }
        if failure != nil || stale || elapsedNow() >= due { await refresh() }
    }

    public func refresh() async {
        guard !loading else { return }
        loading = true
        lastAttempt = wallNow(); lastAttemptElapsed = elapsedNow()
        defer { loading = false; updateFreshness() }
        do {
            let data = try await fetcher.fetch()
            let task = Task.detached { try FeedParser.parse(data) }
            let parsed = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            sourceItems = parsed; items = RecentWindow.items(parsed, now: wallNow()); checked = wallNow(); successElapsed = elapsedNow()
            savedCopy = false; failure = nil; failures = 0
            due = elapsedNow() + Double(interval * 60)
            record("Success · \(parsed.count) updates")
            if remembersUpdates { saveSnapshot() }
        } catch is CancellationError {
            due = elapsedNow() + 30
            record("Cancelled · retry scheduled")
        } catch {
            failure = .classify(error)
            failures = min(failures + 1, 5)
            due = elapsedNow() + min(300, 30 * pow(2, Double(failures - 1)))
            record(failure!.category)
        }
    }

    private func record(_ summary: String) {
        outcomes.insert(CheckOutcome(date: wallNow(), summary: summary), at: 0)
        outcomes = Array(outcomes.prefix(10))
    }
    private func saveSnapshot() {
        guard let checked, !savedCopy else { return }
        do { try cache?.save(SavedSnapshot(checked: checked, items: items)); storageMessage = nil }
        catch { storageMessage = "Couldn’t save the offline copy. Live monitoring continues; try disabling and enabling saved updates." }
    }
    public func clearSavedUpdates() {
        do { try cache?.clear(); storageMessage = "Saved updates cleared. The current in-memory view is unchanged." }
        catch { storageMessage = "Couldn’t clear saved updates. Try again or check app-container permissions." }
    }
    public func diagnostics(version: String) -> String {
        let format: (Date?) -> String = { $0?.ISO8601Format() ?? "Never" }
        let recent = outcomes.map { "\($0.date.ISO8601Format()) · \($0.summary)" }.joined(separator: "\n")
        return """
        CloudBeacon \(version)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Scope: public AWS Multiple services · UAE · me-central-1
        Source: https://status.aws.amazon.com/rss/multipleservices-me-central-1.rss
        State: \(snapshot.health.label)
        Reason: \(snapshot.reason)
        Last attempt: \(format(lastAttempt))
        Last success: \(format(checked))
        Next check: \(format(nextCheck))
        Refresh interval: \(interval) minutes
        Saved copy in use: \(savedCopy ? "Yes" : "No")
        Recent checks (memory only):
        \(recent.isEmpty ? "None" : recent)
        """
    }
}
