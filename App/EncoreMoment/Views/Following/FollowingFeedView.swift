import SwiftUI
import EncoreMomentCore

/// Feed of content from creators the user follows, split into "Moments"
/// (media grid) and "Events" (event rail), both ranked by popularity.
struct FollowingFeedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path: [UUID] = []
    @State private var rail: Rail = .moments

    private enum Rail {
        case moments, events
    }

    private var results: [Event] {
        followedByPopularity
    }

    /// Followed events, most-liked first (falls back to date order).
    private var followedByPopularity: [Event] {
        model.followedEvents.sorted {
            let left = $0.likeCount ?? 0
            let right = $1.likeCount ?? 0
            if left == right { return $0.date > $1.date }
            return left > right
        }
    }

    private var momentResults: [MediaFeedItem] {
        model.followedMoments
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                TabHeader("Following")

                Picker("Feed", selection: $rail) {
                    Text("Moments").tag(Rail.moments)
                    Text("Events").tag(Rail.events)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if rail == .moments {
                    momentsContent
                } else {
                    eventsContent
                }
            }
            .navigationTitle("Following")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let event = model.event(id: id) {
                    EventDetailView(event: event)
                }
            }
            .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder
    private var momentsContent: some View {
        if model.followedCreators.isEmpty && model.hasLoaded {
            followEmptyState
        } else if !model.hasLoaded && model.isLoading {
            ProgressView().frame(maxHeight: .infinity)
        } else if momentResults.isEmpty {
            ContentUnavailableViewCompat(
                title: "No moments yet",
                systemImage: "camera.on.rectangle",
                message: "New photos and videos from creators you follow will appear here."
            )
        } else {
            MomentsGridView(
                items: momentResults,
                hasMore: model.hasMoreFollowedMoments,
                loadMore: { await model.loadMoreFollowedMoments() }
            )
        }
    }

    @ViewBuilder
    private var eventsContent: some View {
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
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.followedCreators.isEmpty {
            followEmptyState
        } else {
            ContentUnavailableViewCompat(
                title: "No followed events yet",
                systemImage: "sparkles",
                message: "New events from creators you follow will appear here."
            )
        }
    }

    private var followEmptyState: some View {
        ContentUnavailableViewCompat(
            title: "Follow creators",
            systemImage: "person.2.badge.plus",
            message: "Follow creators from event pages or creator profiles to build your feed."
        )
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
