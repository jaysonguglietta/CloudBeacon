import Foundation

@main struct LiveCheck {
    @MainActor static func main() async throws {
        let name = "CloudBeacon.LiveCheck.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let monitor = FeedMonitor(preferences: preferences, cache: nil)
        await monitor.refresh()
        guard monitor.failure == nil, monitor.checked != nil else {
            throw NSError(domain: "CloudBeacon.LiveCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: monitor.failure?.message ?? "No successful check"])
        }
        print("Live URLSession → parser → monitor check succeeded.")
        print("\(monitor.items.count) updates · \(monitor.health.label)")
        print(monitor.snapshot.reason)
    }
}
