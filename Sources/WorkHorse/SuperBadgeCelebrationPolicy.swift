import Foundation

struct SuperBadgeCelebrationPolicy {
    static func shouldPresent(
        hasCompletedOnboarding: Bool,
        hasEarnedBadge: Bool,
        hasOpenWindow: Bool,
        isPresentationAvailable: Bool,
        celebratedDateKey: String?,
        currentDateKey: String
    ) -> Bool {
        hasCompletedOnboarding
            && hasEarnedBadge
            && !hasOpenWindow
            && isPresentationAvailable
            && celebratedDateKey != currentDateKey
    }

    static func shouldCloseOpenCelebration(
        celebrationDateKey: String?,
        currentDateKey: String
    ) -> Bool {
        guard let celebrationDateKey else { return false }
        return celebrationDateKey != currentDateKey
    }
}
