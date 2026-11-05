import AppKit
import Combine
import UserNotifications
import StatusCore

@MainActor final class NotificationController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var enabled: Bool
    @Published private(set) var authorization = "Checking macOS notification permission…"
    @Published private(set) var allowed = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published var resolutions: Bool { didSet { preferences.set(resolutions, forKey: "notifyResolutions") } }
    @Published var sound: Bool { didSet { preferences.set(sound, forKey: "notificationSound") } }
    private let center = UNUserNotificationCenter.current()
    private let preferences: UserDefaults
    private let store: WatchStore
    private var ledger: NotificationLedger
    private var tail: Task<Void, Never>?
    private var activation: AnyCancellable?
    private var lastPersisted: Data?

    init(store: WatchStore, preferences: UserDefaults = .standard) {
        self.store = store; self.preferences = preferences
        enabled = preferences.bool(forKey: "notificationsEnabled")
        resolutions = preferences.object(forKey: "notifyResolutions") as? Bool ?? true
        sound = preferences.bool(forKey: "notificationSound")
        if let data = preferences.data(forKey: "notificationLedger"), data.count <= 2_000_000,
           let saved = try? JSONDecoder().decode(NotificationLedger.self, from: data) { ledger = saved }
        else { ledger = NotificationLedger() }
        super.init()
        center.delegate = self
        store.onSuccessfulCheck = { [weak self] feed, items in self?.enqueue(feed, items: items) }
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { @MainActor in await self?.reconcile(); await self?.cleanup() } }
        Task { await reconcile(); await cleanup() }
    }
    func reconcile() async {
        let settings = await center.notificationSettings()
        allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        switch settings.authorizationStatus {
        case .notDetermined: authorization = "Enable notifications to request permission from macOS."
        case .denied: authorization = "Blocked by macOS. Allow CloudBeacon in System Settings → Notifications, then return here."
        case .authorized, .provisional: authorization = "Allowed by macOS. Focus and notification settings control when banners appear."
        @unknown default: authorization = "Permission status is unavailable. Check System Settings → Notifications."
        }
    }
    func setEnabled(_ value: Bool) {
        guard !busy else { return }
        if !value {
            enabled = false; preferences.set(false, forKey: "notificationsEnabled")
            center.removeAllPendingNotificationRequests(); return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                await reconcile()
                enabled = true; preferences.set(true, forKey: "notificationsEnabled")
                ledger = NotificationLedger()
                // Baseline currently loaded feeds; first successful check baselines others.
                for feed in store.feeds {
                    let items = store.reports.filter { $0.feed.id == feed.id }.map(\.item)
                    if store.coverage.first(where: { $0.id == feed.id })?.checked != nil {
                        _ = ledger.consume(feed: feed, items: items, now: Date(), resolutions: resolutions)
                    }
                }
                persist()
                message = allowed ? "Enabled. New reports will alert; existing history is not replayed." : "Enabled in CloudBeacon, but macOS permission must be allowed before banners can appear."
            } catch { message = "Couldn’t request notification permission. Check System Settings → Notifications and try again." }
        }
    }
    private func enqueue(_ feed: FeedDescriptor, items: [FeedItem]) {
        let previous = tail
        tail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await process(feed, items: items)
        }
    }
    private func process(_ feed: FeedDescriptor, items: [FeedItem]) async {
        await cleanup()
        guard enabled, allowed, store.selectedIDs.contains(feed.id) else { return }
        var updated = ledger
        guard let item = updated.consume(feed: feed, items: items, now: Date(), resolutions: resolutions) else {
            ledger = updated; persist(); return
        }
        guard !Task.isCancelled, enabled, store.selectedIDs.contains(feed.id), RecentWindow.includes(item, now: Date()) else { return }
        let content = UNMutableNotificationContent()
        content.title = "AWS · \(feed.service)"
        content.subtitle = "\(feed.region) · \(feed.regionID)"
        content.body = String(item.title.prefix(300)) + "\nOpen to view AWS Health."
        content.threadIdentifier = feed.id
        if sound { content.sound = .default }
        content.userInfo = ["cloudbeacon.feedID": feed.id,
                            "cloudbeacon.expiresAt": item.date!.addingTimeInterval(RecentWindow.duration).timeIntervalSince1970]
        let request = UNNotificationRequest(identifier: "cloudbeacon." + NotificationLedger.identifier(feed: feed, item: item), content: content, trigger: nil)
        do {
            try await center.add(request)
            guard enabled, store.selectedIDs.contains(feed.id), item.date!.addingTimeInterval(RecentWindow.duration) > Date() else {
                center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                return
            }
            ledger = updated; persist()
            message = "Notification submitted to macOS. Banner delivery depends on your system settings."
        } catch { message = "macOS could not accept a notification. CloudBeacon will retry on a later successful check." }
    }
    func cleanup() async {
        let now = Date()
        ledger.retain(feeds: store.selectedIDs, now: now); persist()
        let delivered = await center.deliveredNotifications()
        let expired = delivered.filter { notice in
            let info = notice.request.content.userInfo
            let expiry = (info["cloudbeacon.expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return NotificationRetention.shouldRemove(feedID: info["cloudbeacon.feedID"] as? String, expires: expiry,
                                                       delivered: notice.date, selected: store.selectedIDs, now: now)
        }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: expired)
    }
    func clearDelivered() {
        center.removeAllDeliveredNotifications()
        message = "Delivered CloudBeacon notifications cleared. Seen reports will not be replayed."
    }
    func openSystemSettings() {
        if !NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) {
            message = "Open System Settings → Notifications manually, then choose CloudBeacon."
        }
    }
    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(ledger), data.count <= 2_000_000, data != lastPersisted {
            preferences.set(data, forKey: "notificationLedger"); lastPersisted = data
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in NSWorkspace.shared.open(URL(string: "https://health.aws.amazon.com/health/status")!) }
        }
        completionHandler()
    }
}
