import XCTest
@testable import EncoreMomentCore

final class DeepLinkTests: XCTestCase {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!

    func testEventAppURLRoundTrip() throws {
        let link = DeepLink.event(id)
        XCTAssertEqual(link.appURL.absoluteString, "encoremoment://event/\(id.uuidString)")
        XCTAssertEqual(DeepLink(url: link.appURL), link)
    }

    func testEventWebURLRoundTrip() throws {
        let link = DeepLink.event(id)
        XCTAssertEqual(link.webURL.absoluteString, "https://encoremoment.app/event/\(id.uuidString)")
        XCTAssertEqual(DeepLink(url: link.webURL), link)
    }

    func testCreatorRoundTrip() throws {
        let link = DeepLink.creator(id)
        XCTAssertEqual(DeepLink(url: link.appURL), link)
        XCTAssertEqual(DeepLink(url: link.webURL), link)
    }

    func testRejectsUnknownURLs() {
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/event/\(id.uuidString)")!))
        XCTAssertNil(DeepLink(url: URL(string: "encoremoment://event/not-a-uuid")!))
        XCTAssertNil(DeepLink(url: URL(string: "encoremoment://unknown/\(id.uuidString)")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://encoremoment.app/event")!))
    }
}
