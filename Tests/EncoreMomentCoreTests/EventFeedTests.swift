import XCTest
@testable import EncoreMomentCore

final class EventFeedTests: XCTestCase {
    func testSearchMatchesTitleDetailsAndLocation() {
        let events = SampleData.events
        XCTAssertEqual(EventFeed.search(events, query: "summer").count, 1)
        XCTAssertEqual(EventFeed.search(events, query: "block 9").count, 1)      // location
        XCTAssertEqual(EventFeed.search(events, query: "underground").count, 1)  // details
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(EventFeed.search(SampleData.events, query: "WAREHOUSE").count, 1)
    }

    func testEmptyQueryReturnsAll() {
        let events = SampleData.events
        XCTAssertEqual(EventFeed.search(events, query: "   ").count, events.count)
    }

    func testSortedByDateNewestFirst() {
        let sorted = EventFeed.sortedByDate(SampleData.events)
        for i in 1..<sorted.count {
            XCTAssertGreaterThanOrEqual(sorted[i - 1].date, sorted[i].date)
        }
    }

    func testGroupedByDayIsSortedNewestFirst() {
        let groups = EventFeed.groupedByDay(SampleData.events)
        XCTAssertFalse(groups.isEmpty)
        for i in 1..<groups.count {
            XCTAssertGreaterThan(groups[i - 1].day, groups[i].day)
        }
    }
}
