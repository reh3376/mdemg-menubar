import XCTest
@testable import MdemgMenuBar

final class FormattingTests: XCTestCase {
    func testFormatDurationSeconds() {
        XCTAssertEqual(Formatting.formatDuration(45), "45s")
    }

    func testFormatDurationMinutes() {
        XCTAssertEqual(Formatting.formatDuration(125), "2m 5s")
    }

    func testFormatDurationHours() {
        XCTAssertEqual(Formatting.formatDuration(4980), "1h 23m")
    }

    func testFormatDurationZero() {
        XCTAssertEqual(Formatting.formatDuration(0), "0s")
    }

    func testFormatNumber() {
        XCTAssertEqual(Formatting.formatNumber(34416), "34,416")
        XCTAssertEqual(Formatting.formatNumber(0), "0")
        XCTAssertEqual(Formatting.formatNumber(1000000), "1,000,000")
    }

    func testFormatPercentage() {
        XCTAssertEqual(Formatting.formatPercentage(0.875), "87.5%")
        XCTAssertEqual(Formatting.formatPercentage(1.0), "100.0%")
    }

    func testFormatHealthScore() {
        XCTAssertEqual(Formatting.formatHealthScore(0.783), "0.783")
        XCTAssertEqual(Formatting.formatHealthScore(1.0), "1.000")
    }

    func testTimeAgo() {
        let recent = Date().addingTimeInterval(-30)
        XCTAssertTrue(Formatting.timeAgo(from: recent).hasSuffix("s ago"))

        let minutes = Date().addingTimeInterval(-120)
        XCTAssertEqual(Formatting.timeAgo(from: minutes), "2m ago")
    }
}
