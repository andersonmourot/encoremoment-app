import SwiftUI
import EncoreMomentCore

/// Swipeable full-screen viewer that pages left/right through a media list.
struct MediaPagerView: View {
    let items: [MediaItem]
    /// The like state per media id, kept in sync with the parent list.
    var likeSummaries: [UUID: LikeSummary] = [:]
    var onLikeChanged: ((LikeSummary) -> Void)? = nil
    var onDownloaded: (() -> Void)? = nil

    @State private var selection: UUID

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
        TabView(selection: $selection) {
            ForEach(items) { item in
                MediaDetailView(
                    item: item,
                    initialLikeSummary: likeSummaries[item.id] ?? LikeSummary(eventID: item.id),
                    onLikeChanged: onLikeChanged,
                    onDownloaded: onDownloaded
                )
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
        .background(.black)
        .ignoresSafeArea()
    }
}
