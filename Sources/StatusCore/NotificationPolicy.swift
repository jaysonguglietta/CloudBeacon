import Foundation
import CryptoKit

public enum NotificationRetention {
    public static func shouldRemove(feedID: String?, expires: Date?, delivered: Date, selected: Set<String>, now: Date) -> Bool {
        let expiry = expires ?? delivered.addingTimeInterval(RecentWindow.duration)
        return expiry <= now || feedID.map { !selected.contains($0) } == true
    }
}

public struct NotificationLedger: Codable {
    private var baselined: Set<String> = []
    private var seen: [String: Date] = [:]
    public init() {}
    public mutating func retain(feeds: Set<String>, now: Date) {
        baselined.formIntersection(feeds)
        seen = seen.filter { key, expiry in expiry > now && feeds.contains(String(key.split(separator: ":", maxSplits: 1).first ?? "")) }
    }
    public static func identifier(feed: FeedDescriptor, item: FeedItem) -> String {
        let data = try! JSONEncoder().encode([item.id, item.title, item.body, item.date?.ISO8601Format() ?? ""])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return feed.id + ":" + digest
    }
    /// One newest eligible report per feed/check, never a first-fetch history flood.
    public mutating func consume(feed: FeedDescriptor, items: [FeedItem], now: Date, resolutions: Bool) -> FeedItem? {
        seen = seen.filter { $0.value > now }
        let recent = RecentWindow.items(items, now: now).filter { $0.date.map { $0 <= now } ?? false }
        let candidates = recent.filter { item in
            seen[Self.identifier(feed: feed, item: item)] == nil &&
            (item.health(at: now) == .disruption || item.health(at: now) == .degraded || (resolutions && item.health(at: now) == .resolved))
        }
        for item in recent { seen[Self.identifier(feed: feed, item: item)] = item.date!.addingTimeInterval(RecentWindow.duration) }
        if seen.count > 10_240 { seen = Dictionary(uniqueKeysWithValues: seen.sorted { $0.value > $1.value }.prefix(10_240).map { ($0.key, $0.value) }) }
        guard baselined.insert(feed.id).inserted == false else { return nil }
        return candidates.sorted { $0.date! > $1.date! }.first
    }
}
