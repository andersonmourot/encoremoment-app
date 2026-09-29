import SwiftUI
import PhotosUI
import UIKit
import EncoreMomentCore

/// The signed-in profile and a directory of other creators.
struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthService
    @State private var showingAuth = false
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var showingCreateEvent = false
    @State private var showingProfileSetup = false
    @State private var showingNotifications = false
    @State private var avatarSelection: PhotosPickerItem?
    @State private var avatarEditorImage: AvatarEditorImage?
    @State private var isUpdatingAvatar = false

    var body: some View {
        NavigationStack {
            List {
                if let creator = model.currentCreator {
                    Section {
                        CreatorHeader(
                            creator: creator,
                            avatarSelection: $avatarSelection,
                            isUpdatingAvatar: isUpdatingAvatar,
                            editProfile: { showingEditProfile = true }
                        )
                        if isUpdatingAvatar {
                            ProgressView("Updating profile picture...")
                        }
                    }
                    CreatorAnalyticsSection()
                    myEventsSection
                } else if let email = model.signedInEmail {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed in")
                                .font(.headline)
                            Text(email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Your saved items, follows, comments, and likes sync across your devices.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        Button {
                            showingProfileSetup = true
                        } label: {
                            Label("Complete Profile to Create Events", systemImage: "person.text.rectangle")
                        }
                    } header: {
                        Text("My Events")
                    } footer: {
                        Text("Add a display name and handle to start posting photos and videos from your events.")
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You're browsing as a viewer")
                                .font(.headline)
                            Text("Sign in to sync your favorites and follows across devices, comment, like, and post events.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button {
                                showingAuth = true
                            } label: {
                                Text("Sign In / Create Account").bold()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }

            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                            if model.unreadNotificationCount > 0 {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .accessibilityLabel("Notifications")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingAuth) {
                AuthView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingNotifications) {
                NavigationStack {
                    NotificationsView()
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                if let creator = model.currentCreator {
                    EditCreatorProfileView(creator: creator)
                }
            }
            .sheet(isPresented: $showingCreateEvent) {
                CreateEventView()
            }
            .sheet(isPresented: $showingProfileSetup) {
                ProfileCompleteProfileView()
            }
            .sheet(item: $avatarEditorImage) { editorImage in
                AvatarCropView(image: editorImage.image) { data in
                    await updateAvatar(with: data)
                }
            }
            .onChange(of: avatarSelection) { item in
                guard let item else { return }
                Task { await prepareAvatarEditor(with: item) }
            }
        }
    }

    private func prepareAvatarEditor(with item: PhotosPickerItem) async {
        defer { avatarSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            model.errorMessage = "Couldn't load that image. Please try another photo."
            return
        }
        avatarEditorImage = AvatarEditorImage(image: image)
    }

    private func updateAvatar(with data: Data) async -> Bool {
        isUpdatingAvatar = true
        defer { isUpdatingAvatar = false }
        return await model.updateProfileImage(data: data, fileExtension: "jpg")
    }

    private var myEventsSection: some View {
        let mine = model.myEvents()
        return Section {
            Button {
                showingCreateEvent = true
            } label: {
                Label("Create Event", systemImage: "plus")
            }

            if mine.isEmpty {
                Text("No events yet. Create an event page to start posting photos and videos.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mine) { event in
                    NavigationLink {
                        CreatorEventDetailView(event: event)
                    } label: {
                        ProfileEventRow(event: event, stats: model.stats(for: event.id))
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { mine[$0].id }
                    Task {
                        for id in ids {
                            await model.deleteEvent(id)
                        }
                    }
                }
            }
        } header: {
            Text("My Events")
        }
    }
}

private struct CreatorAnalyticsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            HStack(spacing: 0) {
                ProfileMetricTile(value: model.totalCreatorViews, label: "Views", systemImage: "eye")
                Divider().frame(height: 36)
                ProfileMetricTile(value: model.totalCreatorDownloads, label: "Downloads", systemImage: "square.and.arrow.down")
            }
            .padding(.vertical, 8)

            HStack(spacing: 0) {
                ProfileMetricTile(value: model.publishedEventCount, label: "Published", systemImage: "globe")
                Divider().frame(height: 36)
                ProfileMetricTile(value: model.draftEventCount, label: "Drafts", systemImage: "doc")
            }
            .padding(.vertical, 8)

            if let top = model.topEventByEngagement {
                NavigationLink {
                    CreatorEventDetailView(event: top)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Top event")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(top.title)
                                .font(.subheadline.weight(.semibold))
                            let stats = model.stats(for: top.id)
                            Text("\(stats.views) views - \(stats.downloads) downloads")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        } header: {
            Text("Analytics")
        }
    }
}

private struct ProfileMetricTile: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Label("\(value)", systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .labelStyle(.titleAndIcon)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AvatarEditorImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct EditCreatorProfileView: View {
    let creator: Creator
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var handle: String
    @State private var bio: String
    @State private var isSaving = false

    init(creator: Creator) {
        self.creator = creator
        _displayName = State(initialValue: creator.displayName)
        _handle = State(initialValue: creator.handle)
        _bio = State(initialValue: creator.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $displayName)
                    TextField("Handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Handle must be 3-30 characters using only lowercase letters, numbers, and underscores.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Profile")
                }

                Section {
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Tell fans what kind of events or media you share.")
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || !isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Creator.isValidHandle(handle)
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await model.updateCurrentCreatorProfile(
                displayName: displayName,
                handle: handle,
                bio: bio
            )
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct ProfileCompleteProfileView: View {
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

private struct ProfileEventRow: View {
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
                Text("\(event.mediaCount) items - \(event.date.eventDayString)")
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

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var settings: AppSettings
    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var selectedAccentHex = AppAccentColor.encorePurple.rawValue

    private var selectedTheme: Binding<AppTheme> {
        Binding {
            settings.theme
        } set: { newValue in
            settings.theme = newValue
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.currentCreator != nil {
                        Picker("Accent Color", selection: $selectedAccentHex) {
                            ForEach(AppAccentColor.allCases) { accent in
                                HStack {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 14, height: 14)
                                    Text(accent.displayName)
                                }
                                .tag(accent.rawValue)
                            }
                        }
                        .onChange(of: selectedAccentHex) { hex in
                            Task { await model.updateAccentColor(hex: hex) }
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose Light or Dark mode and personalize your account's accent color.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("API", value: AppConfig.apiBaseURL.host ?? AppConfig.apiBaseURL.absoluteString)
                } header: {
                    Text("About")
                }

                if model.currentCreator != nil {
                    Section {
                        NavigationLink {
                            ReportsView()
                        } label: {
                            Label("Reports", systemImage: "flag")
                        }
                    } header: {
                        Text("Moderation")
                    }
                }

                if auth.isAuthenticated {
                    Section {
                        Button(role: .destructive) {
                            showingLogoutConfirmation = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            if isDeletingAccount {
                                ProgressView()
                            } else {
                                Label("Delete Account", systemImage: "trash")
                            }
                        }
                        .disabled(isDeletingAccount)
                        if let error = auth.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Text("EncoreMoment lets artists and event companies share photos and videos from their events for fans to view and download.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .confirmationDialog(
            "Sign out?",
            isPresented: $showingLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in at any time.")
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, profile, events, and media. This cannot be undone.")
        }
        .onAppear {
            selectedAccentHex = model.accentColorHex
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        default:
            return "Unknown"
        }
    }

    private func signOut() {
        auth.logout()
        Task {
            await model.didSignOut()
            dismiss()
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            let deleted = await auth.deleteAccount()
            isDeletingAccount = false
            if deleted {
                await model.didSignOut()
                dismiss()
            }
        }
    }
}

private struct CreatorHeader: View {
    let creator: Creator
    @Binding var avatarSelection: PhotosPickerItem?
    let isUpdatingAvatar: Bool
    var editProfile: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $avatarSelection, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteImage(url: creator.avatarURL)
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(model.accentColor, lineWidth: 2))

                    ZStack {
                        Circle().fill(model.accentColor)
                        if isUpdatingAvatar {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingAvatar)
            .accessibilityLabel(creator.avatarURL == nil ? "Add Profile Picture" : "Change Profile Picture")

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(creator.displayName).font(.title3.bold())
                    Text(creator.displayHandle).foregroundStyle(model.accentColor)
                    if let bio = creator.bio {
                        Text(bio).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: editProfile) {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit Profile")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppModel())
        .environmentObject(AuthService())
}
