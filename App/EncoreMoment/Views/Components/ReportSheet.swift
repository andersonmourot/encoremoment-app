import SwiftUI
import EncoreMomentCore

struct ReportTarget: Identifiable {
    let id = UUID()
    let targetType: ReportTargetType
    let targetID: UUID
    let eventID: UUID?
    let title: String
}

struct ReportSheet: View {
    let target: ReportTarget
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .inappropriate
    @State private var details = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                } header: {
                    Text(target.title)
                }

                Section {
                    TextField("Optional details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Reports help us review unsafe, spammy, or inappropriate content.")
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit")
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            let report = ReportRequest(
                targetType: target.targetType,
                targetID: target.targetID,
                eventID: target.eventID,
                reason: reason,
                details: details.nilIfBlank
            )
            let submitted = await model.submitReport(report)
            isSubmitting = false
            if submitted { dismiss() }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
