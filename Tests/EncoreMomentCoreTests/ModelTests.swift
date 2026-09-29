import XCTest
@testable import EncoreMomentCore

final class ModelTests: XCTestCase {
    func testHandleValidation() {
        XCTAssertTrue(Creator.isValidHandle("aurora_live"))
        XCTAssertTrue(Creator.isValidHandle("city01"))
        XCTAssertFalse(Creator.isValidHandle("ab"))            // too short
        XCTAssertFalse(Creator.isValidHandle("Aurora"))        // uppercase
        XCTAssertFalse(Creator.isValidHandle("has space"))     // space
        XCTAssertFalse(Creator.isValidHandle("dash-no"))       // dash
        XCTAssertFalse(Creator.isValidHandle(String(repeating: "a", count: 31)))
    }

    func testDisplayHandle() {
        XCTAssertEqual(SampleData.aurora.displayHandle, "@auroralive")
    }

    func testTitleValidation() {
        XCTAssertTrue(Event.isValidTitle("Summer Fest"))
        XCTAssertFalse(Event.isValidTitle("   "))
        XCTAssertFalse(Event.isValidTitle(""))
        XCTAssertFalse(Event.isValidTitle(String(repeating: "x", count: 101)))
    }

    func testEventMediaCounts() {
        let event = SampleData.events.first { $0.title == "Summer Fest 2026" }!
        XCTAssertEqual(event.photoCount, 3)
        XCTAssertEqual(event.videoCount, 1)
        XCTAssertEqual(event.mediaCount, 4)
    }

    func testFormattedDuration() {
        let video = MediaItem(eventId: UUID(), kind: .video, url: URL(string: "https://x/v.mp4")!, durationSeconds: 75)
        XCTAssertEqual(video.formattedDuration, "1:15")
        let photo = MediaItem(eventId: UUID(), kind: .photo, url: URL(string: "https://x/p.jpg")!)
        XCTAssertNil(photo.formattedDuration)
    }

    func testPreviewURLFallsBackToFullURL() {
        let full = URL(string: "https://x/full.jpg")!
        let item = MediaItem(eventId: UUID(), kind: .photo, url: full)
        XCTAssertEqual(item.previewURL, full)
    }

    func testMediaSortOrderDefaultsWhenMissing() throws {
        let eventId = UUID()
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "eventId": "\(eventId.uuidString)",
          "kind": "photo",
          "url": "https://x/photo.jpg",
          "isDownloadable": true,
          "createdAt": "2026-06-24T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(MediaItem.self, from: json)
        XCTAssertEqual(item.sortOrder, 0)
    }

    func testCodableRoundTrip() throws {
        let event = SampleData.events[0]
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(Event.self, from: data)
        XCTAssertEqual(event, decoded)
    }
}
