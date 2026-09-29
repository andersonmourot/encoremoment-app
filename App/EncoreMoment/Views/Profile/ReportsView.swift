import SwiftUI
import EncoreMomentCore

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var reports: [Report] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if reports.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No reports",
                    systemImage: "checkmark.shield",
                    message: "Submitted reports will appear here."
                )
                .frame(height: 260)
                .listRowSeparator(.hidden)
            } else {
                ForEach(reports) { report in
                    ReportRow(report: report) {
                        delete(report)
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        reports = await model.moderationReports()
        isLoading = false
    }

    private func delete(_ report: Report) {
        reports.removeAll { $0.id == report.id }
        Task {
            if !(await model.deleteReport(id: report.id)) {
                await load()
            }
        }
    }
}

private struct ReportRow: View {
    let report: Report
    var onDelete: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(report.targetType.displayName, systemImage: report.targetType.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(report.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete report")
            }

            Text(report.reason.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.accentColor)

            if let details = report.details, !details.isEmpty {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Target: \(report.targetID.uuidString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

private extension ReportTargetType {
    var displayName: String {
        switch self {
        case .event: "Event"
        case .media: "Media"
        case .comment: "Comment"
        case .creator: "Creator"
        }
    }

    var systemImage: String {
        switch self {
        case .event: "calendar"
        case .media: "photo"
        case .comment: "text.bubble"
        case .creator: "person.crop.circle"
        }
    }
}
