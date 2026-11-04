import SwiftUI
import AppKit
import StatusCore

@main struct CloudBeaconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            StatusView(store: delegate.monitoring.store, settings: delegate.settings)
        } label: {
            MenuLabel(store: delegate.monitoring.store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @ObservedObject var store: FeedMonitor
    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: StatusIcon.image(for: store.health)).renderingMode(.original)
            Text("AWS")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CloudBeacon. AWS UAE: \(store.health.label). \(store.snapshot.reason)")
        .help("AWS UAE: \(store.health.label)\n\(store.snapshot.reason)")
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
}

struct StatusView: View {
    @ObservedObject var store: FeedMonitor
    @ObservedObject var settings: SettingsController
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
                        Label(feedback, systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary).accessibilityLabel(feedback)
                    }
                    history
                }.padding(16)
            }.frame(height: contentHeight)
            Divider()
            footer
        }
        .frame(width: 420)
        .onAppear { settings.reconcile(); store.updateFreshness() }
        .onChange(of: store.items) { items in ui.expanded.formIntersection(Set(items.map(\.id))) }
        .confirmationDialog("Clear saved updates?", isPresented: $ui.confirmClear, titleVisibility: .visible) {
            Button("Clear saved updates", role: .destructive) { store.clearSavedUpdates() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the offline copy. Current updates remain in memory; a later successful check may save a new copy if enabled.") }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("MIDDLE EAST · UAE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Label {
                Text(store.health.label).foregroundStyle(.primary)
            } icon: {
                Image(systemName: StatusIcon.symbol(for: store.health)).foregroundStyle(Color(nsColor: StatusIcon.tint(for: store.health)))
            }.font(.title3.weight(.semibold))
            Text("Public reports · Multiple services · me-central-1").font(.subheadline).foregroundStyle(.secondary)
            Text(store.snapshot.reason).font(.callout).fixedSize(horizontal: false, vertical: true)
            if store.savedCopy { Label("Saved copy · not a live check", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary) }
            Text("This feed covers this region only. It does not confirm all AWS services or account-specific resource health.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Status guide") {
                VStack(alignment: .leading, spacing: 7) {
                    legend(.disruption, "Red × — latest report describes disruption")
                    legend(.degraded, "Amber ! — latest report describes degradation")
                    legend(.resolved, "Green ✓ — latest report says its issue resolved")
                    legend(.unknown, "Gray ? — report or connection unconfirmed")
                    Text("An older unresolved report never becomes green just because time has passed.").font(.caption).foregroundStyle(.secondary)
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
                Text("REPORT TIMELINE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.items.count) updates").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !store.items.isEmpty {
                TextField("Search titles and descriptions", text: $ui.search)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Search feed updates")
            }
            if store.loading && store.items.isEmpty {
                ProgressView("Checking AWS…").frame(maxWidth: .infinity).padding()
            } else if store.items.isEmpty {
                Label("No updates to display. Refresh to retry, or open AWS Health for more context.", systemImage: "tray")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let filtered = store.items.filter { ui.search.isEmpty || ($0.title + $0.body).localizedCaseInsensitiveContains(ui.search) }
                if filtered.isEmpty {
                    Text("No updates match “\(ui.search)”.").foregroundStyle(.secondary)
                    Button("Clear search") { ui.search = "" }
                }
                ForEach(filtered) { item in
                    DisclosureGroup(isExpanded: Binding(get: { ui.expanded.contains(item.id) }, set: { expanded in
                        if expanded { ui.expanded.insert(item.id) } else { ui.expanded.remove(item.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.body.isEmpty ? "No details were included in this update." : item.body)
                                .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Button("Preview update summary…") {
                                ui.preview = .init(title: "Update summary", text: summary(item))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            if item.id == store.items.first?.id { Text("LATEST REPORT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
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
                Text(store.loading ? "Checking AWS…" : "Next: \(store.nextCheck?.formatted(date: .omitted, time: .shortened) ?? "Now")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(store.loading).keyboardShortcut("r")
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
    private func summary(_ item: FeedItem) -> String {
        "CloudBeacon · AWS public regional report\nMultiple services · UAE · me-central-1\n\(item.title)\nPublished: \(dateText(item.date))\n\n\(item.body)\n\nSource: https://status.aws.amazon.com/rss/multipleservices-me-central-1.rss\nDashboard: https://health.aws.amazon.com/health/status\nNot a global or account-specific all-clear."
    }
}
