import SwiftUI
import EncoreMomentCore

struct CreatorProfileView: View {
    let creator: Creator
    @EnvironmentObject private var model: AppModel
    @State private var reportTarget: ReportTarget?

    private var liveCreator: Creator {
        model.creator(id: creator.id) ?? model.currentCreator.flatMap { $0.id == creator.id ? $0 : nil } ?? creator
    }

    private var events: [Event] {
        model.events.filter { $0.creatorId == creator.id }
    }

    private var isCurrentCreator: Bool {
        model.currentCreator?.id == creator.id
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        RemoteImage(url: liveCreator.avatarURL)
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(model.accentColor, lineWidth: 2))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(liveCreator.displayName)
                                    .font(.title3.bold())
                                if liveCreator.isVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(model.accentColor)
                                }
                            }
                            Text(liveCreator.displayHandle)
                                .foregroundStyle(model.accentColor)
                        }
                    }

                    if let bio = liveCreator.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !isCurrentCreator {
                        Button {
                            Task { await model.toggleFollow(liveCreator.id) }
                        } label: {
                            Label(
                                model.isFollowing(liveCreator.id) ? "Following" : "Follow",
                                systemImage: model.isFollowing(liveCreator.id) ? "checkmark" : "plus"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Events") {
                if events.isEmpty {
                    Text("No published events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            CreatorProfileEventRow(event: event)
                        }
                    }
                }
            }
        }
        .navigationTitle(liveCreator.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isCurrentCreator {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reportTarget = ReportTarget(
                            targetType: .creator,
                            targetID: liveCreator.id,
                            eventID: nil,
                            title: "Report Creator"
                        )
                    } label: {
                        Image(systemName: "flag")
                    }
                    .accessibilityLabel("Report creator")
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target)
        }
    }
}

private struct CreatorProfileEventRow: View {
    let event: Event

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: MediaStorage.displayCoverURL(for: event))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.headline)
                Text(event.date.eventDayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
