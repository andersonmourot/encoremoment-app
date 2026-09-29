import SwiftUI
import EncoreMomentCore

struct FollowingFeedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var path: [UUID] = []

    private var results: [Event] {
        EventFeed.search(model.followedEvents, query: query)
    }

    var body: some View {
        NavigationStack(path: $path) {
            AsyncContentView(
                isLoading: model.isLoading,
                hasLoaded: model.hasLoaded,
                isEmpty: model.followedCreators.isEmpty || results.isEmpty,
                errorMessage: model.loadError,
                retry: { await model.refresh() }
            ) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(results) { event in
                            FollowingEventRow(event: event, creator: model.creator(id: event.creatorId))
                                .contentShape(Rectangle())
                                .onTapGesture { path.append(event.id) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            } empty: {
                emptyState
            }
            .navigationTitle("Following")
            .navigationDestination(for: UUID.self) { id in
                if let event = model.event(id: id) {
                    EventDetailView(event: event)
                }
            }
            .searchable(text: $query, prompt: "Search followed events")
            .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.followedCreators.isEmpty {
            ContentUnavailableViewCompat(
                title: "Follow creators",
                systemImage: "person.2.badge.plus",
                message: "Follow creators from event pages or creator profiles to build your feed."
            )
        } else {
            ContentUnavailableViewCompat(
                title: "No followed events yet",
                systemImage: "sparkles",
                message: "New events from creators you follow will appear here."
            )
        }
    }
}

private struct FollowingEventRow: View {
    let event: Event
    let creator: Creator?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: MediaStorage.displayCoverURL(for: event))
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    Button {
                        Task { await model.toggleFavorite(event.id) }
                    } label: {
                        Image(systemName: model.isFavorite(event.id) ? "heart.fill" : "heart")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(model.isFavorite(event.id) ? Color.pink : Color.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
                .overlay(alignment: .bottomTrailing) {
                    MediaCountBadge(photos: event.photoCount, videos: event.videoCount)
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline)
                HStack(spacing: 6) {
                    if let creator {
                        Text(creator.displayName)
                        if creator.isVerified {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(model.accentColor)
                        }
                        Text("-")
                    }
                    Text(event.date.eventDayString)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
