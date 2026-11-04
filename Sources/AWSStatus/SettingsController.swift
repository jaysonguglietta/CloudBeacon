import AppKit
import Combine
import ServiceManagement

@MainActor final class SettingsController: ObservableObject {
    enum LoginState { case enabled, disabled, approval, unavailable }
    @Published private(set) var login: LoginState = .disabled
    @Published private(set) var loginMessage: String?
    private var activation: AnyCancellable?
    var launchEnabled: Bool { login == .enabled || login == .approval }
    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "Development") (\(info["CFBundleVersion"] as? String ?? "unbundled"))"
    }
    init() {
        reconcile()
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }
    }
    func reconcile() {
        switch SMAppService.mainApp.status {
        case .enabled: login = .enabled; loginMessage = "CloudBeacon will launch when you log in."
        case .requiresApproval: login = .approval; loginMessage = "Approval required in System Settings → General → Login Items. Return here after approving."
        case .notRegistered: login = .disabled; loginMessage = nil
        case .notFound: login = .unavailable; loginMessage = "Install CloudBeacon in Applications, then try enabling login launch again."
        @unknown default: login = .unavailable; loginMessage = "Login-item status is unavailable. Check System Settings."
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            reconcile()
        } catch {
            reconcile()
            loginMessage = "Couldn’t change login launch. Install one copy in Applications, then check System Settings → General → Login Items and try again."
        }
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
