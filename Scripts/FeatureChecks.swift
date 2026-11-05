import Foundation

actor ConcurrencyMeter {
    var active = 0
    var maximum = 0
    var cancelled = 0
    func enter() { active += 1; maximum = max(maximum, active) }
    func leave(cancelled: Bool = false) { active -= 1; if cancelled { self.cancelled += 1 } }
}
final class WatchFixture: FeedFetching {
    var data: Data
    var error: Error?
    var delay: Duration = .milliseconds(20)
    let meter: ConcurrencyMeter
    init(data: Data, meter: ConcurrencyMeter) { self.data = data; self.meter = meter }
    func fetch() async throws -> Data {
        await meter.enter()
        do { try await Task.sleep(for: delay) }
        catch { await meter.leave(cancelled: true); throw error }
        await meter.leave()
        if let error { throw error }
        return data
    }
}

@main struct FeatureChecks {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }; checks += 1
        }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var elapsed: TimeInterval = 0
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        func data(_ title: String, date: Date? = nil) -> Data {
            Data("<rss><channel><item><title>\(title)</title><guid>\(title)</guid><pubDate>\(formatter.string(from: date ?? now))</pubDate></item></channel></rss>".utf8)
        }
        let catalog = FeedCatalog.bundled
        check(!catalog.fallback && catalog.feeds.count > 5000, "Bundled catalog loads")
        check(catalog.feeds.contains(.original), "Original watch survives migration")
        check(catalog.feeds.contains { $0.id == "ec2-us-east-1" }, "Real EC2 feed")
        check(catalog.feeds.contains { $0.id == "s3-us-west-2" }, "Real S3 feed")
        for bad in ["../etc", "https://evil.test/x", "a?b", "x/y", "", String(repeating: "a", count: 129)] {
            check(!FeedCatalog.validID(bad), "Reject arbitrary destination/path")
        }
        let fresh = FeedItem(id: "fresh", title: "Service disruption: New", body: "Update", date: now)
        let old = FeedItem(id: "old", title: "Service disruption: Old", body: "", date: now.addingTimeInterval(-86401))
        let boundary = FeedItem(id: "edge", title: "Service impact: Edge", body: "", date: now.addingTimeInterval(-86400))
        let future = FeedItem(id: "future", title: "Service impact: Future", body: "", date: now.addingTimeInterval(301))
        check(RecentWindow.items([old, boundary, fresh, future], now: now).map(\.id) == ["edge", "fresh"], "Exact 24-hour window")
        let aged = StatusSnapshot.evaluate(items: [old], checked: now, stale: false, savedCopy: false, failure: nil, now: now)
        check(aged.health == .quiet && aged.reason.contains("not confirmation"), "Age-out does not claim recovery")
        var ledger = NotificationLedger()
        let feed = FeedDescriptor.original
        check(ledger.consume(feed: feed, items: [old, fresh], now: now, resolutions: true) == nil, "First check baselines history")
        check(ledger.consume(feed: feed, items: [fresh], now: now, resolutions: true) == nil, "Same report never repeated")
        let updated = FeedItem(id: fresh.id, title: fresh.title, body: "Changed body", date: now)
        check(ledger.consume(feed: feed, items: [updated], now: now, resolutions: true) == updated, "Changed report can notify")
        check(ledger.consume(feed: feed, items: [updated], now: now, resolutions: true) == nil, "Changed report deduplicated")
        let encoded = try JSONEncoder().encode(ledger)
        var restarted = try JSONDecoder().decode(NotificationLedger.self, from: encoded)
        check(restarted.consume(feed: feed, items: [updated], now: now, resolutions: true) == nil, "Restart deduplication")
        let resolved = FeedItem(id: "resolved", title: "[RESOLVED] New", body: "", date: now)
        check(restarted.consume(feed: feed, items: [resolved], now: now, resolutions: false) == nil, "Resolution preference respected")
        check(restarted.consume(feed: feed, items: [old, future], now: now, resolutions: true) == nil, "Old/future reports never notify")
        let selected: Set<String> = [feed.id]
        check(NotificationRetention.shouldRemove(feedID: feed.id, expires: now, delivered: now, selected: selected, now: now), "Delivered report expires at publication +24h")
        check(NotificationRetention.shouldRemove(feedID: "removed", expires: now.addingTimeInterval(10), delivered: now, selected: selected, now: now), "Deselected feed cleanup")
        check(!NotificationRetention.shouldRemove(feedID: feed.id, expires: now.addingTimeInterval(1), delivered: now, selected: selected, now: now), "Recent notification retained")
        check(NotificationRetention.shouldRemove(feedID: nil, expires: nil, delivered: now.addingTimeInterval(-86401), selected: selected, now: now), "Legacy notifications expire safely")
        let suite = "CloudBeacon.FeatureChecks.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let meter = ConcurrencyMeter()
        var cacheNow = now
        var cacheElapsed: TimeInterval = 0
        let cacheFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = SnapshotCache(url: cacheFolder.appendingPathComponent("snapshot.json"))
        defer { try? FileManager.default.removeItem(at: cacheFolder) }
        let cacheMonitor = FeedMonitor(fetcher: WatchFixture(data: data("Service disruption: Cached"), meter: meter), preferences: preferences, cache: cache,
                                       wallNow: { cacheNow }, elapsedNow: { cacheElapsed })
        await cacheMonitor.refresh()
        cacheMonitor.remembersUpdates = true
        let beforeExpiry = try cache.load()
        check(beforeExpiry?.items.count == 1, "Recent report saved when opted in")
        cacheNow.addTimeInterval(86401); cacheElapsed += 86401
        cacheMonitor.updateFreshness()
        let afterExpiry = try cache.load()
        check(cacheMonitor.items.isEmpty && afterExpiry?.items.isEmpty == true, "Heartbeat prunes expired saved reports")
        cacheMonitor.remembersUpdates = false
        let feeds = (0..<25).map { FeedDescriptor(id: "test-\($0)", service: "Service \($0)", regionID: "us-east-1", region: "N. Virginia") }
        let testCatalog = FeedCatalog(feeds: feeds)
        var fixtures: [String: WatchFixture] = [:]
        for feed in feeds { fixtures[feed.id] = WatchFixture(data: Data("<rss><channel/></rss>".utf8), meter: meter) }
        fixtures["test-0"]!.data = data("Service disruption: New")
        fixtures["test-1"]!.data = data("[RESOLVED] Other")
        fixtures["test-2"]!.data = data("Service disruption: Old", date: now.addingTimeInterval(-86401))
        fixtures["test-4"]!.error = URLError(.notConnectedToInternet)
        preferences.set(Array(feeds.prefix(5).map(\.id)), forKey: "watchedFeedIDs")
        let factory: (FeedDescriptor) -> FeedMonitor = { feed in
            FeedMonitor(fetcher: fixtures[feed.id]!, preferences: preferences, cache: nil,
                        wallNow: { now }, elapsedNow: { elapsed })
        }
        let watch = WatchStore(catalog: testCatalog, preferences: preferences, wallNow: { now }, factory: factory)
        await watch.refresh()
        let maximum = await meter.maximum
        check(maximum <= 3 && maximum > 1, "Bounded parallel polling")
        check(watch.health == .disruption && watch.snapshot.reason.contains("incomplete"), "Issues take priority without hiding failed coverage")
        check(watch.reports.count == 2 && watch.coverage.count == 5, "Old reports hidden, feed coverage retained")
        check(Set(watch.reports.map(\.id)).count == watch.reports.count, "Scoped report IDs unique")
        fixtures["test-4"]!.error = nil
        await watch.refresh()
        check(watch.coverage.allSatisfy { $0.snapshot.health != .unknown }, "One feed recovers independently")
        fixtures["test-0"]!.data = data("Service disruption: Old", date: now.addingTimeInterval(-86401))
        await watch.refresh()
        check(watch.health == .resolved, "Quiet feeds and recent resolution aggregate")
        fixtures["test-1"]!.data = Data("<rss><channel/></rss>".utf8)
        await watch.refresh()
        check(watch.health == .quiet && watch.reports.isEmpty, "Successful feeds with no recent reports are quiet")
        fixtures["test-4"]!.error = URLError(.timedOut)
        await watch.refresh()
        check(watch.health == .unknown, "Missing coverage cannot yield green")
        try watch.select(["test-0"])
        check(preferences.stringArray(forKey: "watchedFeedIDs") == ["test-0"], "Selection persists")
        let restored = WatchStore(catalog: testCatalog, preferences: preferences, wallNow: { now }, factory: factory)
        check(restored.selectedIDs == ["test-0"], "Watchlist restored")
        do { try watch.select(Set(feeds.prefix(21).map(\.id))); fatalError("Selection overflow accepted") } catch is FeedError { checks += 1 }
        do { try watch.select(["evil"]); fatalError("Unknown feed accepted") } catch is FeedError { checks += 1 }
        fixtures["test-0"]!.data = data("Service disruption: New")
        await watch.refresh()
        check(watch.reports.count == 1, "Recent selected report visible")
        now.addTimeInterval(86401); elapsed += 86401
        watch.updateFreshness()
        check(watch.reports.isEmpty, "Heartbeat ages out reports without a new fetch")
        fixtures["test-0"]!.delay = .seconds(10)
        let pending = Task { await watch.refresh() }
        while await meter.active == 0 { await Task.yield() }
        try watch.select([])
        await pending.value
        check(watch.reports.isEmpty && watch.coverage.isEmpty && watch.health == .unknown && !watch.loading, "Removed in-flight results cannot reappear")
        let cancelled = await meter.cancelled
        check(cancelled > 0, "Watchlist change cancels networking")
        let emptyRestored = WatchStore(catalog: testCatalog, preferences: preferences, wallNow: { now }, factory: factory)
        check(emptyRestored.feeds.isEmpty, "Deliberately empty watchlist survives restart")
        ledger.retain(feeds: [], now: now)
        let readded = FeedItem(id: "readded", title: "Service disruption: Readded", body: "", date: now)
        check(ledger.consume(feed: feed, items: [readded], now: now, resolutions: true) == nil, "Removed feed re-add baselines again")
        print("All \(checks) watchlist/notification/window checks passed.")
    }
}
