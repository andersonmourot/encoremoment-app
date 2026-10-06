import SwiftUI
import EncoreMomentCore

/// Unified search: matches creators and events, and shows the most-followed
/// creators as suggestions before the user types anything.
struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var path: [UUID] = []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Creators shown when the field is empty — most-followed first.
    private var suggestedCreators: [Creator] {
        model.topCreators.isEmpty
            ? model.creators.sorted { ($0.followerCount ?? 0) > ($1.followerCount ?? 0) }
            : model.topCreators
    }

    private var creatorResults: [Creator] {
        guard !trimmedQuery.isEmpty else { return suggestedCreators }
        return model.creators.filter { creator in
            [creator.displayName, creator.handle, creator.bio ?? ""]
                .joined(separator: " ")
                .range(of: trimmedQuery, options: .caseInsensitive) != nil
        }
    }

    private var eventResults: [Event] {
        guard !trimmedQuery.isEmpty else { return [] }
        return EventFeed.search(model.events, query: trimmedQuery)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !creatorResults.isEmpty {
                    Section(trimmedQuery.isEmpty ? "Suggested Creators" : "Creators") {
                        ForEach(creatorResults) { creator in
                            NavigationLink {
                                CreatorProfileView(creator: creator)
                            } label: {
                                CreatorSearchRow(creator: creator)
                            }
                        }
                    }
                }

                if !eventResults.isEmpty {
                    Section("Events") {
                        ForEach(eventResults) { event in
                            Button {
                                path.append(event.id)
                            } label: {
                                EventSearchRow(
                                    event: event,
                                    creator: model.creator(id: event.creatorId)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Search").font(.title2.weight(.bold))
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let event = model.event(id: id) {
                    EventDetailView(event: event)
                }
            }
            .searchable(text: $query, prompt: "Events & creators")
            .refreshable { await model.refresh() }
            .overlay {
                if !trimmedQuery.isEmpty && creatorResults.isEmpty && eventResults.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No results",
                        systemImage: "magnifyingglass",
                        message: "Try a different name, handle, or event title."
                    )
                }
            }
        }
    }
}

private struct CreatorSearchRow: View {
    let creator: Creator
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(creator: creator, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(creator.displayName).font(.headline)
                    if creator.isVerified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(model.accentColor)
                    }
                }
                Text(creator.displayHandle)
                    .font(.caption)
                    .foregroundStyle(model.accentColor)
                if let bio = creator.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let count = creator.followerCount, count > 0 {
                Text("\(count) followers")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EventSearchRow: View {
    let event: Event
    let creator: Creator?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: MediaStorage.displayCoverURL(for: event))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline)
                HStack(spacing: 6) {
                    if let creator {
                        Text(creator.displayName)
                        Text("·")
                    }
                    Text(event.date.eventDayString)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
