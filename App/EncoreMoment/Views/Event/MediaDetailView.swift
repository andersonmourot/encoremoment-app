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
    @State private var showComments = false
    /// Created once per item — inline `AVPlayer(url:)` in body would be
    /// rebuilt on every state change and restart playback.
    @State private var player: AVPlayer?

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
                        showComments = true
                    } label: {
                        Label("\(likeSummary?.commentCount ?? 0)", systemImage: "bubble.right")
                    }
                    .accessibilityLabel("Comments")
                }
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
            .sheet(isPresented: $showComments) {
                MediaCommentsSheet(item: item)
            }
            .task(id: item.id) {
                if item.kind == .video {
                    player = AVPlayer(url: resolvedURL(item.url))
                }
                likeSummary = initialLikeSummary.eventID == item.id
                    ? initialLikeSummary
                    : await model.mediaLikeSummary(mediaID: item.id, eventID: item.eventId)
            }
            // Refresh the summary (including comment count) after the comments
            // sheet closes so the icon reflects posts made in it.
            .onChange(of: showComments) { _, shown in
                guard !shown else { return }
                Task {
                    likeSummary = await model.mediaLikeSummary(mediaID: item.id, eventID: item.eventId)
                }
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
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                    .tint(.white)
            }
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
        var optimistic = summary
        optimistic.likedByViewer.toggle()
        optimistic.count += optimistic.likedByViewer ? 1 : -1
        likeSummary = optimistic
        Task {
            defer { isTogglingLike = false }
            if let updated = await model.setMediaLike(mediaID: item.id, eventID: item.eventId, optimistic.likedByViewer) {
                likeSummary = updated
                onLikeChanged?(updated)
            } else {
                // Server rejected — restore the previous state.
                likeSummary = summary
            }
        }
    }

    private func resolvedURL(_ url: URL) -> URL {
        MediaStorage.playableURL(for: url)
    }
}

/// Comments thread for one media item. Fetches the parent event on first open
/// (needed for delete permissions), then renders the shared ``CommentsSection``.
private struct MediaCommentsSheet: View {
    let item: MediaItem
    @EnvironmentObject private var model: AppModel
    @State private var event: Event?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let event {
                    ScrollView {
                        CommentsSection(event: event, media: item)
                            .padding()
                    }
                } else if loadFailed {
                    Text("Couldn't load comments. Please try again.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            event = await model.loadEvent(id: item.eventId)
            loadFailed = event == nil
        }
        .presentationDetents([.medium, .large])
    }
}
