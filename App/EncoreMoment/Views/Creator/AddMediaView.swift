import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import EncoreMomentCore

/// Lets a creator pick photos/videos from their library and attach them to an event.
struct AddMediaView: View {
    let eventId: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PhotosPicker(
                    selection: $selection,
                    maxSelectionCount: 20,
                    matching: PHPickerFilter.any(of: [PHPickerFilter.images, PHPickerFilter.videos])
                ) {
                    Label("Select photos or videos", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(model.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                if isImporting {
                    ProgressView("Importing \(selection.count) item(s)…")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selection) { items in
                guard !items.isEmpty else { return }
                Task { await importItems(items) }
            }
        }
    }

    private func importItems(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let importItems = try await makeImportItems(from: items)
            try await EventMediaImporter.importItems(importItems, to: eventId, model: model)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
}
