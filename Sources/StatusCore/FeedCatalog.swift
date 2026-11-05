import Foundation

public struct FeedDescriptor: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let service: String
    public let regionID: String
    public let region: String
    public init(id: String, service: String, regionID: String, region: String) {
        self.id = id; self.service = service; self.regionID = regionID; self.region = region
    }
    public var label: String { "\(service) · \(region) (\(regionID))" }
    public var url: URL { URL(string: "https://status.aws.amazon.com/rss/\(id).rss")! }
    public static let original = FeedDescriptor(id: "multipleservices-me-central-1", service: "Multiple services", regionID: "me-central-1", region: "UAE")
}

public struct FeedCatalog {
    public let feeds: [FeedDescriptor]
    public let fallback: Bool
    public init(feeds: [FeedDescriptor], fallback: Bool = false) {
        self.feeds = feeds.filter { Self.validID($0.id) }; self.fallback = fallback
    }
    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
    public static var bundled: FeedCatalog {
        var url = Bundle.main.url(forResource: "aws-feeds", withExtension: "json")
        if url == nil {
            #if SWIFT_PACKAGE
            url = Bundle.module.url(forResource: "aws-feeds", withExtension: "json")
            #else
            url = URL(fileURLWithPath: "Sources/StatusCore/Resources/aws-feeds.json")
            #endif
        }
        if let url, let data = try? Data(contentsOf: url), data.count <= 2_000_000,
           let feeds = try? JSONDecoder().decode([FeedDescriptor].self, from: data), !feeds.isEmpty,
           Set(feeds.map(\.id)).count == feeds.count, feeds.allSatisfy({ validID($0.id) }) {
            return FeedCatalog(feeds: feeds)
        }
        return FeedCatalog(feeds: [.original], fallback: true)
    }
}

public enum RecentWindow {
    public static let duration: TimeInterval = 24 * 60 * 60
    public static func includes(_ item: FeedItem, now: Date) -> Bool {
        guard let date = item.date else { return false }
        return date >= now.addingTimeInterval(-duration) && date <= now.addingTimeInterval(300)
    }
    public static func items(_ items: [FeedItem], now: Date) -> [FeedItem] { items.filter { includes($0, now: now) } }
}
