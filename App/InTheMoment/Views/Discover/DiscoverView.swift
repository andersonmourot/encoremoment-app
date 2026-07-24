import SwiftUI
import InTheMomentCore

/// Public feed of published events from every creator.
struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var path: [UUID] = []

    private var results: [Event] {
        EventFeed.search(model.events, query: query)
    }

    private var creatorResults: [Creator] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return model.creators.filter { creator in
            [creator.displayName, creator.handle, creator.bio ?? ""]
                .joined(separator: " ")
                .range(of: trimmed, options: .caseInsensitive) != nil
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            AsyncContentView(
                isLoading: model.isLoading,
                hasLoaded: model.hasLoaded,
                isEmpty: model.events.isEmpty,
                errorMessage: model.loadError,
                retry: { await model.refresh() }
            ) {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if !creatorResults.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Creators")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    ForEach(creatorResults) { creator in
                                        NavigationLink {
                                            CreatorProfileView(creator: creator)
                                        } label: {
                                            DiscoverCreatorRow(creator: creator)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !creatorResults.isEmpty && !results.isEmpty {
                                Divider()
                            }

                            ForEach(results) { event in
                                EventRow(event: event, creator: model.creator(id: event.creatorId))
                                    .contentShape(Rectangle())
                                    .onTapGesture { path.append(event.id) }
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
            .navigationTitle("In The Moment")
            .navigationDestination(for: UUID.self) { id in
                if let event = model.event(id: id) {
                    EventDetailView(event: event)
                }
            }
            .searchable(text: $query, prompt: "Search events")
            .refreshable { await model.refresh() }
        }
    }
}

private struct DiscoverCreatorRow: View {
    let creator: Creator
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: creator.avatarURL)
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(creator.displayName).font(.subheadline.weight(.semibold))
                    if creator.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(model.accentColor)
                    }
                }
                Text(creator.displayHandle)
                    .font(.caption)
                    .foregroundStyle(model.accentColor)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
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
