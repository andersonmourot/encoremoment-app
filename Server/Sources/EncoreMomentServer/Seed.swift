import Vapor
import Fluent
import EncoreMomentCore

/// Populates an empty database with the shared sample creators and events so a
/// fresh deployment isn't blank.
func seedIfEmpty(_ app: Application) async throws {
    let existing = try await CreatorModel.query(on: app.db).count()
    guard existing == 0 else { return }

    for creator in SampleData.creators {
        try await CreatorModel(from: creator).create(on: app.db)
    }
    for event in SampleData.events {
        try await EventModel(from: event).create(on: app.db)
        for item in event.media {
            let media = MediaModel(from: item)
            media.$event.id = event.id
            try await media.create(on: app.db)
        }
    }
    app.logger.info("Seeded sample data")
}
