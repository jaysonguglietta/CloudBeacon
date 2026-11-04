import Foundation

@MainActor final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    var elapsed: TimeInterval = 0
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds); elapsed += seconds }
}

final class FixtureFetcher: FeedFetching {
    var data: Data
    var error: Error?
    var count = 0
    var pause = false
    var continuation: CheckedContinuation<Void, Never>?
    init(_ data: Data) { self.data = data }
    func fetch() async throws -> Data {
        count += 1
        if pause { await withCheckedContinuation { continuation = $0 } }
        if let error { throw error }
        return data
    }
}

@main struct ReadinessChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }; count += 1
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let clock = TestClock()
        func item(_ title: String, _ guid: String = "A", date: Date? = nil, body: String = "") -> String {
            "<item><title>\(title)</title><guid>\(guid)</guid><pubDate>\(formatter.string(from: date ?? clock.date))</pubDate><description><![CDATA[\(body)]]></description></item>"
        }
        func feed(_ content: String) -> Data { Data("<rss><channel>\(content)</channel></rss>".utf8) }
        let a = item("Service disruption: A", body: "<p>First paragraph</p><p>Second &amp; third &#x2713;</p>")
        let parsed = try FeedParser.parse(feed(a))
        let prepended = try FeedParser.parse(feed(item("[RESOLVED] B", "B", date: clock.date.addingTimeInterval(60)) + a))
        check(parsed[0].id == prepended[1].id, "Identity stable across prepend")
        check(parsed[0].body == "First paragraph\nSecond & third ✓", "Paragraphs and numeric entities preserved")
        let duplicate = try FeedParser.parse(feed(a + a))
        check(duplicate.count == 1, "Identical GUID duplicates collapsed")
        do { _ = try FeedParser.parse(feed(a + item("[RESOLVED] changed", "A"))); fatalError("Conflicting GUID accepted") }
        catch is FeedError { count += 1 }
        let fallback = "<item><title>Service impact: no GUID</title><pubDate>\(formatter.string(from: clock.date))</pubDate></item>"
        let fallback1 = try FeedParser.parse(feed(fallback))
        let fallback2 = try FeedParser.parse(feed(item("[RESOLVED] Other", "other") + fallback))
        check(fallback1[0].id == fallback2[1].id, "Missing GUID fallback stable")
        let originalDate = clock.date
        let resolved = StatusSnapshot.evaluate(items: prepended, checked: clock.date, stale: false, savedCopy: false, failure: nil, now: clock.date)
        check(resolved.health == .resolved && resolved.reason.contains("does not establish"), "Resolution remains scoped to latest report")
        let undated = FeedItem(id: "undated", title: "[RESOLVED] Unknown date", body: "", date: nil)
        let future = FeedItem(id: "future", title: "[RESOLVED] Future", body: "", date: clock.date.addingTimeInterval(301))
        for items in [[], [undated], [future], parsed + [undated]] {
            let snapshot = StatusSnapshot.evaluate(items: items, checked: clock.date, stale: false, savedCopy: false, failure: nil, now: clock.date)
            check(snapshot.health == .unknown, "Ambiguous input cannot turn green")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cacheURL = folder.appendingPathComponent("snapshot.json")
        let cache = SnapshotCache(url: cacheURL)
        let suite = "CloudBeaconTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(999, forKey: "refreshMinutes")
        let fetcher = FixtureFetcher(feed(a))
        let store = FeedMonitor(fetcher: fetcher, preferences: preferences, cache: cache,
                                wallNow: { clock.date }, elapsedNow: { clock.elapsed })
        check(store.interval == 5 && store.health == .unknown, "Safe defaults")
        await store.poll()
        check(fetcher.count == 1 && store.health == .disruption && !store.stale, "Initial check succeeds")
        check(!FileManager.default.fileExists(atPath: cacheURL.path), "Offline storage opt-in")
        clock.advance(299); await store.poll()
        check(fetcher.count == 1, "No early scheduled request")
        clock.advance(1); await store.poll()
        check(fetcher.count == 2, "Five-minute scheduling")
        store.interval = 1
        clock.advance(60); await store.poll()
        check(fetcher.count == 3, "Changing interval reschedules")
        store.interval = 0
        check(store.interval == 1, "Invalid interval rejected")
        for interval in [5, 15] {
            store.interval = interval
            clock.advance(TimeInterval(interval * 60)); await store.poll()
            check(fetcher.count == (interval == 5 ? 4 : 5), "Every supported interval")
        }
        clock.advance(1800); store.updateFreshness()
        check(store.stale && store.health == .unknown, "Freshness changes without fetching or opening UI")
        await store.recoverAfterWake()
        check(!store.stale && store.health == .disruption, "Wake recovery")
        fetcher.error = URLError(.notConnectedToInternet)
        await store.refresh()
        check(store.failure?.category == "Connection" && store.health == .unknown && store.items == parsed, "Offline retains history and becomes unconfirmed")
        let beforeRetry = fetcher.count
        clock.advance(29); await store.poll()
        check(fetcher.count == beforeRetry, "Backoff minimum")
        clock.advance(1); await store.poll()
        check(fetcher.count == beforeRetry + 1, "First automatic retry")
        check(store.nextCheck == clock.date.addingTimeInterval(60), "Bounded exponential retry")
        fetcher.error = nil
        clock.advance(15); await store.recoverAfterWake()
        check(store.failure == nil && store.health == .disruption, "Reconnect clears error")
        // Wall clock jumps never postpone monotonic scheduling.
        let calls = fetcher.count
        clock.date = .distantPast
        clock.elapsed += 900
        await store.poll()
        check(fetcher.count == calls + 1, "Wall clock changes do not suspend polling")
        clock.date = originalDate
        await store.refresh()
        store.remembersUpdates = true
        let saved = try cache.load()
        check(saved?.items == parsed, "Opt-in saves validated copy")
        let restarted = FeedMonitor(fetcher: fetcher, preferences: preferences, cache: cache,
                                    wallNow: { clock.date }, elapsedNow: { clock.elapsed })
        check(restarted.savedCopy && restarted.items == parsed && restarted.health == .unknown, "Restart cache never looks live")
        await restarted.refresh()
        check(!restarted.savedCopy && restarted.health == .disruption, "Live check replaces saved state")
        store.remembersUpdates = false
        check(!FileManager.default.fileExists(atPath: cacheURL.path), "Disable deletes saved copy")
        store.remembersUpdates = true
        store.clearSavedUpdates()
        check(!FileManager.default.fileExists(atPath: cacheURL.path) && !store.items.isEmpty, "Clear cache preserves current view")
        try Data("corrupt".utf8).write(to: cacheURL)
        let corrupt = FeedMonitor(fetcher: fetcher, preferences: preferences, cache: cache,
                                  wallNow: { clock.date }, elapsedNow: { clock.elapsed })
        check(corrupt.items.isEmpty && corrupt.storageMessage != nil, "Corrupt cache recovers")
        try Data(repeating: 32, count: 2_000_001).write(to: cacheURL)
        do { _ = try cache.load(); fatalError("Oversize cache accepted") } catch is FeedError { count += 1 }
        fetcher.pause = true
        let pending = Task { await store.refresh() }
        while fetcher.continuation == nil { await Task.yield() }
        let inflight = fetcher.count
        await store.refresh()
        check(fetcher.count == inflight && store.loading, "Concurrent refresh suppressed")
        pending.cancel(); fetcher.pause = false; fetcher.continuation?.resume(); fetcher.continuation = nil
        await pending.value
        check(!store.loading, "Cancellation releases refresh guard")
        fetcher.data = feed("")
        await store.refresh()
        check(store.health == .unknown && store.items.isEmpty && store.failure == nil, "Empty success stays unconfirmed")
        fetcher.data = Data("<broken>".utf8)
        await store.refresh()
        check(store.failure?.category == "Unreadable feed", "Parser failure diagnosable")
        check(MonitorFailure.classify(URLError(.timedOut)).category == "Timeout", "Timeout classified")
        check(MonitorFailure.classify(URLError(.serverCertificateUntrusted)).category == "TLS", "TLS remains protected")
        let diagnostics = store.diagnostics(version: "1.1.0 (2)")
        check(diagnostics.contains("1.1.0 (2)") && diagnostics.contains("Unreadable feed"), "Diagnostics describe version and failure")
        check(!diagnostics.contains(NSHomeDirectory()) && !diagnostics.contains("file://"), "Diagnostics omit local paths")
        for _ in 0..<12 { await store.refresh() }
        check(store.outcomes.count == 10, "Diagnostics bounded")
        print("All \(count) readiness checks passed.")
    }
}
