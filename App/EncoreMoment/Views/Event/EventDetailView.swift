import SwiftUI
import PhotosUI
import EncoreMomentCore

/// A single event page: header plus its grid of downloadable photos and videos.
struct EventDetailView: View {
    let event: Event
    @EnvironmentObject private var model: AppModel
    @State private var selectedMedia: MediaItem?
    @State private var isDownloadingAll = false
    @State private var downloadMessage: String?
    @State private var likeSummary: LikeSummary?
    @State private var isTogglingLike = false
    @State private var showingAuth = false
    @State private var showingMediaPicker = false
    @State private var mediaSelection: [PhotosPickerItem] = []
    @State private var isImportingMedia = false
    @State private var reportTarget: ReportTarget?
    @State private var mediaPendingRemoval: MediaItem?
    @State private var mediaLikes: [UUID: LikeSummary] = [:]
    /// The signed-in viewer's invited role on this event, if any.
    @State private var membership: EventMemberRole?

    /// Always read the freshest copy from the model so newly added media appears.
    private var liveEvent: Event { model.event(id: event.id) ?? event }

    private var isFavorite: Bool { model.isFavorite(liveEvent.id) }
    private var isOwner: Bool { model.currentCreator?.id == liveEvent.creatorId }

    /// The owner, invited collaborators, and (when enabled) any signed-in user
    /// may add media. Viewers cannot.
    private var canUploadMedia: Bool {
        isOwner || liveEvent.allowsCommunityUploads || membership?.canUpload == true
    }

    private var rankedMedia: [MediaItem] {
        liveEvent.media.sorted {
            let left = mediaLikes[$0.id]?.count ?? 0
            let right = mediaLikes[$1.id]?.count ?? 0
            if left == right { return $0.sortOrder < $1.sortOrder }
            return left > right
        }
    }

