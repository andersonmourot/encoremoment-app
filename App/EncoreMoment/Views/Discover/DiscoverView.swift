import SwiftUI
import EncoreMomentCore

/// Public feed split into two rails: "Moments" — a media-first grid ranked by
/// likes — and "Events" — the classic event feed ranked by popularity.
struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path: [UUID] = []
    @State private var rail: Rail = .moments

    private enum Rail {
        case moments, events
    }

    private var results: [Event] {
        model.events
    }

    private var momentResults: [MediaFeedItem] {
        model.moments
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
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
            .navigationTitle("In The Moment")
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
        if !model.hasLoaded && model.isLoading {
            ProgressView().frame(maxHeight: .infinity)
        } else if momentResults.isEmpty {
            ContentUnavailableViewCompat(
                title: "No moments yet",
                systemImage: "camera.on.rectangle",
                message: "Recently uploaded photos and videos will show up here."
            )
        } else {
            MomentsGridView(
                items: momentResults,
                hasMore: model.hasMoreMoments,
                loadMore: { await model.loadMoreMoments() }
            )
        }
    }

    @ViewBuilder
    private var eventsContent: some View {
        AsyncContentView(
            isLoading: model.isLoading,
            hasLoaded: model.hasLoaded,
            isEmpty: model.events.isEmpty,
            errorMessage: model.loadError,
            retry: { await model.refresh() }
        ) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(results) { event in
                        EventRow(event: event, creator: model.creator(id: event.creatorId))
                            .contentShape(Rectangle())
                            .onTapGesture { path.append(event.id) }
                            .task {
                                if event.id == results.last?.id {
                                    await model.loadMoreEvents()
                                }
                            }
                    }

                    if model.hasMoreEvents {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        } empty: {
            ContentUnavailableViewCompat(
                title: "No events yet",
                systemImage: "sparkles",
                message: "Published events from creators will show up here."
            )
        }
    }
}

private struct EventRow: View {
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
                        Text("·")
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

struct MediaCountBadge: View {
    let photos: Int
    let videos: Int

    var body: some View {
        HStack(spacing: 8) {
            if photos > 0 { Label("\(photos)", systemImage: "photo") }
            if videos > 0 { Label("\(videos)", systemImage: "video") }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#Preview {
    DiscoverView().environmentObject(AppModel())
}
