import AppKit
import Network
import StatusCore

/// Owns monitoring independently of the menu label and popover lifetimes.
@MainActor final class MonitoringService {
    let store = WatchStore()
    lazy var notifications = NotificationController(store: store)
    private var task: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private let network = NWPathMonitor()
    private var wasOnline = false
    private var heartbeatCount = 0

    func start() {
        guard task == nil else { return }
        _ = notifications
        task = Task { [weak self] in
            guard let self else { return }
            await store.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await store.poll()
            }
        }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.store.updateFreshness()
                if let self {
                    heartbeatCount += 1
                    if heartbeatCount % 12 == 0 { await notifications.cleanup() }
                }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.notifications.cleanup()
                await self?.store.recoverAfterWake()
            }
        }
        network.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let reconnected = online && !self.wasOnline
                self.wasOnline = online
                if reconnected { await self.store.recoverAfterWake() }
            }
        }
        network.start(queue: DispatchQueue(label: "CloudBeacon.connectivity"))
    }
    func stop() {
        task?.cancel(); task = nil
        store.stop()
        heartbeat?.cancel(); heartbeat = nil
        network.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitoring = MonitoringService()
    let settings = SettingsController()
    func applicationDidFinishLaunching(_ notification: Notification) { monitoring.start() }
    func applicationWillTerminate(_ notification: Notification) { monitoring.stop() }
}
