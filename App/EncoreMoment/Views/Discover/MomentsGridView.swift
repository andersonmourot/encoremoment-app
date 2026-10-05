import SwiftUI
import EncoreMomentCore

/// Vertical media feed — one item fills the screen, snaps per card, scrolls
/// down like a social feed. Each card shows the media with creator/event
/// context and a like badge; tapping opens the swipeable ``MediaPagerView``.
struct MomentsGridView: View {
    let items: [MediaFeedItem]
    var hasMore = false
    var loadMore: (() async -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @State private var selected: MediaItem?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { feedItem in
                        MomentCard(item: feedItem, bottomInset: geo.safeAreaInsets.bottom)
                            .containerRelativeFrame(.vertical)
                            .onTapGesture { selected = feedItem.media }
                            .task {
                                if feedItem.id == items.last?.id, let loadMore {
                                    await loadMore()
                                }
                            }
                    }
                    if hasMore {
                        ProgressView()
                            .containerRelativeFrame(.vertical)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
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

/// One feed card: media fills the whole screen, with the creator/event caption
/// and like count overlaid on a bottom gradient — TikTok-style. Sized by
/// ``containerRelativeFrame`` on the parent so exactly one card is visible.
private struct MomentCard: View {
    let item: MediaFeedItem
    /// Bottom padding so the caption clears the translucent tab bar.
    var bottomInset: CGFloat = 0
    @EnvironmentObject private var model: AppModel

    var body: some View {
        RemoteImage(url: MediaStorage.playableURL(for: item.media.thumbnailURL ?? item.media.url))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(item.creatorName).font(.subheadline.weight(.semibold))
                            Text("·")
                            Text(item.eventTitle).lineLimit(1)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)

                        HStack(spacing: 14) {
                            Label("\(item.likeCount)", systemImage: item.likedByViewer ? "heart.fill" : "heart")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(item.likedByViewer ? .pink : .white)
                            if let caption = item.media.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    // Lift the caption above the translucent tab bar.
                    .padding(.bottom, bottomInset + 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
    }
}
