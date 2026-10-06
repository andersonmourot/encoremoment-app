import SwiftUI
import EncoreMomentCore

/// The comments thread for an event — or, when `media` is set, for one media
/// item inside it: a list of comments plus a composer for signed-in users.
/// Loads its own data through ``AppModel`` (views never network).
struct CommentsSection: View {
    let event: Event
    /// When set, shows and posts comments scoped to this media item.
    var media: MediaItem? = nil
    @EnvironmentObject private var model: AppModel

    @State private var comments: [Comment] = []
    @State private var hasLoaded = false
    @State private var draft = ""
    @State private var isPosting = false
    @State private var reportTarget: ReportTarget?
    @State private var likesByComment: [UUID: LikeSummary] = [:]

    private var sortedComments: [Comment] {
        comments.sorted {
            let left = likesByComment[$0.id]?.count ?? 0
            let right = likesByComment[$1.id]?.count ?? 0
            if left == right { return $0.createdAt < $1.createdAt }
            return left > right
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if !hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if comments.isEmpty {
                Text("No comments yet. Be the first to comment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedComments) { comment in
                    CommentRow(
                        comment: comment,
                        likeSummary: likesByComment[comment.id] ?? LikeSummary(eventID: comment.id),
                        canDelete: model.canDelete(comment, in: event),
                        canLike: model.isAccountSignedIn,
                        onToggleLike: { await toggleLike(comment) },
                        onReport: {
                            reportTarget = ReportTarget(
                                targetType: .comment,
                                targetID: comment.id,
                                eventID: event.id,
                                title: "Report Comment"
                            )
                        },
                        onDelete: { await delete(comment) }
                    )
                }
            }

            if model.isAccountSignedIn {
                composer
            } else {
                Text("Sign in to join the conversation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: media?.id ?? event.id) { await load() }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target)
        }
    }

    private var title: String {
        comments.isEmpty ? "Comments" : "Comments (\(comments.count))"
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(isPosting)
            Button {
                Task { await post() }
            } label: {
                if isPosting {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPosting || !Comment.isValidBody(draft))
        }
    }

    private func load() async {
        if let media {
            comments = await model.comments(forMedia: media.id, in: event.id)
        } else {
            comments = await model.comments(forEvent: event.id)
        }
        await loadLikes()
        hasLoaded = true
    }

    /// One batched call covers every comment's like state — `likes/all`
    /// returns summaries for media comments too, so this works for both the
    /// event thread and per-media threads.
    private func loadLikes() async {
        let summaries = await model.likeSummaries(forEvent: event.id)
        likesByComment = summaries.commentsByID
    }

    private func post() async {
        isPosting = true
        defer { isPosting = false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = if let media {
            await model.addComment(mediaID: media.id, eventID: event.id, body: text)
        } else {
            await model.addComment(eventID: event.id, body: text)
        }
        guard let created else { return }
        comments.append(created)
        likesByComment[created.id] = LikeSummary(eventID: created.id)
        draft = ""
    }

    private func delete(_ comment: Comment) async {
        if await model.deleteComment(comment) {
            comments.removeAll { $0.id == comment.id }
        }
    }

    private func toggleLike(_ comment: Comment) async {
        let current = likesByComment[comment.id] ?? LikeSummary(eventID: comment.id)
        var optimistic = current
        optimistic.likedByViewer.toggle()
        optimistic.count += optimistic.likedByViewer ? 1 : -1
        likesByComment[comment.id] = optimistic
        if let updated = await model.setCommentLike(commentID: comment.id, eventID: event.id, optimistic.likedByViewer) {
            likesByComment[comment.id] = updated
        } else {
            likesByComment[comment.id] = current
        }
    }
}

/// A single comment: author, relative time, body, and an optional delete action.
private struct CommentRow: View {
    let comment: Comment
    let likeSummary: LikeSummary
    let canDelete: Bool
    let canLike: Bool
    let onToggleLike: () async -> Void
    let onReport: () -> Void
    let onDelete: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(comment.authorName)
                    .font(.subheadline.weight(.semibold))
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await onToggleLike() }
                } label: {
                    Label("\(likeSummary.count)", systemImage: likeSummary.likedByViewer ? "heart.fill" : "heart")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!canLike)
                .accessibilityLabel(likeSummary.likedByViewer ? "Unlike comment" : "Like comment")
                Menu {
                    Button {
                        onReport()
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                    if canDelete {
                        Button(role: .destructive) {
                            Task { await onDelete() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Comment actions")
            }
            Text(comment.body)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
