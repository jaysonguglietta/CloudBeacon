import SwiftUI
import AppKit
import StatusCore

@main struct CloudBeaconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            StatusView(store: delegate.monitoring.store, settings: delegate.settings, notifications: delegate.monitoring.notifications)
        } label: {
            MenuLabel(store: delegate.monitoring.store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @ObservedObject var store: WatchStore
    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: StatusIcon.image(for: store.health)).renderingMode(.original)
            Text("AWS")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CloudBeacon. Selected AWS feeds: \(store.health.label). \(store.snapshot.reason)")
        .help("Selected AWS feeds: \(store.health.label)\n\(store.snapshot.reason)")
    }
}

@MainActor final class PopoverState: ObservableObject {
    struct Preview { let title: String; let text: String }
    @Published var settings = false
    @Published var search = ""
    @Published var expanded: Set<String> = []
    @Published var preview: Preview?
    @Published var feedback: String?
    @Published var confirmClear = false
    @Published var confirmNotifications = false
    @Published var editingWatchlist = false
}

struct StatusView: View {
    @ObservedObject var store: WatchStore
    @ObservedObject var settings: SettingsController
    @ObservedObject var notifications: NotificationController
    @StateObject private var ui = PopoverState()
    private var contentHeight: CGFloat { min(520, max(260, (NSScreen.main?.visibleFrame.height ?? 800) - 220)) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "light.beacon.max.fill").foregroundStyle(.orange)
                Text("CloudBeacon").font(.headline)
                Spacer()
                Button {
                    settings.reconcile(); ui.settings.toggle()
                } label: { Image(systemName: "gearshape") }
                    .help("Settings and diagnostics").accessibilityLabel("Settings and diagnostics")
                    .keyboardShortcut(",")
            }.padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    statusHeader
                    if ui.settings { settingsView }
                    if let preview = ui.preview { previewView(preview) }
                    if let feedback = ui.feedback {
                        Label(feedback, systemImage: feedback.hasPrefix("Couldn’t") ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary).accessibilityLabel(feedback)
                    }
                    history
                }.padding(16)
            }.frame(height: contentHeight)
            Divider()
            footer
        }
        .frame(width: 420)
        .onAppear { settings.reconcile(); store.updateFreshness(); Task { await notifications.reconcile(); await notifications.cleanup() } }
        .onChange(of: store.reports) { items in ui.expanded.formIntersection(Set(items.map(\.id))) }
        .confirmationDialog("Clear saved updates?", isPresented: $ui.confirmClear, titleVisibility: .visible) {
            Button("Clear saved updates", role: .destructive) { store.clearSavedUpdates() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes saved copies for your watched feeds. The current 24-hour view remains in memory; later successful checks may save new copies if enabled.") }
        .confirmationDialog("Clear delivered CloudBeacon notifications?", isPresented: $ui.confirmNotifications, titleVisibility: .visible) {
            Button("Clear delivered notifications", role: .destructive) { notifications.clearDelivered() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Seen reports will not be replayed. Future new reports may still notify if enabled.") }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("YOUR AWS WATCHLIST · LAST 24 HOURS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Label {
                Text(store.health.label).foregroundStyle(.primary)
            } icon: {
                Image(systemName: StatusIcon.symbol(for: store.health)).foregroundStyle(Color(nsColor: StatusIcon.tint(for: store.health)))
            }.font(.title3.weight(.semibold))
            Text(store.scopeLabel).font(.subheadline).foregroundStyle(.secondary)
            Text(store.snapshot.reason).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Only selected feeds and reports published within 24 hours are included. This does not confirm all AWS services or account-specific health.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Feed coverage (\(store.coverage.filter { $0.snapshot.health != .unknown }.count)/\(store.feeds.count) confirmed)") {
                ForEach(store.coverage) { coverage in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(coverage.feed.label, systemImage: StatusIcon.symbol(for: coverage.snapshot.health)).font(.caption.weight(.semibold))
                        Text(coverage.snapshot.reason).font(.caption).foregroundStyle(.secondary)
                        Text("Last success: \(dateText(coverage.checked))").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }.font(.caption)
            DisclosureGroup("Status guide") {
                VStack(alignment: .leading, spacing: 7) {
                    legend(.disruption, "Red × — latest report describes disruption")
                    legend(.degraded, "Amber ! — latest report describes degradation")
                    legend(.resolved, "Green ✓ — no recent reports, or latest reports resolved")
                    legend(.unknown, "Gray ? — report or connection unconfirmed")
                    Text("Older reports are hidden, not marked recovered. Aging out of this 24-hour view is not proof that an issue ended.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.font(.caption)
        }
    }
    private func legend(_ health: Health, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: StatusIcon.symbol(for: health)).foregroundStyle(Color(nsColor: StatusIcon.tint(for: health)))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REPORTS · LAST 24 HOURS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.reports.count) updates").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !store.reports.isEmpty {
                TextField("Search titles and descriptions", text: $ui.search)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Search feed updates")
            }
            if store.loading && store.reports.isEmpty {
                ProgressView("Checking AWS…").frame(maxWidth: .infinity).padding()
            } else if store.reports.isEmpty {
                Label("No selected-feed reports were published in the last 24 hours. Feed coverage shows whether checks succeeded.", systemImage: "tray")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let filtered = store.reports.filter { ui.search.isEmpty || ($0.item.title + $0.item.body).localizedCaseInsensitiveContains(ui.search) }
                if filtered.isEmpty {
                    Text("No updates match “\(ui.search)”.").foregroundStyle(.secondary)
                    Button("Clear search") { ui.search = "" }
                }
                ForEach(filtered) { report in
                    let item = report.item
                    DisclosureGroup(isExpanded: Binding(get: { ui.expanded.contains(report.id) }, set: { expanded in
                        if expanded { ui.expanded.insert(report.id) } else { ui.expanded.remove(report.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.body.isEmpty ? "No details were included in this update." : item.body)
                                .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Button("Preview update summary…") {
                                ui.preview = .init(title: "Update summary", text: summary(report))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            if report.id == store.reports.first?.id { Text("LATEST REPORT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                            Text(report.feed.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Text(dateText(item.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("Monitored feeds: \(store.feeds.count)/\(WatchStore.maximumFeeds)").font(.subheadline.weight(.semibold))
            Button(ui.editingWatchlist ? "Close feed editor" : "Choose regions and services…") { ui.editingWatchlist.toggle() }
            if ui.editingWatchlist {
                WatchlistEditor(store: store, notifications: notifications) { ui.editingWatchlist = false }
            }
            notificationSettings
            Divider()
            Picker("Check every", selection: $store.interval) {
                Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15)
            }
            Toggle("Launch at login", isOn: Binding(get: { settings.launchEnabled }, set: settings.setLogin))
            if let message = settings.loginMessage { Text(message).font(.caption).fixedSize(horizontal: false, vertical: true) }
            if settings.login == .approval || settings.login == .unavailable {
                Button("Open Login Items settings…", action: settings.openLoginSettings)
            }
            Toggle("Remember updates for offline viewing", isOn: $store.remembersUpdates)
            Text("Off by default. Saved copies stay in this app’s container and always show unconfirmed until a live check succeeds.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear saved updates…", role: .destructive) { ui.confirmClear = true }
            if let storageMessage = store.storageMessage { Text(storageMessage).font(.caption).fixedSize(horizontal: false, vertical: true) }
            Divider()
            Text("CloudBeacon \(settings.version)").font(.caption.weight(.semibold))
            Button("Preview support diagnostics…") {
                ui.preview = .init(title: "Support diagnostics", text: store.diagnostics(version: settings.version))
            }
            Text("No AWS credentials or analytics. AWS receives your public IP during checks. Diagnostic text is copied locally only when you choose Copy.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func previewView(_ preview: PopoverState.Preview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.title).font(.headline)
            Text("Review what will be copied. Nothing is uploaded.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(preview.text).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 150)
            HStack {
                Button("Copy to clipboard") {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(preview.text, forType: .string) { ui.feedback = "Copied to clipboard." }
                    else { ui.feedback = "Couldn’t copy. Select the preview text and try copying manually." }
                }
                Spacer()
                Button("Close preview") { ui.preview = nil }
            }
        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last success: \(dateText(store.checked))").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(store.feeds.isEmpty ? "Choose feeds in Settings" : store.loading ? "Checking AWS…" : "Next: \(store.nextCheck?.formatted(date: .omitted, time: .shortened) ?? "Now")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(store.loading || store.feeds.isEmpty).keyboardShortcut("r")
                    .help(store.feeds.isEmpty ? "Choose at least one monitored feed in Settings first." : "Refresh your selected AWS feeds")
            }
            HStack {
                Link("Open AWS Health ↗", destination: URL(string: "https://health.aws.amazon.com/health/status")!)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }.font(.caption)
        }.padding(14)
    }
    private func dateText(_ date: Date?) -> String {
        guard let date else { return "Not available" }
        return date.formatted(date: .abbreviated, time: .shortened) + " " + (TimeZone.current.abbreviation(for: date) ?? "local time")
    }
    private func summary(_ report: ScopedReport) -> String {
        let item = report.item
        return "CloudBeacon · AWS public report\n\(report.feed.label)\n\(item.title)\nPublished: \(dateText(item.date))\n\n\(item.body)\n\nSource: \(report.feed.url.absoluteString)\nDashboard: https://health.aws.amazon.com/health/status\nScope: selected feeds, last 24 hours; not an AWS-wide all-clear."
    }

    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Notify me about new AWS reports", isOn: Binding(get: { notifications.enabled }, set: notifications.setEnabled))
                .disabled(notifications.busy)
            if notifications.busy { ProgressView("Requesting macOS permission…").font(.caption) }
            Text(notifications.authorization).font(.caption).foregroundStyle(.secondary)
            if !notifications.allowed { Button("Open notification settings…", action: notifications.openSystemSettings) }
            Toggle("Include resolution reports", isOn: $notifications.resolutions).disabled(!notifications.enabled)
            Toggle("Play notification sound", isOn: $notifications.sound).disabled(!notifications.enabled)
            Text("Alerts start with new reports after the first check. Existing history is not replayed. Reports and delivered alerts expire 24 hours after publication; cleanup runs while CloudBeacon is open, including after wake.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = notifications.message { Text(message).font(.caption) }
            Button("Clear delivered CloudBeacon notifications…") { ui.confirmNotifications = true }
        }
    }
}
