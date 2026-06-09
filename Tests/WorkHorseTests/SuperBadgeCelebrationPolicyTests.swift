import XCTest
@testable import WorkHorse

final class SuperBadgeCelebrationPolicyTests: XCTestCase {
    func testPresentsAnUncelebratedEarnedBadgeWhenSessionIsAvailable() {
        XCTAssertTrue(
            SuperBadgeCelebrationPolicy.shouldPresent(
                hasCompletedOnboarding: true,
                hasEarnedBadge: true,
                hasOpenWindow: false,
                isPresentationAvailable: true,
                celebratedDateKey: nil,
                currentDateKey: "2026-06-09"
            )
        )
    }

    func testDefersPresentationWhileSessionIsUnavailable() {
        XCTAssertFalse(
            SuperBadgeCelebrationPolicy.shouldPresent(
                hasCompletedOnboarding: true,
                hasEarnedBadge: true,
                hasOpenWindow: false,
                isPresentationAvailable: false,
                celebratedDateKey: nil,
                currentDateKey: "2026-06-09"
            )
        )
    }

    func testDoesNotPresentTheSameBadgeTwice() {
        XCTAssertFalse(
            SuperBadgeCelebrationPolicy.shouldPresent(
                hasCompletedOnboarding: true,
                hasEarnedBadge: true,
                hasOpenWindow: false,
                isPresentationAvailable: true,
                celebratedDateKey: "2026-06-09",
                currentDateKey: "2026-06-09"
            )
        )
    }

    func testClosesAnOpenCelebrationAfterTheDateChanges() {
        XCTAssertTrue(
            SuperBadgeCelebrationPolicy.shouldCloseOpenCelebration(
                celebrationDateKey: "2026-06-08",
                currentDateKey: "2026-06-09"
            )
        )
        XCTAssertFalse(
            SuperBadgeCelebrationPolicy.shouldCloseOpenCelebration(
                celebrationDateKey: "2026-06-09",
                currentDateKey: "2026-06-09"
            )
        )
    }
}
