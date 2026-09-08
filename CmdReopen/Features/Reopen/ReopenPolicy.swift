import Foundation

/// Pure decisions. Callers supply time and retain ownership of side effects.
enum ReopenPolicy {
    static func shouldSuppressRecentLaunch(launchDate: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let launchDate else { return false }
        let elapsed = now.timeIntervalSince(launchDate)
        return elapsed >= 0 && elapsed <= interval
    }

    static func shouldDebounceReopen(lastReopenDate: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastReopenDate else { return false }
        return now.timeIntervalSince(lastReopenDate) < interval
    }

    static func shouldIgnoreSelfTriggered(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now <= until
    }

    static func shouldShowExpiredNudge(
        lastNudgeDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastNudgeDate else { return true }
        return !calendar.isDate(lastNudgeDate, inSameDayAs: now)
    }

    static func shouldSuppressRapidReturn(
        previousFrontmostBundleID: String?,
        targetBundleID: String,
        targetLastActivationDate: Date?,
        previousBundleLastActivationDate: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let previousFrontmostBundleID,
              previousFrontmostBundleID != targetBundleID,
              let targetLastActivationDate,
              let previousBundleLastActivationDate else {
            return false
        }
        let targetGap = now.timeIntervalSince(targetLastActivationDate)
        let previousGap = now.timeIntervalSince(previousBundleLastActivationDate)
        return targetGap >= 0 && targetGap < interval && previousGap >= 0 && previousGap < interval
    }
}

struct ForegroundWindowObservationState: Equatable {
    private(set) var hasObservedVisibleWindow = false
    private(set) var consecutiveMissingSamples = 0

    mutating func observe(
        hasVisibleWindow: Bool,
        requiredMissingSamples: Int
    ) -> Bool {
        if hasVisibleWindow {
            hasObservedVisibleWindow = true
            consecutiveMissingSamples = 0
            return false
        }

        guard hasObservedVisibleWindow else {
            return false
        }

        consecutiveMissingSamples += 1
        guard consecutiveMissingSamples >= max(1, requiredMissingSamples) else {
            return false
        }

        reset()
        return true
    }

    mutating func reset() {
        hasObservedVisibleWindow = false
        consecutiveMissingSamples = 0
    }
}
