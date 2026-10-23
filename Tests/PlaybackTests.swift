import XCTest
@testable import ZhuiShiFan

final class PlaybackTests: XCTestCase {
    func testSeekingClampsAtBothEnds() {
        XCTAssertEqual(PlaybackSeeking.target(start: 10, translation: -100, width: 100, duration: 600), 0)
        XCTAssertEqual(PlaybackSeeking.target(start: 590, translation: 100, width: 100, duration: 600), 600)
    }

    func testSeekingUsesShortClipDurationAndLongClipTwoMinuteRange() {
        XCTAssertEqual(PlaybackSeeking.target(start: 10, translation: 50, width: 100, duration: 60), 40)
        XCTAssertEqual(PlaybackSeeking.target(start: 100, translation: 50, width: 100, duration: 600), 160)
    }

    func testSeekingRejectsUnknownDurationAndInvalidGeometry() {
        for duration in [Double.nan, .infinity, 0, -1] {
            XCTAssertNil(PlaybackSeeking.target(start: 10, translation: 50, width: 100, duration: duration))
        }
        XCTAssertNil(PlaybackSeeking.target(start: .nan, translation: 50, width: 100, duration: 600))
        XCTAssertNil(PlaybackSeeking.target(start: 10, translation: 50, width: 0, duration: 600))
    }
}
