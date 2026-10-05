import SwiftUI
import EncoreMomentCore

/// Vertical media feed — one item per row, scroll down like a social feed.
/// Each card shows the media with creator/event context and a like badge;
/// tapping opens the swipeable ``MediaPagerView``.
struct MomentsGridView: View {
    let items: [MediaFeedItem]
    var hasMore = false
    var loadMore: (() async -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @State private var selected: MediaItem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(items) { feedItem in
                    MomentCard(item: feedItem)
                        .onTapGesture { selected = feedItem.media }
                        .task {
                            if feedItem.id == items.last?.id, let loadMore {
                                await loadMore()
                            }
                        }
                }
            }
            .padding(.vertical, 8)
            if hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .fullScreenCover(item: $selected) { item in
            MediaPagerView(
                items: items.map(\.media),
                initialSelection: item.id,
                likeSummaries: likeSummaries,
                onLikeChanged: { _ in
                    // Keep the Profile "Liked" rail in sync with like toggles.
                    Task { await model.loadLikedMedia() }
                }
            )
        }
    }

    private var likeSummaries: [UUID: LikeSummary] {
        Dictionary(
            uniqueKeysWithValues: items.map {
                ($0.id, LikeSummary(eventID: $0.id, count: $0.likeCount, likedByViewer: $0.likedByViewer))
            }
        )
    }
}

/// One feed card: creator + event header, full-width media, like row.
private struct MomentCard: View {
    let item: MediaFeedItem
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(item.creatorName).font(.subheadline.weight(.semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(item.eventTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)

            RemoteImage(url: MediaStorage.playableURL(for: item.media.thumbnailURL ?? item.media.url))
                .aspectRatio(4.0 / 5.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if item.media.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(9)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(10)
                    }
                }

            HStack(spacing: 14) {
                Label("\(item.likeCount)", systemImage: item.likedByViewer ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.likedByViewer ? .pink : .primary)
                if let caption = item.media.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}
