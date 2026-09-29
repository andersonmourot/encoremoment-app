import SwiftUI
import AVKit
import EncoreMomentCore

/// Full-screen viewer for a single photo or video, with a Save-to-device action.
struct MediaDetailView: View {
    let item: MediaItem
    var initialLikeSummary: LikeSummary = LikeSummary(eventID: UUID())
    var onLikeChanged: ((LikeSummary) -> Void)? = nil
    /// Called after the item is successfully saved (used to record a download).
    var onDownloaded: (() -> Void)? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var downloadState: DownloadState = .idle
    @State private var reportTarget: ReportTarget?
    @State private var likeSummary: LikeSummary?
    @State private var isTogglingLike = false

    private enum DownloadState: Equatable {
        case idle, downloading, done, failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { downloadButton }
                ToolbarItem(placement: .topBarTrailing) { likeButton }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reportTarget = ReportTarget(
                            targetType: .media,
                            targetID: item.id,
                            eventID: item.eventId,
                            title: "Report Media"
                        )
                    } label: {
                        Image(systemName: "flag")
                    }
                    .accessibilityLabel("Report media")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $reportTarget) { target in
                ReportSheet(target: target)
            }
            .task(id: item.id) {
                likeSummary = initialLikeSummary.eventID == item.id
                    ? initialLikeSummary
                    : await model.mediaLikeSummary(mediaID: item.id, eventID: item.eventId)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .photo:
            VStack {
                RemoteImage(url: resolvedURL(item.url), contentMode: .fit)
                if let caption = item.caption {
                    Text(caption).font(.callout).foregroundStyle(.white.opacity(0.8)).padding()
                }
            }
        case .video:
            VideoPlayer(player: AVPlayer(url: resolvedURL(item.url)))
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch downloadState {
        case .idle, .failed:
            Button {
                Task { await save() }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(!item.isDownloadable)
        case .downloading:
            ProgressView()
        case .done:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var likeButton: some View {
        let summary = likeSummary ?? LikeSummary(eventID: item.id)
        Button {
            toggleLike(summary)
        } label: {
            Label("\(summary.count)", systemImage: summary.likedByViewer ? "heart.fill" : "heart")
        }
        .disabled(isTogglingLike || !model.isAccountSignedIn)
    }

    private func save() async {
        downloadState = .downloading
        do {
            try await MediaDownloader.saveToPhotoLibrary(item)
            downloadState = .done
            onDownloaded?()
        } catch {
            downloadState = .failed(error.localizedDescription)
        }
    }

    private func toggleLike(_ summary: LikeSummary) {
        isTogglingLike = true
        Task {
            defer { isTogglingLike = false }
            if let updated = await model.setMediaLike(mediaID: item.id, eventID: item.eventId, !summary.likedByViewer) {
                likeSummary = updated
                onLikeChanged?(updated)
            }
        }
    }

    private func resolvedURL(_ url: URL) -> URL {
        MediaStorage.playableURL(for: url)
    }
}
