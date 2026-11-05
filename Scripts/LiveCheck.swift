import Foundation

@main struct LiveCheck {
    @MainActor static func main() async throws {
        let name = "CloudBeacon.LiveCheck.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        for id in [FeedDescriptor.original.id, "ec2-us-east-1", "s3-us-west-2"] {
            let monitor = FeedMonitor(fetcher: FeedHTTPClient(feedID: id), preferences: preferences, cache: nil)
            await monitor.refresh()
            guard monitor.failure == nil, monitor.checked != nil else {
                throw NSError(domain: "CloudBeacon.LiveCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: monitor.failure?.message ?? "No successful check"])
            }
            print("\(id): live transport → parser → monitor succeeded; \(monitor.items.count) reports in last 24 hours; \(monitor.health.label)")
        }
    }
}
