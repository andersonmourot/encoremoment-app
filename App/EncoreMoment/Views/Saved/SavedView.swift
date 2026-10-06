import SwiftUI
import EncoreMomentCore

/// A fan's saved content: favorited events.
struct SavedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAuth = false
    @State private var scrollOffset: CGFloat = 0

    private var headerCollapsed: Bool { scrollOffset > 24 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CollapsingTabHeader("Saved", collapsed: headerCollapsed)

                Group {
                let favorites = model.favoriteEvents
                AsyncContentView(
                    isLoading: model.isLoading,
                    hasLoaded: model.hasLoaded,
                    isEmpty: favorites.isEmpty,
                    errorMessage: model.loadError,
                    retry: { await model.refresh() }
                ) {
                    List {
                        if !model.isAccountSignedIn {
                            Section {
                                Button {
                                    showingAuth = true
                                } label: {
                                    Label("Sign in to sync across devices", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.subheadline.weight(.semibold))
                                }
                            } footer: {
                                Text("Your favorites are saved on this device. Sign in to sync them everywhere.")
                            }
                        }
                        if !favorites.isEmpty {
                            Section("Favorite events") {
                                ForEach(favorites) { event in
                                    NavigationLink(value: event.id) {
                                        SavedEventRow(event: event, creator: model.creator(id: event.creatorId))
                                    }
                                }
                            }
                        }
                    }
                    .trackScrollOffset($scrollOffset)
                } empty: {
                    ContentUnavailableViewCompat(
                        title: "Nothing saved yet",
                        systemImage: "heart",
                        message: "Tap the heart on an event to save it here."
                    )
                }
                }
            }
            .navigationTitle("Saved")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let event = model.event(id: id) {
                    EventDetailView(event: event)
                }
            }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showingAuth) {
                AuthView()
            }
        }
    }
}

private struct SavedEventRow: View {
    let event: Event
    let creator: Creator?

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: MediaStorage.displayCoverURL(for: event))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline)
                Text("\(creator?.displayName ?? "Unknown") · \(event.date.eventDayString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SavedView().environmentObject(AppModel())
}
