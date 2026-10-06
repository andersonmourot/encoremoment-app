import SwiftUI
import EncoreMomentCore

/// Vertical media feed — one full-width post per row, scrolled continuously
/// like an Instagram/TikTok feed. Each post is media with a "break" strip below
/// holding the uploader's name plus like and comment counts; tapping opens the
/// single-item ``MediaDetailView`` (left/right paging lives in event browsing).
struct MomentsGridView: View {
    let items: [MediaFeedItem]
    var hasMore = false
    var loadMore: (() async -> Void)? = nil
    var scrollOffset: Binding<CGFloat> = .constant(0)

    @EnvironmentObject private var model: AppModel
    @State private var selected: MediaFeedItem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ScrollSentinel()
                ForEach(items) { feedItem in
                    MomentCard(item: feedItem)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = feedItem }
                        .task {
                            if feedItem.id == items.last?.id, let loadMore {
                                await loadMore()
                            }
                        }
                    Divider()
                        .overlay(Color.secondary.opacity(0.25))
                }
                if hasMore {
                    ProgressView()
                        .padding()
                }
            }
        }
        .trackScrollOffset(scrollOffset)
        // Feed items open just themselves — left/right paging only happens
        // inside an event's media browser.
        .fullScreenCover(item: $selected) { feedItem in
            MediaDetailView(
                item: feedItem.media,
                initialLikeSummary: LikeSummary(
                    eventID: feedItem.media.id,
                    count: feedItem.likeCount,
                    likedByViewer: feedItem.likedByViewer,
                    commentCount: feedItem.commentCount
                ),
                onLikeChanged: { _ in
                    // Keep the Profile "Liked" rail in sync with like toggles.
                    Task { await model.loadLikedMedia() }
                }
            )
        }
    }

}

/// One feed post: full-width media, then a break strip holding the uploader's
/// name, the event it belongs to, and its like/comment counts.
private struct MomentCard: View {
    let item: MediaFeedItem
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            RemoteImage(url: MediaStorage.playableURL(for: item.media.thumbnailURL ?? item.media.url))
                .frame(maxWidth: .infinity)
                .frame(height: 430)
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

            // The break between posts: who posted it, likes, comments.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.media.uploaderName ?? item.creatorName)
                        .font(.subheadline.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(item.eventTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 16) {
                    Label("\(item.likeCount)", systemImage: item.likedByViewer ? "heart.fill" : "heart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.likedByViewer ? .pink : .primary)
                    Label("\(item.commentCount)", systemImage: "bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let caption = item.media.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.4))
        }
    }
}
