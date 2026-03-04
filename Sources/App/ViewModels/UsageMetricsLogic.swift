import Foundation

enum TrendWindow: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .day:
            return 1
        case .week:
            return 7
        case .month:
            return 30
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .day:
            return language == .english ? "24h" : "24小时"
        case .week:
            return language == .english ? "7d" : "7天"
        case .month:
            return language == .english ? "30d" : "30天"
        }
    }
}

struct UsageTrendPoint: Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let usagePercent: Double
}

enum DataConfidenceLevel: String {
    case high
    case medium
    case low
    case unknown

    func label(language: AppLanguage) -> String {
        switch self {
        case .high:
            return language == .english ? "High" : "高"
        case .medium:
            return language == .english ? "Medium" : "中"
        case .low:
            return language == .english ? "Low" : "低"
        case .unknown:
            return language == .english ? "Unknown" : "未知"
        }
    }
}

struct DataConfidence: Equatable {
    let level: DataConfidenceLevel
    let reason: String
}

enum UsageMetricsLogic {
    static func trendPoints(
        accountSnapshots: [UsageSnapshot],
        window: TrendWindow,
        now: Date = Date(),
        targetCount: Int = 36
    ) -> [UsageTrendPoint] {
        let cutoff = now.addingTimeInterval(-TimeInterval(window.days * 86_400))
        let source = accountSnapshots.filter { $0.capturedAt >= cutoff }

        guard !source.isEmpty else { return [] }

        var points: [UsageTrendPoint] = []
        points.reserveCapacity(min(source.count, 160))
        for snapshot in source {
            guard let percent = snapshot.usagePercentage ?? snapshot.monthlyUsagePercentage else {
                continue
            }
            points.append(
                UsageTrendPoint(
                    timestamp: snapshot.capturedAt,
                    usagePercent: min(max(percent, 0), 100)
                )
            )
        }
        return downsample(points: points, targetCount: targetCount)
    }

    static func downsample(points: [UsageTrendPoint], targetCount: Int) -> [UsageTrendPoint] {
        guard points.count > targetCount, targetCount > 2 else { return points }
        let step = Double(points.count - 1) / Double(targetCount - 1)
        var reduced: [UsageTrendPoint] = []
        reduced.reserveCapacity(targetCount)
        for index in 0..<targetCount {
            let sourceIndex = Int((Double(index) * step).rounded())
            reduced.append(points[min(max(sourceIndex, 0), points.count - 1)])
        }
        return reduced
    }

    static func dataConfidence(for data: UsageData, language: AppLanguage) -> DataConfidence {
        if data.errorMessage != nil {
            return DataConfidence(
                level: .low,
                reason: language == .english ? "Last refresh failed" : "最近一次刷新失败"
            )
        }

        let hasNumericUsage = (data.tokenTotal ?? 0) > 0 || (data.monthlyTotal ?? 0) > 0
        let hasEstimatedField = data.primaryRefreshIsEstimated || data.secondaryRefreshIsEstimated
        if hasNumericUsage && !hasEstimatedField {
            return DataConfidence(
                level: .high,
                reason: language == .english ? "Direct provider data" : "供应商直接返回数据"
            )
        }
        if hasNumericUsage && hasEstimatedField {
            return DataConfidence(
                level: .medium,
                reason: language == .english ? "Partially estimated reset cycle" : "部分刷新周期为估算"
            )
        }
        if data.provider == .chatGPT {
            return DataConfidence(
                level: .medium,
                reason: language == .english ? "Subscription-only status" : "仅订阅状态信息"
            )
        }
        return DataConfidence(
            level: .unknown,
            reason: language == .english ? "Limited provider fields" : "供应商可用字段有限"
        )
    }

    static func isRetryableFetchError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .networkError:
                return true
            case .httpError(let code), .httpErrorWithMessage(let code, _):
                return code >= 500 || code == 429
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("timeout") || lowered.contains("timed out") || lowered.contains("429")
    }

    static func backoffDelayNanoseconds(attempt: Int, jitterRange: ClosedRange<Double> = 0.05...0.18) -> UInt64 {
        let baseSeconds = pow(2.0, Double(max(0, attempt - 1))) * 0.45
        let jitterSeconds = Double.random(in: jitterRange)
        let totalSeconds = min(baseSeconds + jitterSeconds, 2.8)
        return UInt64(totalSeconds * 1_000_000_000)
    }
}
