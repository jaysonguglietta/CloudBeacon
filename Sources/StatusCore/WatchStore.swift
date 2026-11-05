import Foundation
import Combine

public struct ScopedReport: Identifiable, Equatable {
    public let feed: FeedDescriptor
    public let item: FeedItem
    public var id: String { feed.id + ":" + item.id }
}

public struct FeedCoverage: Identifiable {
    public let feed: FeedDescriptor
    public let snapshot: StatusSnapshot
    public let checked: Date?
    public var id: String { feed.id }
}

@MainActor public final class WatchStore: ObservableObject {
    public static let maximumFeeds = 20
    public let catalog: FeedCatalog
    @Published public private(set) var feeds: [FeedDescriptor] = []
    @Published public private(set) var reports: [ScopedReport] = []
    @Published public private(set) var coverage: [FeedCoverage] = []
    @Published public private(set) var loading = false
    @Published public private(set) var snapshot = StatusSnapshot(health: .unknown, reason: "Waiting for a check.")
    @Published public private(set) var checked: Date?
    @Published public private(set) var nextCheck: Date?
    @Published public private(set) var storageMessage: String?
    @Published public var interval: Int {
        didSet {
            guard [1, 5, 15].contains(interval) else { interval = oldValue; return }
            preferences.set(interval, forKey: "refreshMinutes")
            for monitor in monitors.values { monitor.interval = interval }
            updateFreshness()
        }
    }
    @Published public var remembersUpdates: Bool {
        didSet {
            preferences.set(remembersUpdates, forKey: "rememberUpdates")
            for monitor in monitors.values { monitor.remembersUpdates = remembersUpdates }
            rebuild()
        }
    }
    public var health: Health { snapshot.health }
    public var scopeLabel: String { "\(feeds.count) service/region \(feeds.count == 1 ? "feed" : "feeds") · last 24 hours" }
    public var selectedIDs: Set<String> { Set(feeds.map(\.id)) }
    public var onSuccessfulCheck: ((FeedDescriptor, [FeedItem]) -> Void)?
    private let preferences: UserDefaults
    private let factory: (FeedDescriptor) -> FeedMonitor
    private let wallNow: () -> Date
    private var monitors: [String: FeedMonitor] = [:]
    private var generation = 0
    private var batch: Task<Void, Never>?

    public init(catalog: FeedCatalog = .bundled, preferences: UserDefaults = .standard,
                wallNow: @escaping () -> Date = Date.init,
                factory: ((FeedDescriptor) -> FeedMonitor)? = nil) {
        self.catalog = catalog; self.preferences = preferences; self.wallNow = wallNow
        self.factory = factory ?? { feed in
            FeedMonitor(fetcher: FeedHTTPClient(feedID: feed.id), preferences: preferences,
                        cache: SnapshotCache.applicationCache(feedID: feed.id), wallNow: wallNow)
        }
        let savedInterval = preferences.integer(forKey: "refreshMinutes")
        interval = [1, 5, 15].contains(savedInterval) ? savedInterval : 5
        remembersUpdates = preferences.bool(forKey: "rememberUpdates")
        let ids = preferences.stringArray(forKey: "watchedFeedIDs") ?? [FeedDescriptor.original.id]
        let allowed = Set(ids.prefix(Self.maximumFeeds))
        feeds = catalog.feeds.filter { allowed.contains($0.id) }.sorted { $0.label < $1.label }
        for feed in feeds { monitors[feed.id] = self.factory(feed) }
        rebuild()
    }

