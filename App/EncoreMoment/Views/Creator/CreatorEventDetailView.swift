import SwiftUI
import PhotosUI
import EncoreMomentCore

/// Creator's view of one of their events: same content as the public page plus an
/// "Add media" action for uploading new photos and videos.
struct CreatorEventDetailView: View {
    let event: Event
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingManageMedia = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedMedia: MediaItem?
    @State private var mediaPendingRemoval: MediaItem?
    @State private var mediaSelection: [PhotosPickerItem] = []
    @State private var showingMediaPicker = false
    @State private var isImportingMedia = false
    @State private var reorderedMedia: [MediaItem]?

    private var liveEvent: Event { model.event(id: event.id) ?? event }
    private var visibleMedia: [MediaItem] { reorderedMedia ?? liveEvent.media }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statsCard
                Divider()
                if visibleMedia.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No media yet",
                        systemImage: "photo.badge.plus",
                        message: "Tap Add to upload photos and videos to this event."
                    )
                    .frame(height: 180)
                } else {
                    MediaGridView(
                        media: visibleMedia,
                        onTap: { selectedMedia = $0 },
                        onSetCover: { item in
                            Task { await model.setCover(media: item, for: liveEvent.id) }
                        },
                        onDelete: { mediaPendingRemoval = $0 },
                        onReorder: { reorderedMedia = $0 },
                        onReorderFinished: { persistMediaOrder() }
                    )
                }
            }
            .padding()
        }
        .navigationTitle(liveEvent.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingMediaPicker = true } label: {
                    if isImportingMedia {
                        ProgressView()
                    } else {
                        Label("Add", systemImage: "plus")
                    }
                }
                .disabled(isImportingMedia)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingEdit = true } label: { Label("Edit details", systemImage: "pencil") }
                    if !liveEvent.media.isEmpty {
                        Button { showingManageMedia = true } label: { Label("Manage media", systemImage: "rectangle.stack") }
                    }
                    Button {
                        Task { await model.setPublished(!liveEvent.isPublished, for: liveEvent.id) }
                    } label: {
                        if liveEvent.isPublished {
                            Label("Switch to draft", systemImage: "eye.slash")
                        } else {
                            Label("Publish", systemImage: "eye")
                        }
                    }
                    ShareLink(item: DeepLink.event(liveEvent.id).webURL) {
                        Label("Share link", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Event", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditEventView(event: liveEvent)
        }
        .sheet(isPresented: $showingManageMedia) {
            ManageMediaView(event: liveEvent)
        }
        .photosPicker(
            isPresented: $showingMediaPicker,
            selection: $mediaSelection,
            maxSelectionCount: 20,
            matching: PHPickerFilter.any(of: [PHPickerFilter.images, PHPickerFilter.videos])
        )
        .onChange(of: mediaSelection) { items in
            guard !items.isEmpty else { return }
            Task { await importMedia(items) }
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                deleteEvent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the event and its media from EncoreMoment.")
        }
        .alert(
            "Remove this media?",
            isPresented: Binding(
                get: { mediaPendingRemoval != nil },
                set: { if !$0 { mediaPendingRemoval = nil } }
            )
        ) {
            Button("Remove Media", role: .destructive) {
                removePendingMedia()
            }
            Button("Cancel", role: .cancel) { mediaPendingRemoval = nil }
        } message: {
            Text("This removes the selected photo or video from this event.")
        }
        .fullScreenCover(item: $selectedMedia) { MediaDetailView(item: $0) }
    }

    private func deleteEvent() {
        let id = liveEvent.id
        Task {
            await model.deleteEvent(id)
            dismiss()
        }
    }

    private func removePendingMedia() {
        guard let item = mediaPendingRemoval else { return }
        mediaPendingRemoval = nil
        Task {
            await model.removeMedia(item.id, from: liveEvent.id)
        }
    }

    private func persistMediaOrder() {
        guard let reorderedMedia else { return }
        Task {
            await model.reorderMedia(reorderedMedia, in: liveEvent.id)
            self.reorderedMedia = nil
        }
    }

    private func importMedia(_ items: [PhotosPickerItem]) async {
        isImportingMedia = true
        defer {
            isImportingMedia = false
            mediaSelection = []
        }
        do {
            let importItems = try await makeImportItems(from: items)
            try await EventMediaImporter.importItems(importItems, to: liveEvent.id, model: model)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func makeImportItems(from items: [PhotosPickerItem]) async throws -> [EventMediaImportItem] {
        var importItems: [EventMediaImportItem] = []
        for item in items {
            guard let data = try await item.loadTransferable(type: Data.self) else { continue }
            importItems.append(EventMediaImportItem(data: data, supportedContentTypes: item.supportedContentTypes))
        }
        return importItems
    }

    private var statsCard: some View {
        let stats = model.stats(for: liveEvent.id)
        return HStack(spacing: 0) {
            StatTile(value: stats.views, label: "Views", systemImage: "eye")
            Divider().frame(height: 36)
            StatTile(value: stats.downloads, label: "Downloads", systemImage: "square.and.arrow.down")
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: MediaStorage.displayCoverURL(for: liveEvent))
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 12) {
                Label(liveEvent.date.eventDayString, systemImage: "calendar")
                if let location = liveEvent.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let details = liveEvent.details {
                Text(details).padding(.top, 4)
            }
        }
    }
}

/// One labeled metric in the creator's stats card.
private struct StatTile: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Label("\(value)", systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .labelStyle(.titleAndIcon)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