    /// Uploads by the owner and invited collaborators.
    private var officialMedia: [MediaItem] { rankedMedia.filter(\.isOfficial) }
    /// Media contributed by the community.
    private var communityMedia: [MediaItem] { rankedMedia.filter { !$0.isOfficial } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: MediaStorage.displayCoverURL(for: liveEvent))
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 6) {
                    Text(liveEvent.title).font(.title2.bold())
                    if let creator = model.creator(id: liveEvent.creatorId) {
                        HStack {
                            NavigationLink {
                                CreatorProfileView(creator: creator)
                            } label: {
                                Text(creator.displayHandle).foregroundStyle(model.accentColor)
                            }
                            Spacer()
                            FollowButton(creator: creator)
                        }
                    }
                    HStack(spacing: 12) {
                        Label(liveEvent.date.eventDayString, systemImage: "calendar")
                        if let location = liveEvent.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                        }
                        if liveEvent.inviteOnly {
                            Label("Invite Only", systemImage: "lock")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let details = liveEvent.details {
                        Text(details).font(.body).padding(.top, 4)
                    }
                }

                likeRow

                if liveEvent.downloadableCount > 0 {
                    Button {
                        downloadAll()
                    } label: {
                        Label(
                            isDownloadingAll ? "Saving…" : "Download all (\(liveEvent.downloadableCount))",
                            systemImage: "square.and.arrow.down.on.square"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloadingAll)
                }

                Divider()

                if canUploadMedia {
                    uploadSection
                }

                if liveEvent.media.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No media yet",
                        systemImage: "photo.on.rectangle",
                        message: "Photos and videos for this event will appear here."
                    )
                    .frame(height: 200)
                } else {
                    mediaSection(title: "Official", media: officialMedia)
                    if !communityMedia.isEmpty || liveEvent.allowsCommunityUploads {
                        mediaSection(title: "Community", media: communityMedia)
                    }
                }

                Divider()

                CommentsSection(event: liveEvent)
            }
            .padding()
        }
        .navigationTitle(liveEvent.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: liveEvent.id) {
            // List rows carry a "lite" event (no media array) — pull the full
            // event into the model's cache so `liveEvent` gets the media.
            await model.fetchFullEvent(id: event.id)
            await model.recordView(liveEvent.id)
            let summaries = await model.likeSummaries(forEvent: liveEvent.id)
            likeSummary = summaries.event
            mediaLikes = summaries.mediaByID
            if model.isAccountSignedIn {
                membership = await model.myMembership(in: liveEvent.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.toggleFavorite(liveEvent.id) }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                }
                .tint(isFavorite ? Color.pink : model.accentColor)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: DeepLink.event(liveEvent.id).webURL,
                    subject: Text(liveEvent.title),
                    message: Text("Photos & videos from \(liveEvent.title) on EncoreMoment")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        reportTarget = ReportTarget(
                            targetType: .event,
                            targetID: liveEvent.id,
                            eventID: liveEvent.id,
                            title: "Report Event"
                        )
                    } label: {
                        Label("Report Event", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $selectedMedia) { item in
            MediaPagerView(
                items: rankedMedia,
                initialSelection: item.id,
                likeSummaries: mediaLikes,
                onLikeChanged: { mediaLikes[$0.eventID] = $0 },
                onDownloaded: {
                    Task { await model.recordDownloads(eventID: liveEvent.id, count: 1) }
                }
            )
        }
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target)
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
            Text("This removes your contributed photo or video from this event.")
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
        .alert("Download", isPresented: Binding(
            get: { downloadMessage != nil },
            set: { if !$0 { downloadMessage = nil } }
        )) {
            Button("OK", role: .cancel) { downloadMessage = nil }
        } message: {
            Text(downloadMessage ?? "")
        }
    }

    /// A labeled media section (Official or Community) with its grid.
    private func mediaSection(title: String, media: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if media.isEmpty {
                Text(title == "Official"
                     ? "The creator hasn't added media yet."
                     : "No community uploads yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                MediaGridView(
                    media: media,
                    onTap: { selectedMedia = $0 },
                    likeSummary: { mediaLikes[$0.id] },
                    onToggleLike: model.isAccountSignedIn ? { toggleMediaLike($0) } : nil,
                    canDelete: { model.canDeleteMedia($0, in: liveEvent) },
                    onDelete: { mediaPendingRemoval = $0 }
                )
            }
        }
    }

    /// "Add media" button plus a live progress bar while files upload.
    private var uploadSection: some View {
        VStack(spacing: 8) {
            Button {
                if model.isAccountSignedIn {
                    showingMediaPicker = true
                } else {
                    showingAuth = true
                }
            } label: {
                Label(
                    isImportingMedia ? "Adding media..." : "Add your photos or videos",
                    systemImage: "photo.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isImportingMedia)

            if isImportingMedia {
                ProgressView(value: model.uploadProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 4)
                if let progress = model.uploadProgress {
                    Text("Uploading… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var likeRow: some View {
        let summary = likeSummary ?? LikeSummary(eventID: liveEvent.id)
        let liked = summary.likedByViewer
        return Button {
            toggleLike(currentlyLiked: liked)
        } label: {
            Label("\(summary.count)", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(liked ? model.accentColor : Color.secondary)
        .disabled(isTogglingLike || !model.isAccountSignedIn)
        .accessibilityLabel(liked ? "Unlike" : "Like")
    }

    private func toggleLike(currentlyLiked: Bool) {
        isTogglingLike = true
        let previous = likeSummary
        var optimistic = previous ?? LikeSummary(eventID: liveEvent.id)
        optimistic.likedByViewer = !currentlyLiked
        optimistic.count += optimistic.likedByViewer ? 1 : -1
        likeSummary = optimistic
        Task {
            defer { isTogglingLike = false }
            if let updated = await model.setLike(eventID: liveEvent.id, !currentlyLiked) {
                likeSummary = updated
            } else {
                likeSummary = previous
            }
        }
    }

    private func toggleMediaLike(_ item: MediaItem) {
        let summary = mediaLikes[item.id] ?? LikeSummary(eventID: item.id)
        var optimistic = summary
        optimistic.likedByViewer.toggle()
        optimistic.count += optimistic.likedByViewer ? 1 : -1
        mediaLikes[item.id] = optimistic
        Task {
            if let updated = await model.setMediaLike(
                mediaID: item.id,
                eventID: liveEvent.id,
                optimistic.likedByViewer
            ) {
                mediaLikes[item.id] = updated
            } else {
                mediaLikes[item.id] = summary
            }
        }
    }

    private func removePendingMedia() {
        guard let item = mediaPendingRemoval else { return }
        mediaPendingRemoval = nil
        Task {
            await model.removeMedia(item.id, from: liveEvent.id)
        }
    }

    private func downloadAll() {
        isDownloadingAll = true
        Task {
            defer { isDownloadingAll = false }
            do {
                let result = try await MediaDownloader.saveAllToPhotoLibrary(liveEvent.media)
                await model.recordDownloads(eventID: liveEvent.id, count: result.saved)
                downloadMessage = result.failed == 0
                    ? "Saved \(result.saved) item\(result.saved == 1 ? "" : "s") to your photo library."
                    : "Saved \(result.saved), \(result.failed) failed."
            } catch {
                downloadMessage = error.localizedDescription
            }
        }
    }

    private func importMedia(_ items: [PhotosPickerItem]) async {
        isImportingMedia = true
        defer {
            isImportingMedia = false
            mediaSelection = []
        }
        do {
            let importItems = try await EventMediaImporter.makeImportItems(from: items)
            try await EventMediaImporter.importItems(importItems, to: liveEvent.id, model: model)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

/// Follow / Following toggle for a creator.
private struct FollowButton: View {
    let creator: Creator
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let following = model.isFollowing(creator.id)
        Button {
            Task { await model.toggleFollow(creator.id) }
        } label: {
            Label(following ? "Following" : "Follow",
                  systemImage: following ? "checkmark" : "plus")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(following ? Color.secondary : model.accentColor)
    }
}
