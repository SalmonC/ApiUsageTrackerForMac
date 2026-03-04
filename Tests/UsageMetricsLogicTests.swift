import XCTest
@testable import QuotaPulse

final class UsageMetricsLogicTests: XCTestCase {
    func testTrendPointsRespectWindowAndDownsample() {
        let accountId = UUID()
        let now = Date()
        var snapshots: [UsageSnapshot] = []

        for hour in stride(from: 95, through: 0, by: -1) {
            snapshots.append(
                UsageSnapshot(
                    accountId: accountId,
                    provider: .miniMax,
                    capturedAt: now.addingTimeInterval(-TimeInterval(hour * 3600)),
                    tokenUsed: Double(hour),
                    tokenTotal: 100,
                    monthlyUsed: nil,
                    monthlyTotal: nil,
                    usagePercentage: Double(hour % 100),
                    monthlyUsagePercentage: nil
                )
            )
        }

        let dayPoints = UsageMetricsLogic.trendPoints(
            accountSnapshots: snapshots,
            window: .day,
            now: now
        )
        XCTAssertFalse(dayPoints.isEmpty)
        XCTAssertLessThanOrEqual(dayPoints.count, 36)
        XCTAssertTrue(dayPoints.allSatisfy { $0.timestamp >= now.addingTimeInterval(-86_400) })

        let monthPoints = UsageMetricsLogic.trendPoints(
            accountSnapshots: snapshots,
            window: .month,
            now: now
        )
        XCTAssertLessThanOrEqual(monthPoints.count, 36)
        XCTAssertGreaterThanOrEqual(monthPoints.count, dayPoints.count)
    }

    func testDataConfidenceClassification() {
        let base = UsageData(
            accountId: UUID(),
            accountName: "A",
            provider: .miniMax,
            tokenRemaining: 50,
            tokenUsed: 50,
            tokenTotal: 100,
            refreshTime: nil,
            lastUpdated: Date(),
            errorMessage: nil,
            monthlyRemaining: nil,
            monthlyTotal: nil,
            monthlyUsed: nil,
            monthlyRefreshTime: nil,
            nextRefreshTime: nil,
            subscriptionPlan: nil
        )

        let high = UsageMetricsLogic.dataConfidence(for: base, language: .english)
        XCTAssertEqual(high.level, .high)

        var estimated = base
        estimated.primaryRefreshIsEstimated = true
        let medium = UsageMetricsLogic.dataConfidence(for: estimated, language: .english)
        XCTAssertEqual(medium.level, .medium)

        var errored = base
        errored.errorMessage = "failed"
        let low = UsageMetricsLogic.dataConfidence(for: errored, language: .english)
        XCTAssertEqual(low.level, .low)

        let chat = UsageData(
            accountId: UUID(),
            accountName: "Chat",
            provider: .chatGPT,
            tokenRemaining: nil,
            tokenUsed: nil,
            tokenTotal: nil,
            refreshTime: nil,
            lastUpdated: Date(),
            errorMessage: nil,
            monthlyRemaining: nil,
            monthlyTotal: nil,
            monthlyUsed: nil,
            monthlyRefreshTime: nil,
            nextRefreshTime: nil,
            subscriptionPlan: "Plus"
        )
        let chatConfidence = UsageMetricsLogic.dataConfidence(for: chat, language: .english)
        XCTAssertEqual(chatConfidence.level, .medium)
    }

    func testRetryableErrorClassification() {
        XCTAssertTrue(UsageMetricsLogic.isRetryableFetchError(APIError.httpError(500)))
        XCTAssertTrue(UsageMetricsLogic.isRetryableFetchError(APIError.httpError(429)))
        XCTAssertTrue(UsageMetricsLogic.isRetryableFetchError(APIError.networkError(URLError(.timedOut))))
        XCTAssertFalse(UsageMetricsLogic.isRetryableFetchError(APIError.httpError(401)))
        XCTAssertFalse(UsageMetricsLogic.isRetryableFetchError(APIError.decodingError(NSError(domain: "x", code: 1))))
    }

    func testBackoffGrowsWithAttemptAndHonorsCap() {
        let a1 = UsageMetricsLogic.backoffDelayNanoseconds(attempt: 1, jitterRange: 0...0)
        let a2 = UsageMetricsLogic.backoffDelayNanoseconds(attempt: 2, jitterRange: 0...0)
        let a5 = UsageMetricsLogic.backoffDelayNanoseconds(attempt: 5, jitterRange: 0...0)

        XCTAssertGreaterThan(a2, a1)
        XCTAssertLessThanOrEqual(a5, UInt64(2.8 * 1_000_000_000))
    }
}
