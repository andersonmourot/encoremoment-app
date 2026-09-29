import SwiftUI
import EncoreMomentCore

struct CreatorsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var results: [Creator] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return model.creators }
        return model.creators.filter { creator in
            [creator.displayName, creator.handle, creator.bio ?? ""]
                .joined(separator: " ")
                .range(of: trimmed, options: .caseInsensitive) != nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { creator in
                    NavigationLink {
                        CreatorProfileView(creator: creator)
                    } label: {
                        CreatorSearchRow(creator: creator)
                    }
                }
            }
            .navigationTitle("Creators")
            .searchable(text: $query, prompt: "Search creators")
            .refreshable { await model.refresh() }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No creators found",
                        systemImage: "person.2",
                        message: "Try searching by name or handle."
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
            RemoteImage(url: creator.avatarURL)
                .frame(width: 44, height: 44)
                .clipShape(Circle())

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
        }
        .padding(.vertical, 4)
    }
}
