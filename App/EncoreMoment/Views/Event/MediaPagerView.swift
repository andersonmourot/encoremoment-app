import SwiftUI
import EncoreMomentCore

/// Swipeable full-screen viewer that pages left/right through a media list.
/// Uses a lazy paged ScrollView — `TabView(.page)` eagerly instantiates every
/// page (every image fetch and every AVPlayer) when the viewer opens.
struct MediaPagerView: View {
    let items: [MediaItem]
    /// The like state per media id, kept in sync with the parent list.
    var likeSummaries: [UUID: LikeSummary] = [:]
    var onLikeChanged: ((LikeSummary) -> Void)? = nil
    var onDownloaded: (() -> Void)? = nil

    @State private var selection: UUID?

    init(
        items: [MediaItem],
        initialSelection: UUID,
        likeSummaries: [UUID: LikeSummary] = [:],
        onLikeChanged: ((LikeSummary) -> Void)? = nil,
        onDownloaded: (() -> Void)? = nil
    ) {
        self.items = items
        self.likeSummaries = likeSummaries
        self.onLikeChanged = onLikeChanged
        self.onDownloaded = onDownloaded
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    MediaDetailView(
                        item: item,
                        initialLikeSummary: likeSummaries[item.id] ?? LikeSummary(eventID: item.id),
                        onLikeChanged: onLikeChanged,
                        onDownloaded: onDownloaded
                    )
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selection)
        .scrollIndicators(.hidden)
        .background(.black)
        .ignoresSafeArea()
    }
}
