import SwiftUI
import EncoreMomentCore

struct NotificationsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if model.notifications.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No notifications",
                    systemImage: "bell",
                    message: "Activity on your events and profile will appear here."
                )
                .frame(height: 260)
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.notifications) { notification in
                    NotificationRow(notification: notification)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await model.markNotificationRead(notification.id) }
                        }
                }
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            if model.unreadNotificationCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark All Read") {
                        Task { await model.markAllNotificationsRead() }
                    }
                }
            }
        }
        .refreshable { await model.loadNotifications() }
        .task { await model.loadNotifications() }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.kind.systemImage)
                .foregroundStyle(notification.isRead ? Color.secondary : Color.appAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                    Spacer()
                    if !notification.isRead {
                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(notification.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(notification.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension AppNotificationKind {
    var systemImage: String {
        switch self {
        case .comment: "text.bubble"
        case .like: "hand.thumbsup"
        case .follow: "person.crop.circle.badge.plus"
        case .mediaUpload: "photo.badge.plus"
        case .invite: "envelope.badge"
        }
    }
}
