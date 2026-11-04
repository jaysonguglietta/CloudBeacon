import Foundation

public struct SavedSnapshot: Codable {
    public let version: Int
    public let checked: Date
    public let items: [FeedItem]
    public init(checked: Date, items: [FeedItem]) { version = 1; self.checked = checked; self.items = items }
}

public final class SnapshotCache {
    private let url: URL
    public init(url: URL) { self.url = url }
    public static func applicationCache() -> SnapshotCache {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudBeacon", isDirectory: true)
        return SnapshotCache(url: folder.appendingPathComponent("last-success.json"))
    }
    public func load() throws -> SavedSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= FeedParser.maximumBytes else { throw FeedError.oversized }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= FeedParser.maximumBytes else { throw FeedError.oversized }
        let saved = try JSONDecoder().decode(SavedSnapshot.self, from: data)
        guard saved.version == 1, saved.items.count <= 512,
              Set(saved.items.map(\.id)).count == saved.items.count,
              saved.items.allSatisfy({ !$0.title.isEmpty && $0.title.utf8.count <= 4096 && $0.id.utf8.count <= 256 && $0.body.utf8.count <= 262144 }) else { throw FeedError.invalid }
        return saved
    }
    public func save(_ snapshot: SavedSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= FeedParser.maximumBytes else { throw FeedError.oversized }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
