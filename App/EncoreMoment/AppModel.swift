import Foundation
import SwiftUI
import EncoreMomentCore

/// Observable view-model that bridges SwiftUI views to the ``EventStore``.
///
/// Holds the lightweight UI state (loaded events, the "signed in" creator) and
/// exposes async actions the views call. The concrete store is injected, so
/// swapping ``InMemoryEventStore`` for a networked store later is a one-line change.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var events: [Event] = [] {
        didSet { eventIndex = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    }
    /// Fully-loaded events (with media) keyed by id — list payloads are "lite"
    /// (no media array), so detail views fetch and cache the full event here.
    @Published private(set) var fullEvents: [UUID: Event] = [:]
    @Published private(set) var creators: [Creator] = [] {
        didSet { creatorIndex = Dictionary(creators.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    }
    private var eventIndex: [UUID: Event] = [:]
    private var creatorIndex: [UUID: Creator] = [:]
    /// Events owned by the current creator, including unpublished drafts.
    @Published private(set) var myEventsList: [Event] = []
    @Published private(set) var isLoading = false
    /// Whether the first load attempt has completed (used to distinguish the
    /// initial loading state from a genuinely empty feed).
    @Published private(set) var hasLoaded = false
    /// Set when loading the feed fails; surfaced inline with a Retry action.
    @Published private(set) var loadError: String?
    /// Set when a one-off action (create/update/delete) fails; surfaced as an alert.
    @Published var errorMessage: String?

    /// Whether more feed pages are available to load.
    @Published private(set) var hasMoreEvents = false
    /// Fraction (0–1) of the in-flight media upload, or `nil` when idle.
    @Published private(set) var uploadProgress: Double?

    /// Cross-event media feed (Discover → Moments), most-liked first.
    @Published private(set) var moments: [MediaFeedItem] = []
    @Published private(set) var hasMoreMoments = false
    /// Moments restricted to followed creators (Following → Moments).
    @Published private(set) var followedMoments: [MediaFeedItem] = []
    @Published private(set) var hasMoreFollowedMoments = false
    /// Media the signed-in user has liked (Profile → Liked).
    @Published private(set) var likedMediaItems: [MediaItem] = []
    /// Most-followed creators — the Search tab's default suggestions.
    @Published private(set) var topCreators: [Creator] = []

    static let feedPageSize = 25
    static let momentsPageSize = 30

    /// The profile currently acting in "creator mode" (the signed-in account),
    /// or `nil` when browsing as an anonymous viewer or a legacy account.
    @Published var currentCreator: Creator?

    /// The email of the signed-in account, or `nil` if anonymous.
    @Published private(set) var signedInEmail: String?

    /// The signed-in user's account id, used to authorize comment deletion.
    @Published private(set) var signedInUserID: UUID?

    /// Whether the signed-in account has a profile that can manage events.
    var isSignedIn: Bool { currentCreator != nil }

    /// Whether any account is signed in.
    var isAccountSignedIn: Bool { signedInEmail != nil }

    var accentColorHex: String {
        AppAccentColor.normalized(currentCreator?.accentColorHex)
    }

    var accentColor: Color {
        Color(hex: accentColorHex)
    }

    /// Event to present when the app is opened via a deep link.
    @Published var deepLinkedEvent: Event?

    /// The fan's on-device favorites and followed creators.
    @Published private(set) var fanPrefs = FanPreferences()

    /// Creators the fan has blocked (hidden from `creators`/`events`), kept
    /// separately so Settings can list and unblock them.
    @Published private(set) var blockedCreators: [Creator] = []

    /// Engagement stats for the current creator's events, keyed by event id.
    @Published private(set) var statsByEvent: [UUID: EventStats] = [:]
    @Published private(set) var notifications: [AppNotification] = []

    private let store: EventStore
    /// Swapped between the on-device file store (anonymous) and the API store
    /// (signed in) so favorites/follows sync to the account when logged in.
    private var fanStore: FanPreferencesStore
    private let analyticsStore: AnalyticsStore
    private let socialStore: SocialStore
    private let mediaUploadService: MediaUploadService
    private let reportService: ReportService
    private let notificationService: NotificationService

    init(
        store: EventStore? = nil,
        fanStore: FanPreferencesStore? = nil,
        analyticsStore: AnalyticsStore? = nil,
        socialStore: SocialStore? = nil,
        mediaUploadService: MediaUploadService? = nil,
        reportService: ReportService? = nil,
        notificationService: NotificationService? = nil,
        currentCreator: Creator? = nil
    ) {
        self.store = store ?? AppModel.makeDefaultStore()
        self.fanStore = fanStore ?? AppModel.makeDefaultFanStore()
        self.analyticsStore = analyticsStore ?? AppModel.makeDefaultAnalyticsStore()
        self.socialStore = socialStore ?? AppModel.makeDefaultSocialStore()
        self.mediaUploadService = mediaUploadService ?? MediaUploadService()
        self.reportService = reportService ?? ReportService()
        self.notificationService = notificationService ?? NotificationService()
        self.currentCreator = currentCreator
    }

    /// The shared backend so events and uploads are visible across all users.
    /// Wrapped in an ``AuthenticatedTransport`` so mutations carry the bearer token.
    private static func makeDefaultStore() -> EventStore {
        let transport = ETagCachingTransport(
            wrapping: AuthenticatedTransport { TokenHolder.shared.token }
        )
        return APIEventStore(baseURL: AppConfig.apiBaseURL, transport: transport)
    }

    private static func makeDefaultFanStore() -> FanPreferencesStore {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("fan-preferences.json")
        return (try? FileFanPreferencesStore(fileURL: url)) ?? InMemoryFanPreferencesStore()
    }

    /// The account-backed fan store (favorites/follows sync across devices).
    private static func makeAPIFanStore() -> FanPreferencesStore {
        let transport = AuthenticatedTransport { TokenHolder.shared.token }
        return APIFanPreferencesStore(baseURL: AppConfig.apiBaseURL, transport: transport)
    }

    private static func makeDefaultAnalyticsStore() -> AnalyticsStore {
        let transport = AuthenticatedTransport { TokenHolder.shared.token }
        return APIAnalyticsStore(baseURL: AppConfig.apiBaseURL, transport: transport)
    }

    private static func makeDefaultSocialStore() -> SocialStore {
        let transport = ETagCachingTransport(
            wrapping: AuthenticatedTransport { TokenHolder.shared.token }
        )
        return APISocialStore(baseURL: AppConfig.apiBaseURL, transport: transport)
    }

    /// Loads initial data. When restoring a signed-in `account`, switches to the
    /// account-backed fan store so favorites/follows come from the server.
    func bootstrap(account: Account? = nil) async {
        if let account {
            currentCreator = account.creator
            signedInEmail = account.email
            signedInUserID = account.id
            fanStore = AppModel.makeAPIFanStore()
        }
        fanPrefs = (try? await fanStore.preferences()) ?? FanPreferences()
        await refresh()
        #if canImport(UIKit)
        if account != nil { PushRegistration.shared.syncNow() }
        #endif
    }

    func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            async let published = store.publishedEventsPage(
                limit: Self.feedPageSize, offset: 0, followingOnly: false, popular: true
            )
            async let people = store.allCreators()
            async let feed = store.mediaFeed(followingOnly: false, limit: Self.momentsPageSize, offset: 0)
            async let followedFeed = store.mediaFeed(
                followingOnly: true, limit: Self.momentsPageSize, offset: 0
            )
            async let top = store.topCreators(limit: 20)
            let firstPage = try await published
            let allCreators = try await people
            // Blocked creators are hidden from every feed; the server also
            // filters for signed-in users, and we filter here so anonymous
            // blocks and instant removal work too.
            self.events = firstPage.filter { !fanPrefs.isBlocked($0.creatorId) }
            self.hasMoreEvents = firstPage.count == Self.feedPageSize
            self.creators = allCreators.filter { !fanPrefs.isBlocked($0.id) }
            let feedPage = (try? await feed) ?? []
            self.moments = feedPage.filter { !fanPrefs.isBlocked($0.creatorID) }
            self.hasMoreMoments = feedPage.count == Self.momentsPageSize
            let followedPage = (try? await followedFeed) ?? []
            self.followedMoments = followedPage.filter { !fanPrefs.isBlocked($0.creatorID) }
            self.hasMoreFollowedMoments = followedPage.count == Self.momentsPageSize
            self.topCreators = ((try? await top) ?? []).filter { !fanPrefs.isBlocked($0.id) }

            // The remaining loads are independent — run them in parallel.
            let creatorId = currentCreator?.id
            async let likedTask = isAccountSignedIn
                ? ((try? await socialStore.likedMedia()) ?? [])
                : []
            async let remoteBlocked = (try? await fanStore.blockedCreators()) ?? []
            async let mineTask: [Event] = creatorId == nil
                ? []
                : ((try? await store.events(forCreator: creatorId!)) ?? [])
            async let statsTask = creatorId == nil
                ? []
                : ((try? await analyticsStore.creatorStats()) ?? [])
            async let notificationsTask = isAccountSignedIn
                ? ((try? await notificationService.notifications()) ?? [])
                : []

            self.likedMediaItems = await likedTask
            // Signed-in users get blocked profiles from /me/blocks (the server
            // filters them out of /creators); anonymous users derive them here.
            let derived = allCreators.filter { fanPrefs.isBlocked($0.id) }
            let remote = await remoteBlocked
            self.blockedCreators = derived + remote.filter { r in !derived.contains(where: { $0.id == r.id }) }
            self.myEventsList = await mineTask
            statsByEvent = Dictionary((await statsTask).map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
            notifications = await notificationsTask
        } catch {
            loadError = error.localizedDescription
        }
        await refreshFullEvents()
    }

    /// Appends the next page of the public feed. Called when the user scrolls
    /// near the bottom; silently no-ops when there's nothing more to load.
    func loadMoreEvents() async {
        guard hasMoreEvents, !isLoading else { return }
        guard let page = try? await store.publishedEventsPage(
            limit: Self.feedPageSize, offset: events.count,
            followingOnly: false, popular: true
        ) else { return }
        let seen = Set(events.map(\.id))
        let fresh = page.filter { !fanPrefs.isBlocked($0.creatorId) && !seen.contains($0.id) }
        events.append(contentsOf: fresh)
        hasMoreEvents = page.count == Self.feedPageSize
    }

    /// Appends the next page of Moments media.
    func loadMoreMoments() async {
        guard hasMoreMoments else { return }
        guard let page = try? await store.mediaFeed(
            followingOnly: false, limit: Self.momentsPageSize, offset: moments.count
        ) else { return }
        let seen = Set(moments.map(\.id))
        let fresh = page.filter { !fanPrefs.isBlocked($0.creatorID) && !seen.contains($0.id) }
        moments.append(contentsOf: fresh)
        hasMoreMoments = page.count == Self.momentsPageSize
    }

    /// Appends the next page of followed Moments media.
    func loadMoreFollowedMoments() async {
        guard hasMoreFollowedMoments else { return }
        guard let page = try? await store.mediaFeed(
            followingOnly: true, limit: Self.momentsPageSize, offset: followedMoments.count
        ) else { return }
        let seen = Set(followedMoments.map(\.id))
        let fresh = page.filter { !fanPrefs.isBlocked($0.creatorID) && !seen.contains($0.id) }
        followedMoments.append(contentsOf: fresh)
        hasMoreFollowedMoments = page.count == Self.momentsPageSize
    }

    /// Refreshes only the content feeds — used after mutations where social
    /// state (notifications, stats, blocks) can't have changed.
    func refreshFeeds() async {
        async let published = store.publishedEventsPage(
            limit: Self.feedPageSize, offset: 0, followingOnly: false, popular: true
        )
        async let people = store.allCreators()
        async let feed = store.mediaFeed(followingOnly: false, limit: Self.momentsPageSize, offset: 0)
        async let followedFeed = store.mediaFeed(followingOnly: true, limit: Self.momentsPageSize, offset: 0)
        let creatorId = currentCreator?.id
        let existingMine = myEventsList
        async let mine: [Event] = creatorId == nil
            ? []
            : ((try? await store.events(forCreator: creatorId!)) ?? existingMine)
        if let firstPage = try? await published {
            events = firstPage.filter { !fanPrefs.isBlocked($0.creatorId) }
            hasMoreEvents = firstPage.count == Self.feedPageSize
        }
        if let allCreators = try? await people {
            creators = allCreators.filter { !fanPrefs.isBlocked($0.id) }
        }
        if let feedPage = try? await feed {
            moments = feedPage.filter { !fanPrefs.isBlocked($0.creatorID) }
            hasMoreMoments = feedPage.count == Self.momentsPageSize
        }
        if let followedPage = try? await followedFeed {
            followedMoments = followedPage.filter { !fanPrefs.isBlocked($0.creatorID) }
            hasMoreFollowedMoments = followedPage.count == Self.momentsPageSize
        }
        myEventsList = await mine
        await refreshFullEvents()
    }

    // MARK: Analytics

    /// Stats for one of the creator's events (zeroes until loaded/recorded).
    func stats(for eventID: UUID) -> EventStats {
        statsByEvent[eventID] ?? EventStats(eventID: eventID)
    }

    var totalCreatorViews: Int {
        myEventsList.reduce(0) { $0 + stats(for: $1.id).views }
    }

    var totalCreatorDownloads: Int {
        myEventsList.reduce(0) { $0 + stats(for: $1.id).downloads }
    }

    var publishedEventCount: Int {
        myEventsList.filter(\.isPublished).count
    }

    var draftEventCount: Int {
        myEventsList.filter { !$0.isPublished }.count
    }

    var topEventByEngagement: Event? {
        myEventsList.max { lhs, rhs in
            let lhsStats = stats(for: lhs.id)
            let rhsStats = stats(for: rhs.id)
            return (lhsStats.views + lhsStats.downloads) < (rhsStats.views + rhsStats.downloads)
        }
    }

    /// Records that a fan opened an event page. Fire-and-forget.
    func recordView(_ eventID: UUID) async {
        try? await analyticsStore.recordView(eventID: eventID)
    }

    /// Records `count` downloads from an event. Fire-and-forget.
    func recordDownloads(eventID: UUID, count: Int) async {
        guard count > 0 else { return }
        try? await analyticsStore.recordDownloads(eventID: eventID, count: count)
    }

    func creator(id: UUID) -> Creator? {
        creatorIndex[id]
    }

    func myEvents() -> [Event] { myEventsList }

    // MARK: Mutations

    func createEvent(
        title: String,
        details: String?,
        location: String?,
        date: Date,
        allowsCommunityUploads: Bool = false,
        inviteOnly: Bool = false
    ) async {
        guard let creator = currentCreator else { return }
        let event = Event(
            creatorId: creator.id,
            title: title,
            details: details?.nilIfBlank,
            location: location?.nilIfBlank,
            date: date,
            allowsCommunityUploads: allowsCommunityUploads,
            inviteOnly: inviteOnly
        )
        await perform { try await self.store.createEvent(event) }
    }

    func addMedia(_ item: MediaItem, to eventId: UUID) async {
        await perform { try await self.store.addMedia(item, toEvent: eventId) }
    }

    /// Uploads a media file (streamed from disk, not held in memory). When
    /// `refreshes` is false the caller is expected to refresh once after the
    /// batch — avoids a full feed reload per file during multi-picks.
    func uploadMedia(
        fileURL: URL,
        fileExtension: String,
        kind: MediaKind,
        thumbnailData: Data?,
        to eventId: UUID,
        refreshes: Bool = true
    ) async throws {
        uploadProgress = 0
        defer { uploadProgress = nil }
        _ = try await mediaUploadService.upload(
            fileURL: fileURL,
            fileExtension: fileExtension,
            kind: kind,
            to: eventId,
            thumbnailData: thumbnailData
        ) { [weak self] fraction in
            Task { @MainActor in self?.uploadProgress = fraction }
        }
        if refreshes { await refreshFeeds() }
    }

    func updateProfileImage(data: Data, fileExtension: String) async -> Bool {
        do {
            let creator = try await mediaUploadService.uploadAvatar(
                data: data,
                fileExtension: fileExtension
            )
            currentCreator = creator
            creators = creators.map { $0.id == creator.id ? creator : $0 }
            if !creators.contains(where: { $0.id == creator.id }) {
                creators.append(creator)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateCurrentCreatorProfile(displayName: String, handle: String, bio: String?) async -> Bool {
        guard var creator = currentCreator else { return false }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Display name is required."
            return false
        }
        guard Creator.isValidHandle(handle) else {
            errorMessage = "Handle must be 3-30 letters, numbers, or underscores."
            return false
        }

        creator.displayName = trimmedName
        creator.handle = handle
        creator.bio = bio?.nilIfBlank
        do {
            try await store.upsertCreator(creator)
            currentCreator = creator
            creators = creators.map { $0.id == creator.id ? creator : $0 }
            if !creators.contains(where: { $0.id == creator.id }) {
                creators.append(creator)
            }
            await refresh()
            return true
        } catch {
            errorMessage = "Couldn't update your profile. Please try again."
            return false
        }
    }

    func updateAccentColor(hex: String) async -> Bool {
        guard var creator = currentCreator else { return false }
        creator.accentColorHex = AppAccentColor.normalized(hex)
        do {
            try await store.upsertCreator(creator)
            currentCreator = creator
            creators = creators.map { $0.id == creator.id ? creator : $0 }
            if !creators.contains(where: { $0.id == creator.id }) {
                creators.append(creator)
            }
            return true
        } catch {
            errorMessage = "Couldn't update your theme color. Please try again."
            return false
        }
    }

    func updateEvent(_ event: Event) async {
        await perform { try await self.store.updateEvent(event) }
    }

    func setPublished(_ isPublished: Bool, for eventId: UUID) async {
        guard var event = await resolveEvent(id: eventId) else { return }
        event.isPublished = isPublished
        await updateEvent(event)
    }

    func deleteEvent(_ id: UUID) async {
        await perform { try await self.store.deleteEvent(id: id) }
    }

    func removeMedia(_ mediaId: UUID, from eventId: UUID) async {
        await perform { try await self.store.removeMedia(id: mediaId, fromEvent: eventId) }
    }

    func setCover(media: MediaItem, for eventId: UUID) async {
        guard var event = await resolveEvent(id: eventId) else { return }
        event.coverImageURL = media.previewURL
        await updateEvent(event)
    }

    func reorderMedia(_ media: [MediaItem], in eventId: UUID) async {
        guard var event = await resolveEvent(id: eventId) else { return }
        event.media = media.enumerated().map { index, item in
            var copy = item
            copy.sortOrder = index
            return copy
        }
        await updateEvent(event)
    }

    // MARK: Event members (invited viewers & collaborators)

    /// The invited-member list of an owned event (empty on failure).
    func eventMembers(forEvent eventID: UUID) async -> [EventMember] {
        (try? await store.members(of: eventID)) ?? []
    }

    /// The signed-in viewer's role on this event, if they were invited.
    func myMembership(in eventID: UUID) async -> EventMemberRole? {
        try? await store.myMembership(in: eventID)
    }

    /// Whether the signed-in viewer may add media to this event: the owner, an
    /// invited collaborator, or anyone when community uploads are enabled.
    func canAddMedia(to event: Event) async -> Bool {
        guard isAccountSignedIn else { return false }
        if currentCreator?.id == event.creatorId { return true }
        if event.allowsCommunityUploads { return true }
        return (try? await store.myMembership(in: event.id))?.canUpload ?? false
    }

    /// Invites (or re-roles) a creator by handle. Returns the updated member
    /// list; on failure surfaces `errorMessage` and returns nil.
    func inviteMember(handle: String, role: EventMemberRole, to eventID: UUID) async -> [EventMember]? {
        let cleaned = handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return nil }
        do {
            return try await store.inviteMember(handle: cleaned, role: role, to: eventID)
        } catch {
            errorMessage = "Couldn't invite \"\(cleaned)\". Check the handle and try again."
            return nil
        }
    }

    func removeMember(_ member: EventMember, from eventID: UUID) async -> [EventMember]? {
        do {
            return try await store.removeMember(creatorID: member.creatorID, from: eventID)
        } catch {
            errorMessage = "Couldn't remove this member. Please try again."
            return nil
        }
    }

    /// Resolves and presents an event opened via a ``DeepLink`` URL; invite
    /// links redeem the membership first, then open the event.
    func handle(url: URL) async {
        switch DeepLink(url: url) {
        case .event(let id):
            deepLinkedEvent = await resolveEvent(id: id)
        case .invite(let code):
            await redeemInviteLink(code: code)
        case .creator, nil:
            break
        }
    }

    /// Joins an event via an invite link, then opens it.
    func redeemInviteLink(code: String) async {
        guard isAccountSignedIn else {
            errorMessage = "Sign in to accept this event invite."
            return
        }
        do {
            let event = try await store.redeemInviteLink(code: code)
            await refresh()
            deepLinkedEvent = event
        } catch {
            errorMessage = "This invite link is invalid or expired."
        }
    }

    /// Creates a shareable invite link for an owned event.
    func createInviteLink(role: EventMemberRole, for eventID: UUID) async -> EventInviteLink? {
        do {
            return try await store.createInviteLink(role: role, for: eventID)
        } catch {
            errorMessage = "Couldn't create an invite link. Please try again."
            return nil
        }
    }

    /// Looks up an event for a mutation — must have its full media array, so
    /// lite list entries and partial fetches fall through to a store load.
    private func resolveEvent(id: UUID) async -> Event? {
        if let local = event(id: id), !local.media.isEmpty { return local }
        return await fetchFullEvent(id: id)
    }

    /// Loads an event by id — a cached full copy if present, the loaded list
    /// otherwise, falling back to a store fetch.
    func loadEvent(id: UUID) async -> Event? {
        if let cached = event(id: id) { return cached }
        return try? await store.event(id: id)
    }

    /// Fetches the full event (with media) from the store and caches it, so
    /// views reading `event(id:)` see the media array reactively.
    @discardableResult
    func fetchFullEvent(id: UUID) async -> Event? {
        guard let event = try? await store.event(id: id) else { return nil }
        fullEvents[id] = event
        return event
    }

    /// Refreshes every cached full event (usually just the open detail page)
    /// after feed data is reloaded.
    private func refreshFullEvents() async {
        for id in fullEvents.keys {
            if let fresh = try? await store.event(id: id) {
                fullEvents[id] = fresh
            }
        }
    }

    func event(id: UUID) -> Event? {
        fullEvents[id] ?? eventIndex[id] ?? myEventsList.first { $0.id == id }
    }

    /// Called after a successful sign-in/registration. Switches to the account's
    /// server-backed fan store and merges any on-device favorites/follows up to it
    /// so nothing collected while anonymous is lost.
    func didSignIn(_ account: Account) async {
        let local = (try? await fanStore.preferences()) ?? fanPrefs
        currentCreator = account.creator
        signedInEmail = account.email
        signedInUserID = account.id
        let api = AppModel.makeAPIFanStore()
        fanStore = api
        if let merged = try? await api.merge(local) {
            fanPrefs = merged
        } else {
            fanPrefs = (try? await api.preferences()) ?? FanPreferences()
        }
        await refresh()
        #if canImport(UIKit)
        PushRegistration.shared.syncNow()
        #endif
    }

    /// Clears account state on sign-out (token is cleared separately by AuthService)
    /// and returns to the on-device fan store.
    func didSignOut() async {
        currentCreator = nil
        signedInEmail = nil
        signedInUserID = nil
        myEventsList = []
        notifications = []
        fanStore = AppModel.makeDefaultFanStore()
        fanPrefs = (try? await fanStore.preferences()) ?? FanPreferences()
        await refresh()
    }

    // MARK: Fan preferences (favorites & follows)

    func isFavorite(_ eventID: UUID) -> Bool { fanPrefs.isFavorite(eventID) }
    func isFollowing(_ creatorID: UUID) -> Bool { fanPrefs.isFollowing(creatorID) }

    func toggleFavorite(_ eventID: UUID) async {
        let newValue = !fanPrefs.isFavorite(eventID)
        do {
            fanPrefs = try await fanStore.setFavorite(eventID: eventID, newValue)
        } catch {
            errorMessage = "Couldn't \(newValue ? "save" : "remove") this favorite. Please try again."
        }
    }

    func toggleFollow(_ creatorID: UUID) async {
        let newValue = !fanPrefs.isFollowing(creatorID)
        do {
            fanPrefs = try await fanStore.setFollowing(creatorID: creatorID, newValue)
        } catch {
            errorMessage = "Couldn't \(newValue ? "follow" : "unfollow") right now. Please try again."
        }
    }

    // MARK: Blocking

    func isBlocked(_ creatorID: UUID) -> Bool { fanPrefs.isBlocked(creatorID) }

    /// Blocks or unblocks a creator. Blocking removes their events/profile from
    /// the visible feed immediately (and files a moderation report server-side).
    func setBlocked(_ creatorID: UUID, _ blocked: Bool) async {
        do {
            fanPrefs = try await fanStore.setBlocked(creatorID: creatorID, blocked)
            if blocked {
                // Instant feed removal — don't wait for the next refresh.
                events.removeAll { $0.creatorId == creatorID }
                if let index = creators.firstIndex(where: { $0.id == creatorID }) {
                    let removed = creators.remove(at: index)
                    if !blockedCreators.contains(where: { $0.id == removed.id }) {
                        blockedCreators.append(removed)
                    }
                }
            } else {
                blockedCreators.removeAll { $0.id == creatorID }
                // Refetch so the unblocked creator's content is restored.
                await refresh()
            }
        } catch {
            errorMessage = "Couldn't \(blocked ? "block" : "unblock") this user. Please try again."
        }
    }

    /// Favorited events that are still available in the loaded feed, newest first.
    var favoriteEvents: [Event] {
        EventFeed.events(events, withIDs: fanPrefs.favoriteEventIDs)
    }

    /// Creators the fan follows.
    var followedCreators: [Creator] {
        creators.filter { fanPrefs.isFollowing($0.id) }
    }

    /// Published events from creators the fan follows, newest first.
    var followedEvents: [Event] {
        EventFeed.sortedByDate(EventFeed.events(events, byCreators: fanPrefs.followedCreatorIDs))
    }

    // MARK: Social (comments & likes)

    /// Loads the comments for an event, oldest first.
    func comments(forEvent eventID: UUID) async -> [Comment] {
        (try? await socialStore.comments(forEvent: eventID)) ?? []
    }

    /// Comments on one media item inside an event.
    func comments(forMedia mediaID: UUID, in eventID: UUID) async -> [Comment] {
        (try? await socialStore.comments(forMedia: mediaID, in: eventID)) ?? []
    }

    /// Posts a comment; returns the created comment, or nil on failure.
    func addComment(eventID: UUID, body: String) async -> Comment? {
        do {
            return try await socialStore.addComment(eventID: eventID, body: body)
        } catch {
            errorMessage = "Couldn't post your comment. Please try again."
            return nil
        }
    }

    /// Posts a comment on a specific media item; returns it, or nil on failure.
    func addComment(mediaID: UUID, eventID: UUID, body: String) async -> Comment? {
        do {
            return try await socialStore.addComment(mediaID: mediaID, eventID: eventID, body: body)
        } catch {
            errorMessage = "Couldn't post your comment. Please try again."
            return nil
        }
    }

    /// Refreshes the signed-in user's liked-media list (Profile → Liked).
    func loadLikedMedia() async {
        guard isAccountSignedIn else { likedMediaItems = []; return }
        likedMediaItems = (try? await socialStore.likedMedia()) ?? []
    }

    /// Deletes a comment. The server enforces author/owner authorization.
    func deleteComment(_ comment: Comment) async -> Bool {
        do {
            try await socialStore.deleteComment(id: comment.id, eventID: comment.eventID)
            return true
        } catch {
            errorMessage = "Couldn't delete this comment. Please try again."
            return false
        }
    }

    /// Whether the current account may delete `comment` (its author, or the
    /// owning creator of `event`).
    func canDelete(_ comment: Comment, in event: Event) -> Bool {
        if let userID = signedInUserID, comment.authorID == userID { return true }
        if let creator = currentCreator, creator.id == event.creatorId { return true }
        return false
    }

    func canDeleteMedia(_ item: MediaItem, in event: Event) -> Bool {
        if let creator = currentCreator, creator.id == event.creatorId { return true }
        if let userID = signedInUserID, item.uploaderID == userID { return true }
        return false
    }

    func commentLikeSummary(commentID: UUID, eventID: UUID) async -> LikeSummary {
        (try? await socialStore.commentLikeSummary(commentID: commentID, eventID: eventID)) ?? LikeSummary(eventID: commentID)
    }

    func setCommentLike(commentID: UUID, eventID: UUID, _ liked: Bool) async -> LikeSummary? {
        do {
            return try await socialStore.setCommentLike(commentID: commentID, eventID: eventID, liked)
        } catch {
            errorMessage = "Couldn't update your comment like. Please try again."
            return nil
        }
    }

    func mediaLikeSummary(mediaID: UUID, eventID: UUID) async -> LikeSummary {
        (try? await socialStore.mediaLikeSummary(mediaID: mediaID, eventID: eventID)) ?? LikeSummary(eventID: mediaID)
    }

    func setMediaLike(mediaID: UUID, eventID: UUID, _ liked: Bool) async -> LikeSummary? {
        do {
            return try await socialStore.setMediaLike(mediaID: mediaID, eventID: eventID, liked)
        } catch {
            errorMessage = "Couldn't update your media like. Please try again."
            return nil
        }
    }

    func likeSummary(forEvent eventID: UUID) async -> LikeSummary {
        (try? await socialStore.likeSummary(forEvent: eventID)) ?? LikeSummary(eventID: eventID)
    }

    /// Event + media + comment like state in one call.
    func likeSummaries(forEvent eventID: UUID) async -> EventLikeSummaries {
        (try? await socialStore.likeSummaries(forEvent: eventID))
            ?? EventLikeSummaries(event: LikeSummary(eventID: eventID))
    }

    /// Toggles the viewer's like; returns the updated summary, or nil on failure.
    func setLike(eventID: UUID, _ liked: Bool) async -> LikeSummary? {
        do {
            return try await socialStore.setLike(eventID: eventID, liked)
        } catch {
            errorMessage = "Couldn't update your like. Please try again."
            return nil
        }
    }

    func submitReport(_ report: ReportRequest) async -> Bool {
        do {
            try await reportService.submit(report)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func moderationReports() async -> [Report] {
        do {
            return try await reportService.reports()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func deleteReport(id: UUID) async -> Bool {
        do {
            try await reportService.deleteReport(id: id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var unreadNotificationCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    func loadNotifications() async {
        guard isAccountSignedIn else {
            notifications = []
            return
        }
        notifications = (try? await notificationService.notifications()) ?? []
    }

    func markNotificationRead(_ id: UUID) async {
        if let updated = try? await notificationService.markRead(id: id) {
            notifications = notifications.map { $0.id == id ? updated : $0 }
        }
    }

    func markAllNotificationsRead() async {
        do {
            try await notificationService.markAllRead()
            notifications = notifications.map { item in
                var copy = item
                copy.isRead = true
                return copy
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mutations refetch only the content feeds — notifications, stats, and
    /// block state can't have changed, so a full `refresh()` is overkill.
    private func perform(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            await refreshFeeds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
