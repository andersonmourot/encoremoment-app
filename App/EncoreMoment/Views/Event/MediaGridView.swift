import SwiftUI
import UniformTypeIdentifiers
import EncoreMomentCore

/// Square thumbnail grid of an event's media.
struct MediaGridView: View {
    let media: [MediaItem]
    var onTap: (MediaItem) -> Void
    var onSetCover: ((MediaItem) -> Void)? = nil
    var canDelete: ((MediaItem) -> Bool)? = nil
    var onDelete: ((MediaItem) -> Void)? = nil
    var onReorder: (([MediaItem]) -> Void)? = nil
    var onReorderFinished: (() -> Void)? = nil
    @State private var draggedItem: MediaItem?

    private let spacing: CGFloat = 6
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(media) { item in
                Button { onTap(item) } label: {
                    MediaGridCell(item: item)
                }
                .buttonStyle(.plain)
                .onDrag {
                    guard onReorder != nil else { return NSItemProvider() }
                    draggedItem = item
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: MediaGridDropDelegate(
                        item: item,
                        media: media,
                        draggedItem: $draggedItem,
                        onReorder: onReorder,
                        onReorderFinished: onReorderFinished
                    )
                )
                .contextMenu {
                    if let onSetCover {
                        Button {
                            onSetCover(item)
                        } label: {
                            Label("Set as Cover", systemImage: "photo")
                        }
                    }
                    if let onDelete, canDelete?(item) ?? true {
                        Button(role: .destructive) {
                            onDelete(item)
                        } label: {
                            Label("Remove Media", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct MediaGridDropDelegate: DropDelegate {
    let item: MediaItem
    let media: [MediaItem]
    @Binding var draggedItem: MediaItem?
    var onReorder: (([MediaItem]) -> Void)?
    var onReorderFinished: (() -> Void)?

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem != item,
              let from = media.firstIndex(of: draggedItem),
              let to = media.firstIndex(of: item) else { return }

        var updated = media
        updated.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
        onReorder?(updated)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        onReorderFinished?()
        return true
    }
}

private struct MediaGridCell: View {
    let item: MediaItem

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(url: item.previewURL)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomLeading) {
                videoBadge
            }
    }

    @ViewBuilder
    private var videoBadge: some View {
        if item.kind == .video {
            Label(item.formattedDuration ?? "", systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
            }
    }
}
