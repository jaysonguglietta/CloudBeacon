import SwiftUI
import StatusCore

@MainActor final class WatchlistDraft: ObservableObject {
    @Published var selected: Set<String> = []
    @Published var regionID = "me-central-1"
    @Published var search = ""
    @Published var error: String?
    var initialized = false
}

struct WatchlistEditor: View {
    @ObservedObject var store: WatchStore
    @ObservedObject var notifications: NotificationController
    let done: () -> Void
    @StateObject private var draft = WatchlistDraft()
    private var regions: [FeedDescriptor] {
        Dictionary(grouping: store.catalog.feeds, by: \.regionID).values.compactMap(\.first)
            .sorted { $0.region == $1.region ? $0.regionID < $1.regionID : $0.region < $1.region }
    }
    private var visible: [FeedDescriptor] {
        store.catalog.feeds.filter { $0.regionID == draft.regionID && (draft.search.isEmpty || $0.service.localizedCaseInsensitiveContains(draft.search) || $0.id.localizedCaseInsensitiveContains(draft.search)) }
            .sorted { $0.service < $1.service }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose up to \(WatchStore.maximumFeeds) service/region feeds. Changes apply when you save.").font(.caption)
            if store.catalog.fallback { Text("Catalog unavailable. Only the original UAE feed is available in this build.").font(.caption).foregroundStyle(.orange) }
            Picker("AWS region", selection: $draft.regionID) {
                ForEach(regions, id: \.regionID) { feed in Text("\(feed.region) · \(feed.regionID)").tag(feed.regionID) }
            }
            TextField("Search services in this region", text: $draft.search).textFieldStyle(.roundedBorder)
            Text("\(draft.selected.count)/\(WatchStore.maximumFeeds) selected across all regions").font(.caption.weight(.semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if visible.isEmpty { Text("No services match. Clear the search or choose another region.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(visible) { feed in
                        Toggle(feed.service, isOn: Binding(get: { draft.selected.contains(feed.id) }, set: { selected in
                            if selected {
                                guard draft.selected.count < WatchStore.maximumFeeds else { draft.error = "You can monitor up to \(WatchStore.maximumFeeds) feeds. Remove one first."; return }
                                draft.selected.insert(feed.id)
                            } else { draft.selected.remove(feed.id) }
                            draft.error = nil
                        })).toggleStyle(.checkbox).font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }.frame(height: 180)
            if !draft.selected.isEmpty {
                DisclosureGroup("Selected feeds (\(draft.selected.count))") {
                    ForEach(store.catalog.feeds.filter { draft.selected.contains($0.id) }.sorted { $0.label < $1.label }) { feed in
                        HStack {
                            Text(feed.label).font(.caption)
                            Spacer()
                            Button { draft.selected.remove(feed.id) } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel("Remove \(feed.label)")
                        }.padding(.vertical, 3)
                    }
                }.font(.caption)
            }
            if let error = draft.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Save watchlist") {
                    do {
                        try store.select(draft.selected)
                        Task { await notifications.cleanup(); await store.refresh() }
                        done()
                    } catch { draft.error = "Couldn’t save this watchlist. Choose at most \(WatchStore.maximumFeeds) listed feeds and try again." }
                }.buttonStyle(.borderedProminent)
                Button("Cancel", action: done)
            }
        }.onAppear {
            guard !draft.initialized else { return }
            draft.initialized = true; draft.selected = store.selectedIDs
            draft.regionID = store.feeds.first?.regionID ?? regions.first?.regionID ?? "me-central-1"
        }
    }
}
