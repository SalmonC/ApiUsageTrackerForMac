import XCTest
@testable import QuotaPulse

@MainActor
final class AppViewModelTrendCacheTests: XCTestCase {
    func testTrendCacheHitAndRevisionInvalidation() {
        let viewModel = AppViewModel(loadStoredState: false)
        let accountID = UUID()
        let now = Date()

        let initialSnapshots = [
            makeSnapshot(accountID: accountID, hoursAgo: 3, usagePercent: 10, now: now),
            makeSnapshot(accountID: accountID, hoursAgo: 2, usagePercent: 20, now: now),
            makeSnapshot(accountID: accountID, hoursAgo: 1, usagePercent: 35, now: now)
        ]

        viewModel.replaceSnapshotsForTesting(initialSnapshots)
        let firstRevision = viewModel.snapshotRevisionForTesting

        XCTAssertEqual(viewModel.trendCacheEntryCountForTesting, 0)

        let firstResult = viewModel.trendPoints(for: accountID, window: .day)
        XCTAssertEqual(viewModel.trendCacheEntryCountForTesting, 1)
        XCTAssertEqual(firstResult.count, 3)

        let secondResult = viewModel.trendPoints(for: accountID, window: .day)
        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(viewModel.trendCacheEntryCountForTesting, 1)

        let updatedSnapshots = initialSnapshots + [
            makeSnapshot(accountID: accountID, hoursAgo: 0, usagePercent: 42, now: now)
        ]
        viewModel.replaceSnapshotsForTesting(updatedSnapshots)

        let secondRevision = viewModel.snapshotRevisionForTesting
        XCTAssertGreaterThan(secondRevision, firstRevision)
        XCTAssertEqual(viewModel.trendCacheEntryCountForTesting, 0)

        let refreshedResult = viewModel.trendPoints(for: accountID, window: .day)
        XCTAssertEqual(viewModel.trendCacheEntryCountForTesting, 1)
        XCTAssertEqual(refreshedResult.count, 4)
    }

    private func makeSnapshot(accountID: UUID, hoursAgo: Int, usagePercent: Double, now: Date) -> UsageSnapshot {
        UsageSnapshot(
            accountId: accountID,
            provider: .miniMax,
            capturedAt: now.addingTimeInterval(-TimeInterval(hoursAgo * 3600)),
            tokenUsed: usagePercent,
            tokenTotal: 100,
            monthlyUsed: nil,
            monthlyTotal: nil,
            usagePercentage: usagePercent,
            monthlyUsagePercentage: nil
        )
    }
}
