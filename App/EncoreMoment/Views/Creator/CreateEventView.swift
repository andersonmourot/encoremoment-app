import SwiftUI
import EncoreMomentCore

/// Form for a creator to start a new event page.
struct CreateEventView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var location = ""
    @State private var date = Date()
    @State private var allowsCommunityUploads = false
    @State private var inviteOnly = false

    private var canSave: Bool { Event.isValidTitle(title) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Location", text: $location)
                }
                Section("About") {
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Toggle("Let fans add media", isOn: $allowsCommunityUploads)
                } footer: {
                    Text("When enabled, signed-in users can add their own photos and videos to this event.")
                }
                Section {
                    Toggle("Invite only", isOn: $inviteOnly)
                } footer: {
                    Text("Only you and people you invite can see this event. Manage invited viewers and collaborators from the event page.")
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await model.createEvent(
                                title: title,
                                details: details,
                                location: location,
                                date: date,
                                allowsCommunityUploads: allowsCommunityUploads,
                                inviteOnly: inviteOnly
                            )
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    CreateEventView().environmentObject(AppModel())
}
