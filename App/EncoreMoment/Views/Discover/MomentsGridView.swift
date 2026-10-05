import SwiftUI
import EncoreMomentCore

/// A grid of media items from the cross-event Moments feed. Each cell shows the
/// thumbnail with a like badge; tapping opens the swipeable ``MediaPagerView``.
struct MomentsGridView: View {
    let items: [MediaFeedItem]
    var hasMore = false
    var loadMore: (() async -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @State private var selected: MediaItem?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items) { feedItem in
                    MomentCell(item: feedItem)
                        .onTapGesture { selected = feedItem.media }
                        .task {
                            if feedItem.id == items.last?.id, let loadMore {
                                await loadMore()
                            }
                        }
                }
            }
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

private struct MomentCell: View {
    let item: MediaFeedItem

    var body: some View {
        RemoteImage(url: MediaStorage.playableURL(for: item.media.thumbnailURL ?? item.media.url))
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if item.media.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Label("\(item.likeCount)", systemImage: item.likedByViewer ? "heart.fill" : "heart")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.likedByViewer ? .pink : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(5)
            }
    }
}
