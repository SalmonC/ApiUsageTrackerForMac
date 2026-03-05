import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var isLoading = false
    @Published var settings: AppSettings = .default
    @Published private(set) var isDashboardVisible = false
    @Published private(set) var nextAutoRefreshDate: Date?
    @Published var refreshingAccountIDs: Set<UUID> = []
    @Published var dashboardSortMode: DashboardSortMode = Storage.shared.loadDashboardSortMode()
    @Published var dashboardManualOrder: [UUID] = Storage.shared.loadDashboardManualOrder()
    @Published var trendWindow: TrendWindow = .day

    private struct TrendCacheKey: Hashable {
        let accountId: UUID
        let window: TrendWindow
        let revision: UInt64
    }

    private var cycleLearningState: [String: CycleLearningState] = [:]
    private var usageSnapshots: [UsageSnapshot] = []
    private var snapshotsByAccount: [UUID: [UsageSnapshot]] = [:]
    private var trendCache: [TrendCacheKey: [UsageTrendPoint]] = [:]
    private var snapshotRevision: UInt64 = 0
    private let snapshotRetentionDays: TimeInterval = 45 * 86_400
    private let snapshotMaxPerAccount = 5_000
    private let snapshotDuplicateWindow: TimeInterval = 45
    var onSettingsSaved: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    
    init(loadStoredState: Bool = true) {
        if loadStoredState {
            cycleLearningState = Storage.shared.loadCycleLearningState()
            usageSnapshots = Storage.shared.loadUsageSnapshots()
            loadSettings()
            loadCachedData()
        }
        rebuildSnapshotsIndex()
        pruneAndPersistSnapshots(now: Date())
        Storage.shared.saveRefreshInterval(settings.refreshInterval)
    }
    
    func loadSettings() {
        settings = Storage.shared.loadSettings()
    }
    
    private func loadCachedData() {
        let cached = Storage.shared.loadUsageData()
        if !cached.isEmpty {
            usageData = cached
            ensureManualOrderContainsCurrentAccounts()
        }
    }
    
    func setNextAutoRefreshDate(_ date: Date?) {
        nextAutoRefreshDate = date
    }

    func setDashboardVisible(_ visible: Bool) {
        guard isDashboardVisible != visible else { return }
        isDashboardVisible = visible
    }
    
    func refreshAll(reloadSettings: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        if reloadSettings {
            loadSettings()
        }
        let language = settings.language
        let activeAccounts = settings.accounts.filter { $0.isEnabled && !$0.apiKey.isEmpty }
        var orderedResults = Array<UsageData?>(repeating: nil, count: activeAccounts.count)
        
        await withTaskGroup(of: (Int, UsageData?).self) { group in
            for (index, account) in activeAccounts.enumerated() {
                group.addTask {
                    return (index, await Self.fetchUsageData(for: account, language: language))
                }
            }
            
            for await (index, data) in group {
                orderedResults[index] = data
            }
        }
        
        let newData = orderedResults.compactMap { $0 }.map(resolveRefreshTime)
        
        usageData = newData
        ensureManualOrderContainsCurrentAccounts()
        Storage.shared.saveUsageData(newData)
        appendSnapshots(from: newData, capturedAt: Date())
        Storage.shared.saveCycleLearningState(cycleLearningState)
        
        WidgetCenter.shared.reloadAllTimelines()
        
        isLoading = false
    }

    func refreshAccount(_ accountId: UUID) async {
        guard !isLoading else { return }
        guard refreshingAccountIDs.insert(accountId).inserted else { return }

        loadSettings()
        guard let account = settings.accounts.first(where: { $0.id == accountId && $0.isEnabled && !$0.apiKey.isEmpty }) else {
            refreshingAccountIDs.remove(accountId)
            return
        }

        defer { refreshingAccountIDs.remove(accountId) }

        guard let fetched = await Self.fetchUsageData(for: account, language: settings.language) else {
            return
        }
        let updatedData = resolveRefreshTime(fetched)

        if let existingIndex = usageData.firstIndex(where: { $0.accountId == accountId }) {
            usageData[existingIndex] = updatedData
        } else {
            usageData.append(updatedData)
        }
        ensureManualOrderContainsCurrentAccounts()

        Storage.shared.saveUsageData(usageData)
        appendSnapshots(from: [updatedData], capturedAt: Date())
        Storage.shared.saveCycleLearningState(cycleLearningState)
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func saveSettings(_ newSettings: AppSettings) {
        settings = newSettings
        let accountLookup = Dictionary(uniqueKeysWithValues: newSettings.accounts.map { ($0.id, $0) })
        usageData = usageData
            .filter { accountLookup[$0.accountId] != nil }
            .map { item in
                guard let account = accountLookup[item.accountId] else { return item }
                var next = item
                next.accountName = account.name.isEmpty ? account.provider.displayName : account.name
                next.provider = account.provider
                return next
            }
        ensureManualOrderContainsCurrentAccounts()
        Storage.shared.saveUsageData(usageData)
        removeSnapshotsForDeletedAccounts(validIDs: Set(newSettings.accounts.map(\.id)))
        Storage.shared.saveSettings(newSettings)
        Storage.shared.saveRefreshInterval(newSettings.refreshInterval)
        onSettingsSaved?()
    }
    
    func openSettings() {
        onOpenSettings?()
    }
    
    var hotkeyDisplayString: String {
        settings.hotkey.displayString
    }

    var latestUpdateTime: Date? {
        usageData.map(\.lastUpdated).max()
    }

    var failedAccountCount: Int {
        usageData.filter { $0.errorMessage != nil }.count
    }

    var successfulAccountCount: Int {
        usageData.filter { $0.errorMessage == nil }.count
    }

    func snapshots(for accountId: UUID, withinDays days: Int? = nil) -> [UsageSnapshot] {
        let accountSnapshots = snapshotsByAccount[accountId] ?? []
        guard days != nil else { return accountSnapshots }
        let cutoff = Date().addingTimeInterval(-TimeInterval(max(days ?? 0, 1) * 86_400))
        return accountSnapshots.filter { $0.capturedAt >= cutoff }
    }

    func trendPoints(for accountId: UUID, window: TrendWindow? = nil) -> [UsageTrendPoint] {
        let selectedWindow = window ?? trendWindow
        let cacheKey = TrendCacheKey(accountId: accountId, window: selectedWindow, revision: snapshotRevision)
        if let cached = trendCache[cacheKey] {
            return cached
        }

        let accountSnapshots = snapshotsByAccount[accountId] ?? []
        let points = UsageMetricsLogic.trendPoints(
            accountSnapshots: accountSnapshots,
            window: selectedWindow
        )
        trendCache[cacheKey] = points
        return points
    }

    func dataConfidence(for data: UsageData) -> DataConfidence {
        UsageMetricsLogic.dataConfidence(for: data, language: settings.language)
    }

    var displayUsageData: [UsageData] {
        UsageDataSorting.sort(usageData, mode: dashboardSortMode, manualOrder: dashboardManualOrder)
    }

    func setDashboardSortMode(_ mode: DashboardSortMode) {
        let previousMode = dashboardSortMode
        let currentVisibleOrder = displayUsageData.map(\.accountId)
        dashboardSortMode = mode
        if mode == .manual {
            if previousMode != .manual && !currentVisibleOrder.isEmpty {
                let visibleSet = Set(usageData.map(\.accountId))
                let hiddenIDs = dashboardManualOrder.filter { !visibleSet.contains($0) }
                dashboardManualOrder = currentVisibleOrder + hiddenIDs
                Storage.shared.saveDashboardManualOrder(dashboardManualOrder)
            }
            ensureManualOrderContainsCurrentAccounts()
        }
        Storage.shared.saveDashboardSortMode(mode)
    }

    @discardableResult
    func moveManualOrder(draggedID: UUID, before targetID: UUID, persist: Bool = false) -> Bool {
        moveManualOrder(draggedID: draggedID, relativeTo: targetID, insertAfterTarget: false, persist: persist)
    }

    @discardableResult
    func moveManualOrder(draggedID: UUID, after targetID: UUID, persist: Bool = false) -> Bool {
        moveManualOrder(draggedID: draggedID, relativeTo: targetID, insertAfterTarget: true, persist: persist)
    }

    @discardableResult
    private func moveManualOrder(
        draggedID: UUID,
        relativeTo targetID: UUID,
        insertAfterTarget: Bool,
        persist: Bool
    ) -> Bool {
        guard dashboardSortMode == .manual else { return false }
        guard draggedID != targetID else { return false }

        let visibleOrderedIDs = displayUsageData.map(\.accountId)
        guard let fromIndex = visibleOrderedIDs.firstIndex(of: draggedID) else {
            return false
        }

        var reorderedVisible = visibleOrderedIDs
        reorderedVisible.remove(at: fromIndex)

        guard let targetIndex = reorderedVisible.firstIndex(of: targetID) else {
            return false
        }

        let insertionIndex = insertAfterTarget ? (targetIndex + 1) : targetIndex
        reorderedVisible.insert(draggedID, at: max(0, min(insertionIndex, reorderedVisible.count)))

        guard reorderedVisible != visibleOrderedIDs else {
            return false
        }

        let visibleSet = Set(usageData.map(\.accountId))
        let hiddenIDs = dashboardManualOrder.filter { !visibleSet.contains($0) }
        let newOrder = reorderedVisible + hiddenIDs
        guard newOrder != dashboardManualOrder else {
            return false
        }

        dashboardManualOrder = newOrder
        if persist {
            Storage.shared.saveDashboardManualOrder(dashboardManualOrder)
        }
        return true
    }

    func commitManualOrderFromCurrentDisplayIfNeeded() {
        guard dashboardSortMode == .manual else { return }
        ensureManualOrderContainsCurrentAccounts()
        Storage.shared.saveDashboardManualOrder(dashboardManualOrder)
    }

    private func resolveRefreshTime(_ data: UsageData) -> UsageData {
        var resolved = data
        let now = Date()

        let primaryKey = cycleLearningKey(accountID: data.accountId, kind: "primary")
        let secondaryKey = cycleLearningKey(accountID: data.accountId, kind: "secondary")

        var primaryState = cycleLearningState[primaryKey] ?? CycleLearningState()
        var secondaryState = cycleLearningState[secondaryKey] ?? CycleLearningState()

        if let primaryRefresh = resolved.refreshTime {
            primaryState = updateLearning(primaryState, observedReset: primaryRefresh, now: now)
            resolved.primaryRefreshIsEstimated = false
        } else if let predictedPrimary = predictReset(from: primaryState, now: now) {
            resolved.refreshTime = predictedPrimary
            resolved.primaryRefreshIsEstimated = true
            if resolved.nextRefreshTime == nil {
                resolved.nextRefreshTime = predictedPrimary
            }
        } else {
            resolved.primaryRefreshIsEstimated = false
        }

        if let secondaryRefresh = resolved.monthlyRefreshTime {
            secondaryState = updateLearning(secondaryState, observedReset: secondaryRefresh, now: now)
            resolved.secondaryRefreshIsEstimated = false
        } else if let predictedSecondary = predictReset(from: secondaryState, now: now) {
            resolved.monthlyRefreshTime = predictedSecondary
            resolved.secondaryRefreshIsEstimated = true
        } else {
            resolved.secondaryRefreshIsEstimated = false
        }

        cycleLearningState[primaryKey] = primaryState
        cycleLearningState[secondaryKey] = secondaryState
        return resolved
    }

    private func cycleLearningKey(accountID: UUID, kind: String) -> String {
        "\(accountID.uuidString)-\(kind)"
    }

    private func updateLearning(_ state: CycleLearningState, observedReset: Date, now: Date) -> CycleLearningState {
        var next = state
        let uniquenessThreshold: TimeInterval = 60
        if !next.observedResets.contains(where: { abs($0.timeIntervalSince(observedReset)) < uniquenessThreshold }) {
            next.observedResets.append(observedReset)
            next.observedResets.sort()
            if next.observedResets.count > 8 {
                next.observedResets.removeFirst(next.observedResets.count - 8)
            }
        }
        next.lastObservedAt = now

        let intervals = zip(next.observedResets, next.observedResets.dropFirst())
            .map { $1.timeIntervalSince($0) }
            .filter { $0 > 300 }
            .sorted()

        guard !intervals.isEmpty else { return next }

        let medianInterval = intervals[intervals.count / 2]
        let plausibleRange = (1800.0...3_888_000.0) // 30m...45d
        guard plausibleRange.contains(medianInterval) else { return next }

        if let existing = next.learnedInterval, existing > 0 {
            let drift = abs(medianInterval - existing) / existing
            if drift <= 0.20 {
                next.learnedInterval = existing * 0.6 + medianInterval * 0.4
                next.confidence = min(1.0, max(next.confidence, 0.55) + 0.10)
            } else {
                next.confidence = max(0.25, next.confidence - 0.20)
                if next.confidence < 0.40 {
                    next.learnedInterval = medianInterval
                    next.confidence = 0.55
                }
            }
        } else {
            next.learnedInterval = medianInterval
            next.confidence = 0.60
        }

        return next
    }

    private func predictReset(from state: CycleLearningState, now: Date) -> Date? {
        guard let interval = state.learnedInterval else { return nil }
        guard interval > 300 else { return nil }
        guard state.confidence >= 0.55 else { return nil }
        guard let lastObservedAt = state.lastObservedAt else { return nil }
        guard now.timeIntervalSince(lastObservedAt) <= 21 * 86_400 else { return nil }
        guard let anchor = state.observedResets.last else { return nil }

        var prediction = anchor
        var guardCounter = 0
        while prediction <= now, guardCounter < 128 {
            prediction = prediction.addingTimeInterval(interval)
            guardCounter += 1
        }
        guard prediction > now else { return nil }
        return prediction
    }

    nonisolated private static func fetchUsageData(for account: APIAccount, language: AppLanguage) async -> UsageData? {
        if Task.isCancelled {
            return nil
        }
        if let preflightError = await preflightErrorMessage(for: account, language: language) {
            Logger.log("Preflight failed for \(account.provider.rawValue): \(preflightError)")
            return failureUsageData(for: account, errorMessage: preflightError)
        }

        let service = getService(for: account.provider)

        do {
            let result = try await fetchUsageWithRetry(
                service: service,
                apiKey: account.apiKey,
                provider: account.provider
            )
            return UsageData(
                accountId: account.id,
                accountName: account.name.isEmpty ? account.provider.displayName : account.name,
                provider: account.provider,
                tokenRemaining: result.remaining,
                tokenUsed: result.used,
                tokenTotal: result.total,
                refreshTime: result.refreshTime,
                lastUpdated: Date(),
                errorMessage: nil,
                monthlyRemaining: result.monthlyRemaining,
                monthlyTotal: result.monthlyTotal,
                monthlyUsed: result.monthlyUsed,
                monthlyRefreshTime: result.monthlyRefreshTime,
                nextRefreshTime: result.nextRefreshTime,
                subscriptionPlan: result.subscriptionPlan,
                primaryCycleIsPercentage: result.primaryCycleIsPercentage,
                secondaryCycleIsPercentage: result.secondaryCycleIsPercentage
            )
        } catch is CancellationError {
            return nil
        } catch {
            let message = classifyFetchError(error, language: language)
            Logger.log("Fetch failed for \(account.provider.rawValue): \(message), raw=\(error.localizedDescription)")
            return failureUsageData(for: account, errorMessage: message)
        }
    }

    nonisolated private static func fetchUsageWithRetry(
        service: UsageService,
        apiKey: String,
        provider: APIProvider
    ) async throws -> UsageResult {
        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await service.fetchUsage(apiKey: apiKey)
            } catch {
                if error is CancellationError {
                    throw error
                }
                lastError = error
                guard attempt < maxAttempts, UsageMetricsLogic.isRetryableFetchError(error) else {
                    throw error
                }
                let backoffNs = UsageMetricsLogic.backoffDelayNanoseconds(attempt: attempt)
                Logger.log("Retrying \(provider.rawValue) fetch (attempt \(attempt + 1)/\(maxAttempts)) after error: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: backoffNs)
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    nonisolated private static func failureUsageData(for account: APIAccount, errorMessage: String) -> UsageData {
        UsageData(
            accountId: account.id,
            accountName: account.name.isEmpty ? account.provider.displayName : account.name,
            provider: account.provider,
            tokenRemaining: nil,
            tokenUsed: nil,
            tokenTotal: nil,
            refreshTime: nil,
            lastUpdated: Date(),
            errorMessage: errorMessage,
            monthlyRemaining: nil,
            monthlyTotal: nil,
            monthlyUsed: nil,
            monthlyRefreshTime: nil,
            nextRefreshTime: nil,
            subscriptionPlan: nil
        )
    }

    nonisolated private static func preflightErrorMessage(for account: APIAccount, language: AppLanguage) async -> String? {
        let credential = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if credential.isEmpty {
            return localized(
                zh: "预检失败：未配置凭证",
                en: "Preflight failed: missing credential",
                language: language
            )
        }

        if let formatError = credentialFormatError(for: account.provider, credential: credential, language: language) {
            return localized(
                zh: "预检失败：\(formatError)",
                en: "Preflight failed: \(formatError)",
                language: language
            )
        }

        if let reachabilityError = await providerReachabilityError(for: account.provider, language: language) {
            return localized(
                zh: "预检失败：\(reachabilityError)",
                en: "Preflight failed: \(reachabilityError)",
                language: language
            )
        }

        return nil
    }

    nonisolated private static func credentialFormatError(
        for provider: APIProvider,
        credential: String,
        language: AppLanguage
    ) -> String? {
        switch provider {
        case .openAI:
            guard credential.hasPrefix("sk-"), credential.count >= 20 else {
                return localized(
                    zh: "OpenAI API Key 格式异常（应以 sk- 开头）",
                    en: "invalid OpenAI API key format (expected sk- prefix)",
                    language: language
                )
            }
        case .chatGPT:
            let looksLikeJWT = credential.split(separator: ".").count == 3
            let looksLikeCookie = credential.contains("=") || credential.contains("session-token")
            if credential.hasPrefix("sk-") {
                return localized(
                    zh: "ChatGPT 账号应填写 access token 或 session token，不是 API Key",
                    en: "ChatGPT account requires access/session token, not API key",
                    language: language
                )
            }
            guard looksLikeJWT || looksLikeCookie || credential.count >= 24 else {
                return localized(
                    zh: "ChatGPT 凭证格式异常，请检查 access token/session token",
                    en: "invalid ChatGPT credential format, check access/session token",
                    language: language
                )
            }
        case .tavily:
            guard credential.count >= 16 else {
                return localized(
                    zh: "Tavily Key 长度异常，请检查是否粘贴完整",
                    en: "Tavily key length looks invalid",
                    language: language
                )
            }
        case .miniMax, .glm, .kimi:
            guard credential.count >= 12 else {
                return localized(
                    zh: "\(provider.displayName) 凭证格式异常，请检查是否完整",
                    en: "\(provider.displayName) credential format looks invalid",
                    language: language
                )
            }
        }
        return nil
    }

    nonisolated private static func providerReachabilityError(for provider: APIProvider, language: AppLanguage) async -> String? {
        guard let url = providerHealthProbeURL(for: provider) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode >= 500 {
                return localized(
                    zh: "供应商接口暂不可用（HTTP \(httpResponse.statusCode)）",
                    en: "provider endpoint is temporarily unavailable (HTTP \(httpResponse.statusCode))",
                    language: language
                )
            }
            return nil
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                return localized(
                    zh: "网络不可用，请检查网络连接",
                    en: "network unavailable, check internet connection",
                    language: language
                )
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return localized(
                    zh: "无法连接供应商接口，请检查网络或代理",
                    en: "cannot reach provider endpoint, check network or proxy",
                    language: language
                )
            case .timedOut:
                return localized(
                    zh: "供应商接口连接超时",
                    en: "provider endpoint timed out",
                    language: language
                )
            default:
                return localized(
                    zh: "网络预检失败（\(error.localizedDescription)）",
                    en: "network preflight failed (\(error.localizedDescription))",
                    language: language
                )
            }
        } catch {
            return localized(
                zh: "网络预检失败，请稍后重试",
                en: "network preflight failed, please retry later",
                language: language
            )
        }
    }

    nonisolated private static func providerHealthProbeURL(for provider: APIProvider) -> URL? {
        switch provider {
        case .miniMax:
            return URL(string: "https://api.minimax.chat")
        case .glm:
            return URL(string: "https://open.bigmodel.cn")
        case .tavily:
            return URL(string: "https://api.tavily.com")
        case .openAI:
            return URL(string: "https://api.openai.com")
        case .chatGPT:
            return URL(string: "https://chatgpt.com/api/auth/session")
        case .kimi:
            return URL(string: "https://api.moonshot.cn")
        }
    }

    nonisolated private static func classifyFetchError(_ error: Error, language: AppLanguage) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .noAPIKey:
                return localized(
                    zh: "查询失败：未配置凭证",
                    en: "Request failed: missing credential",
                    language: language
                )
            case .httpError(let code), .httpErrorWithMessage(let code, _):
                if code == 401 || code == 403 {
                    return localized(
                        zh: "查询失败：鉴权失败（401/403），请更新凭证",
                        en: "Request failed: authorization error (401/403), update credential",
                        language: language
                    )
                }
                if code == 429 {
                    return localized(
                        zh: "查询失败：触发频率限制（429），请稍后重试",
                        en: "Request failed: rate limited (429), retry later",
                        language: language
                    )
                }
                if code >= 500 {
                    return localized(
                        zh: "查询失败：供应商服务异常（HTTP \(code)）",
                        en: "Request failed: provider service error (HTTP \(code))",
                        language: language
                    )
                }
            case .decodingError:
                return localized(
                    zh: "查询失败：响应结构变化，解析失败",
                    en: "Request failed: response schema changed (decode error)",
                    language: language
                )
            case .networkError(let wrapped):
                return classifyNetworkWrappedError(wrapped, language: language)
            case .invalidURL, .invalidResponse:
                return localized(
                    zh: "查询失败：接口响应异常",
                    en: "Request failed: invalid endpoint response",
                    language: language
                )
            }
        }

        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("401") || lowered.contains("403") || lowered.contains("unauthorized") || lowered.contains("forbidden") {
            return localized(
                zh: "查询失败：鉴权失败，请更新凭证",
                en: "Request failed: authorization failed, update credential",
                language: language
            )
        }
        if lowered.contains("429") || lowered.contains("rate") {
            return localized(
                zh: "查询失败：触发频率限制，请稍后重试",
                en: "Request failed: rate limited, retry later",
                language: language
            )
        }
        if lowered.contains("decode") || lowered.contains("json") || lowered.contains("parse") {
            return localized(
                zh: "查询失败：响应结构变化，解析失败",
                en: "Request failed: response schema changed",
                language: language
            )
        }
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return localized(
                zh: "查询失败：请求超时",
                en: "Request failed: timeout",
                language: language
            )
        }
        return localized(
            zh: "查询失败：未知错误，请稍后重试",
            en: "Request failed: unknown error, retry later",
            language: language
        )
    }

    nonisolated private static func classifyNetworkWrappedError(
        _ wrapped: Error,
        language: AppLanguage
    ) -> String {
        if let urlError = wrapped as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return localized(
                    zh: "查询失败：网络不可用",
                    en: "Request failed: network unavailable",
                    language: language
                )
            case .timedOut:
                return localized(
                    zh: "查询失败：请求超时",
                    en: "Request failed: timeout",
                    language: language
                )
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return localized(
                    zh: "查询失败：无法连接供应商接口",
                    en: "Request failed: cannot reach provider endpoint",
                    language: language
                )
            default:
                break
            }
        }
        let nsError = wrapped as NSError
        if nsError.domain == NSURLErrorDomain {
            return localized(
                zh: "查询失败：网络异常，请稍后重试",
                en: "Request failed: network error, retry later",
                language: language
            )
        }
        return localized(
            zh: "查询失败：供应商接口异常",
            en: "Request failed: provider endpoint error",
            language: language
        )
    }

    nonisolated private static func localized(zh: String, en: String, language: AppLanguage) -> String {
        language == .english ? en : zh
    }

    private func ensureManualOrderContainsCurrentAccounts() {
        let currentIDs = usageData.map(\.accountId)
        guard !currentIDs.isEmpty else { return }

        var merged = dashboardManualOrder.filter { currentIDs.contains($0) }
        for id in currentIDs where !merged.contains(id) {
            merged.append(id)
        }

        if merged != dashboardManualOrder {
            dashboardManualOrder = merged
            Storage.shared.saveDashboardManualOrder(merged)
        }
    }

    private func appendSnapshots(from usageItems: [UsageData], capturedAt: Date) {
        guard !usageItems.isEmpty else { return }
        var changed = false

        for item in usageItems {
            guard let snapshot = makeSnapshot(from: item, capturedAt: capturedAt) else {
                continue
            }

            if let lastForAccount = usageSnapshots.last(where: { $0.accountId == item.accountId }),
               isDuplicateSnapshot(lastForAccount, snapshot) {
                continue
            }

            usageSnapshots.append(snapshot)
            changed = true
        }

        if changed {
            pruneAndPersistSnapshots(now: capturedAt)
        }
    }

    private func makeSnapshot(from data: UsageData, capturedAt: Date) -> UsageSnapshot? {
        guard data.errorMessage == nil else { return nil }

        let primaryPercentage: Double? = {
            guard let total = data.tokenTotal, total > 0 else { return nil }
            return data.usagePercentage
        }()

        let secondaryPercentage: Double? = {
            guard let total = data.monthlyTotal, total > 0 else { return nil }
            return data.monthlyUsagePercentage
        }()

        let hasTrackableValue =
            primaryPercentage != nil ||
            secondaryPercentage != nil ||
            data.tokenUsed != nil ||
            data.monthlyUsed != nil
        guard hasTrackableValue else { return nil }

        return UsageSnapshot(
            accountId: data.accountId,
            provider: data.provider,
            capturedAt: capturedAt,
            tokenUsed: data.tokenUsed,
            tokenTotal: data.tokenTotal,
            monthlyUsed: data.monthlyUsed,
            monthlyTotal: data.monthlyTotal,
            usagePercentage: primaryPercentage,
            monthlyUsagePercentage: secondaryPercentage
        )
    }

    private func isDuplicateSnapshot(_ old: UsageSnapshot, _ new: UsageSnapshot) -> Bool {
        guard new.capturedAt.timeIntervalSince(old.capturedAt) <= snapshotDuplicateWindow else {
            return false
        }
        return old.provider == new.provider &&
            old.tokenUsed == new.tokenUsed &&
            old.tokenTotal == new.tokenTotal &&
            old.monthlyUsed == new.monthlyUsed &&
            old.monthlyTotal == new.monthlyTotal &&
            old.usagePercentage == new.usagePercentage &&
            old.monthlyUsagePercentage == new.monthlyUsagePercentage
    }

    private func pruneAndPersistSnapshots(now: Date) {
        let cutoff = now.addingTimeInterval(-snapshotRetentionDays)
        let freshSnapshots = usageSnapshots.filter { $0.capturedAt >= cutoff }
        let grouped = Dictionary(grouping: freshSnapshots, by: \.accountId)

        var merged: [UsageSnapshot] = []
        merged.reserveCapacity(freshSnapshots.count)
        for (_, accountSnapshots) in grouped {
            let sorted = accountSnapshots.sorted { $0.capturedAt < $1.capturedAt }
            merged.append(contentsOf: sorted.suffix(snapshotMaxPerAccount))
        }
        merged.sort { $0.capturedAt < $1.capturedAt }

        if merged != usageSnapshots {
            usageSnapshots = merged
            rebuildSnapshotsIndex()
            bumpSnapshotRevision()
        }
        Storage.shared.saveUsageSnapshots(usageSnapshots)
    }

    private func removeSnapshotsForDeletedAccounts(validIDs: Set<UUID>) {
        let filtered = usageSnapshots.filter { validIDs.contains($0.accountId) }
        if filtered != usageSnapshots {
            usageSnapshots = filtered
            rebuildSnapshotsIndex()
            bumpSnapshotRevision()
            Storage.shared.saveUsageSnapshots(filtered)
        }
    }

    private func rebuildSnapshotsIndex() {
        snapshotsByAccount = Dictionary(grouping: usageSnapshots, by: \.accountId).mapValues { snapshots in
            snapshots.sorted { $0.capturedAt < $1.capturedAt }
        }
    }

    private func bumpSnapshotRevision() {
        snapshotRevision &+= 1
        trendCache.removeAll(keepingCapacity: true)
    }

}

#if DEBUG
extension AppViewModel {
    var trendCacheEntryCountForTesting: Int { trendCache.count }
    var snapshotRevisionForTesting: UInt64 { snapshotRevision }

    func replaceSnapshotsForTesting(_ snapshots: [UsageSnapshot]) {
        usageSnapshots = snapshots.sorted { $0.capturedAt < $1.capturedAt }
        rebuildSnapshotsIndex()
        bumpSnapshotRevision()
    }
}
#endif
