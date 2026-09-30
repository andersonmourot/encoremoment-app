import SwiftUI
import EncoreMomentCore

/// Owner-only management of an event's invited viewers and collaborators.
/// Collaborators can add media (it lands in the Official section); viewers can
/// only see the event — the only audience for invite-only events.
struct EventMembersView: View {
    let event: Event
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var members: [EventMember] = []
    @State private var handle = ""
    @State private var role: EventMemberRole = .viewer
    @State private var isInviting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Handle (e.g. friend_name)", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(isInviting ? "Inviting…" : "Invite") { invite() }
                            .disabled(handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInviting)
                    }
                    Picker("Access", selection: $role) {
                        ForEach(EventMemberRole.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Invite someone")
                } footer: {
                    Text("Collaborators can add photos and videos to the Official section. Viewers can only see the event.")
                }

                Section("Invited (\(members.count))") {
                    if members.isEmpty {
                        Text("Nobody invited yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { member in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName)
                                        .font(.subheadline.weight(.medium))
                                    Text("@\(member.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    ForEach(EventMemberRole.allCases) { r in
                                        Button {
                                            Task { await changeRole(member, to: r) }
                                        } label: {
                                            Label(r.displayName, systemImage: member.role == r ? "checkmark" : "")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        Task { await remove(member) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                } label: {
                                    Text(member.role.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(member.role == .collaborator ? Color.appAccent : Color.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.quaternary.opacity(0.5), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { members = await model.eventMembers(forEvent: event.id) }
        }
    }

    private func invite() {
        isInviting = true
        Task {
            defer { isInviting = false }
            if let updated = await model.inviteMember(handle: handle, role: role, to: event.id) {
                members = updated
                handle = ""
            }
        }
    }

    private func changeRole(_ member: EventMember, to newRole: EventMemberRole) async {
        guard newRole != member.role else { return }
        if let updated = await model.inviteMember(handle: member.handle, role: newRole, to: event.id) {
            members = updated
        }
    }

    private func remove(_ member: EventMember) async {
        if let updated = await model.removeMember(member, from: event.id) {
            members = updated
        }
    }
}

#Preview {
    EventMembersView(event: Event(
        creatorId: UUID(),
        title: "Album Release Party",
        date: .now,
        inviteOnly: true
    ))
    .environmentObject(AppModel())
}
