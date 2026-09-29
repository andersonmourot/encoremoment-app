import SwiftUI
import EncoreMomentCore

struct ManageMediaView: View {
    let event: Event
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var media: [MediaItem]
    @State private var coverImageURL: URL?
    @State private var isSaving = false

    init(event: Event) {
        self.event = event
        _media = State(initialValue: event.media)
        _coverImageURL = State(initialValue: event.coverImageURL)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($media) { $item in
                        ManageMediaRow(
                            item: $item,
                            isCover: coverImageURL == item.previewURL,
                            setCover: { coverImageURL = item.previewURL },
                            remove: { remove(item) }
                        )
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Drag to reorder. Captions appear in the full-screen media viewer.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Manage Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        media.move(fromOffsets: source, toOffset: destination)
    }

    private func remove(_ item: MediaItem) {
        media.removeAll { $0.id == item.id }
        if coverImageURL == item.previewURL {
            coverImageURL = media.first?.previewURL
        }
    }

    private func save() {
        isSaving = true
        Task {
            var updated = event
            updated.coverImageURL = coverImageURL
            updated.media = media.enumerated().map { index, item in
                var copy = item
                copy.sortOrder = index
                copy.caption = copy.caption?.nilIfBlank
                return copy
            }
            await model.updateEvent(updated)
            isSaving = false
            dismiss()
        }
    }
}

private struct ManageMediaRow: View {
    @Binding var item: MediaItem
    let isCover: Bool
    var setCover: () -> Void
    var remove: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RemoteImage(url: item.previewURL)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Label(item.kind == .video ? "Video" : "Photo", systemImage: item.kind == .video ? "video" : "photo")
                        if isCover {
                            Text("Cover")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(model.accentColor.opacity(0.18), in: Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Button(action: setCover) {
                            Label("Set as Cover", systemImage: "photo")
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        Spacer()
                        Button(role: .destructive, action: remove) {
                            Label("Remove", systemImage: "trash")
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                    .labelStyle(.titleAndIcon)
                }
            }

            TextField("Caption", text: Binding(
                get: { item.caption ?? "" },
                set: { item.caption = $0 }
            ), axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 6)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
