import SwiftUI
import EncoreMomentCore

/// Creator-side dashboard: the events owned by the current creator, with the
/// ability to create new ones. Each event is independent and holds its own media.
struct MyEventsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingCreate = false
    @State private var showingAuth = false
    @State private var showingProfileSetup = false

    var body: some View {
        NavigationStack {
            Group {
                let mine = model.myEvents()
                if !model.isAccountSignedIn {
                    VStack(spacing: 16) {
                        ContentUnavailableViewCompat(
                            title: "Sign in to manage events",
                            systemImage: "person.crop.circle.badge.plus",
                            message: "Create an account to start posting photos and videos from your events."
                        )
                        Button {
                            showingAuth = true
                        } label: {
                            Text("Sign In / Create Account").bold()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if !model.isSignedIn {
                    VStack(spacing: 16) {
                        ContentUnavailableViewCompat(
                            title: "Complete your profile",
                            systemImage: "person.text.rectangle",
                            message: "Add a display name and handle to start posting photos and videos from your events."
                        )
                        Button {
                            showingProfileSetup = true
                        } label: {
                            Text("Complete Profile").bold()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    AsyncContentView(
                        isLoading: model.isLoading,
                        hasLoaded: model.hasLoaded,
                        isEmpty: mine.isEmpty,
                        errorMessage: model.loadError,
                        retry: { await model.refresh() }
                    ) {
                        List {
                            ForEach(mine) { event in
                                NavigationLink(value: event.id) {
                                    MyEventRow(event: event, stats: model.stats(for: event.id))
                                }
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { mine[$0].id }
                                Task { for id in ids { await model.deleteEvent(id) } }
                            }
                        }
                    } empty: {
                        ContentUnavailableViewCompat(
                            title: "No events yet",
                            systemImage: "rectangle.stack.badge.plus",
                            message: "Create an event page to start posting photos and videos."
                        )
                    }
                }
            }
            .navigationTitle("My Events")
            .navigationDestination(for: UUID.self) { id in
                if let event = model.event(id: id) {
                    CreatorEventDetailView(event: event)
                }
            }
            .toolbar {
                if model.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingCreate = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateEventView()
            }
            .sheet(isPresented: $showingAuth) {
                AuthView()
            }
            .sheet(isPresented: $showingProfileSetup) {
                CompleteProfileView()
            }
        }
    }
}

private struct CompleteProfileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var handle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $displayName)
                    TextField("Handle (e.g. aurora_live)", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Handle must be 3-30 characters using only lowercase letters, numbers, and underscores.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    EmptyView()
                } footer: {
                    Text("This profile lets your signed-in account create and manage events.")
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if auth.isWorking {
                                ProgressView()
                            } else {
                                Text("Save Profile").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(auth.isWorking || !isValid)
                }
            }
            .navigationTitle("Complete Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && Creator.isValidHandle(handle)
    }

    private func submit() {
        Task {
            if let account = await auth.completeProfile(displayName: displayName, handle: handle) {
                await model.didSignIn(account)
                dismiss()
            }
        }
    }
}

private struct MyEventRow: View {
    let event: Event
    let stats: EventStats

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: MediaStorage.displayCoverURL(for: event))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title).font(.headline)
                    if !event.isPublished {
                        Text("Draft")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                }
                Text("\(event.mediaCount) items · \(event.date.eventDayString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(stats.views)", systemImage: "eye")
                    Label("\(stats.downloads)", systemImage: "square.and.arrow.down")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    MyEventsView().environmentObject(AppModel())
}