    public func select(_ ids: Set<String>) throws {
        guard ids.count <= Self.maximumFeeds, ids.isSubset(of: Set(catalog.feeds.map(\.id))) else { throw FeedError.rejected }
        guard ids != selectedIDs else { return }
        generation += 1; batch?.cancel(); batch = nil; loading = false
        // Each batch has its own monitor generation; removed/old results cannot reappear.
        let removed = feeds.filter { !ids.contains($0.id) }
        for feed in removed { monitors[feed.id]?.clearSavedUpdates() }
        preferences.set(ids.sorted(), forKey: "watchedFeedIDs")
        feeds = catalog.feeds.filter { ids.contains($0.id) }.sorted { $0.label < $1.label }
        monitors = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, factory($0)) })
        rebuild()
    }

    public func updateFreshness() {
        for monitor in monitors.values { monitor.updateFreshness() }
        rebuild()
    }
    public func poll() async {
        updateFreshness()
        if monitors.values.contains(where: { $0.isDue }) { await run(manual: false) }
    }
    public func refresh() async { await run(manual: true) }
    public func recoverAfterWake() async {
        updateFreshness()
        await run(manual: false, recovering: true)
    }
    public func stop() { batch?.cancel() }

    private func run(manual: Bool, recovering: Bool = false) async {
        guard !loading, !feeds.isEmpty else { return }
        loading = true
        let version = generation
        let work = feeds.compactMap { feed -> (FeedDescriptor, FeedMonitor)? in
            guard let monitor = monitors[feed.id], manual || recovering || monitor.isDue else { return nil }
            return (feed, monitor)
        }
        let task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                var iterator = work.makeIterator()
                func enqueue(_ pair: (FeedDescriptor, FeedMonitor)) {
                    group.addTask { [weak self] in
                        guard !Task.isCancelled else { return }
                        if recovering { await pair.1.recoverAfterWake() }
                        else if manual { await pair.1.refresh() }
                        else { await pair.1.poll() }
                        guard !Task.isCancelled else { return }
                        await self?.completed(pair.0, monitor: pair.1, version: version)
                    }
                }
                for _ in 0..<3 { if let pair = iterator.next() { enqueue(pair) } }
                while await group.next() != nil {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let pair = iterator.next() { enqueue(pair) }
                }
            }
        }
        batch = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard generation == version else { return }
        loading = false; batch = nil; rebuild()
    }

    private func completed(_ feed: FeedDescriptor, monitor: FeedMonitor, version: Int) {
        guard generation == version else { return }
        rebuild()
        if monitor.failure == nil, monitor.checked != nil, !monitor.savedCopy, !monitor.stale {
            onSuccessfulCheck?(feed, monitor.items)
        }
    }

    private func rebuild() {
        coverage = feeds.compactMap { feed in monitors[feed.id].map { FeedCoverage(feed: feed, snapshot: $0.snapshot, checked: $0.checked) } }
        var recent: [ScopedReport] = []
        for feed in feeds {
            for item in monitors[feed.id]?.items ?? [] where RecentWindow.includes(item, now: wallNow()) {
                recent.append(ScopedReport(feed: feed, item: item))
            }
        }
        reports = recent.sorted { left, right in
            let first = left.item.date ?? .distantPast
            let second = right.item.date ?? .distantPast
            return first == second ? left.id < right.id : first > second
        }
        checked = coverage.allSatisfy { $0.checked != nil } ? coverage.compactMap(\.checked).min() : nil
        nextCheck = monitors.values.compactMap(\.nextCheck).min()
        storageMessage = monitors.values.compactMap(\.storageMessage).first
        guard !feeds.isEmpty else {
            snapshot = .init(health: .unknown, reason: "No feeds selected. Open Settings → Monitored feeds to choose regions and services."); return
        }
        let unknown = coverage.filter { $0.snapshot.health == .unknown }.count
        let suffix = unknown > 0 ? " \(unknown) of \(feeds.count) feeds are unconfirmed; coverage is incomplete." : ""
        if coverage.contains(where: { $0.snapshot.health == .disruption }) {
            snapshot = .init(health: .disruption, reason: "A selected feed reports disruption within the last 24 hours." + suffix)
        } else if coverage.contains(where: { $0.snapshot.health == .degraded }) {
            snapshot = .init(health: .degraded, reason: "A selected feed reports degradation within the last 24 hours." + suffix)
        } else if unknown > 0 {
            snapshot = .init(health: .unknown, reason: "\(unknown) of \(feeds.count) selected feeds are unconfirmed. Expand Feed coverage for the reason.")
        } else if reports.isEmpty {
            snapshot = .init(health: .quiet, reason: "No reports in the last 24 hours across your selected feeds. Older reports are hidden; this is not proof that older issues recovered.")
        } else {
            snapshot = .init(health: .resolved, reason: "The latest recent reports in the selected feeds indicate resolution. This is not an AWS-wide or account-specific all-clear.")
        }
    }

    public func clearSavedUpdates() {
        for monitor in monitors.values { monitor.clearSavedUpdates() }
        rebuild()
    }
    public func diagnostics(version: String) -> String {
        let rows = coverage.map { "\($0.feed.label): \($0.snapshot.health.label). \($0.snapshot.reason)" }.joined(separator: "\n")
        return "CloudBeacon \(version)\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nWindow: last 24 hours\nScope: \(scopeLabel)\nState: \(health.label)\n\(snapshot.reason)\nRefresh: \(interval) minutes\nLast full coverage success: \(checked?.ISO8601Format() ?? "Never")\n\n\(rows)"
    }
}
