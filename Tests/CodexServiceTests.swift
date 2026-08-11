import XCTest
@testable import QuotaPulse

final class CodexServiceTests: XCTestCase {
    func testParsesCodexRateLimitResponse() throws {
        let payload = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":94,"windowDurationMins":300,"resetsAt":1782128534},"secondary":{"usedPercent":43,"windowDurationMins":10080,"resetsAt":1782354954},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus"}}}
        """

        let result = try CodexService.parseResponses(payload)

        XCTAssertEqual(result.used, 94)
        XCTAssertEqual(result.remaining, 6)
        XCTAssertEqual(result.total, 100)
        XCTAssertEqual(result.monthlyUsed, 43)
        XCTAssertEqual(result.monthlyRemaining, 57)
        XCTAssertEqual(result.monthlyTotal, 100)
        XCTAssertEqual(result.subscriptionPlan, "plus")
        XCTAssertEqual(result.primaryCycleIsPercentage, true)
        XCTAssertEqual(result.secondaryCycleIsPercentage, true)
        XCTAssertEqual(result.refreshTime?.timeIntervalSince1970, 1_782_128_534)
        XCTAssertEqual(result.monthlyRefreshTime?.timeIntervalSince1970, 1_782_354_954)
    }

    func testParsesCodexSessionTokenCountEvent() throws {
        let payload = """
        {"timestamp":"2026-06-22T02:45:52.219Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"limit_id":"codex","primary":{"used_percent":27.0,"window_minutes":300,"resets_at":1782109649},"secondary":{"used_percent":24.0,"window_minutes":10080,"resets_at":1782354954},"plan_type":"plus"}}
        """

        let result = try CodexService.parseResponses(payload)

        XCTAssertEqual(result.used, 27)
        XCTAssertEqual(result.remaining, 73)
        XCTAssertEqual(result.monthlyUsed, 24)
        XCTAssertEqual(result.monthlyRemaining, 76)
        XCTAssertEqual(result.subscriptionPlan, "plus")
    }

    func testParsesLiveWhamUsageResponse() throws {
        let payload = """
        {"plan_type":"plus","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":52,"limit_window_seconds":18000,"reset_after_seconds":15437,"reset_at":1782303730},"secondary_window":{"used_percent":85,"limit_window_seconds":604800,"reset_after_seconds":66661,"reset_at":1782354954}}}
        """

        let result = try CodexService.parseWhamUsageResponse(Data(payload.utf8))

        XCTAssertEqual(result.used, 52)
        XCTAssertEqual(result.remaining, 48)
        XCTAssertEqual(result.total, 100)
        XCTAssertEqual(result.monthlyUsed, 85)
        XCTAssertEqual(result.monthlyRemaining, 15)
        XCTAssertEqual(result.monthlyTotal, 100)
        XCTAssertEqual(result.subscriptionPlan, "plus")
        XCTAssertEqual(result.primaryCycleIsPercentage, true)
        XCTAssertEqual(result.secondaryCycleIsPercentage, true)
        XCTAssertEqual(result.refreshTime?.timeIntervalSince1970, 1_782_303_730)
        XCTAssertEqual(result.monthlyRefreshTime?.timeIntervalSince1970, 1_782_354_954)
    }

    func testParsesWeeklyOnlyCodexWindowWithoutFakingFiveHourQuota() throws {
        let payload = """
        {"plan_type":"plus","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":43,"limit_window_seconds":604800,"reset_at":1782354954}}}
        """

        let result = try CodexService.parseWhamUsageResponse(Data(payload.utf8))

        XCTAssertNil(result.used)
        XCTAssertNil(result.remaining)
        XCTAssertNil(result.total)
        XCTAssertNil(result.refreshTime)
        XCTAssertNil(result.primaryCycleIsPercentage)
        XCTAssertEqual(result.monthlyUsed, 43)
        XCTAssertEqual(result.monthlyRemaining, 57)
        XCTAssertEqual(result.monthlyTotal, 100)
        XCTAssertEqual(result.secondaryCycleIsPercentage, true)
        XCTAssertEqual(result.monthlyRefreshTime?.timeIntervalSince1970, 1_782_354_954)
    }

    func testThrowsHelpfulCodexErrorMessage() {
        let payload = """
        {"error":{"code":-32603,"message":"failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"},"id":2}
        """

        XCTAssertThrowsError(try CodexService.parseResponses(payload)) { error in
            XCTAssertTrue(error.localizedDescription.contains("failed to fetch codex rate limits"))
        }
    }
}
