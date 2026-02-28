import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var isLoading = false
    @Published var settings: AppSettings = .default
    @Published var secondsUntilTokenRefresh: Int = 0
    @Published var secondsUntilDataRefresh: Int = 0
    @Published var refreshingAccountIDs: Set<UUID> = []
    @Published var dashboardSortMode: DashboardSortMode = Storage.shared.loadDashboardSortMode()
    @Published var dashboardManualOrder: [UUID] = Storage.shared.loadDashboardManualOrder()
    
    private var refreshTimer: Timer?
    private var cycleLearningState: [String: CycleLearningState] = Storage.shared.loadCycleLearningState()
    private var nextAutoRefreshDate: Date?
    var onSettingsSaved: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    
    init() {
        loadSettings()
        loadCachedData()
        Storage.shared.saveRefreshInterval(settings.refreshInterval)
        startCountdownTimer()
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
    
    private func startCountdownTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        updateTokenRefreshCountdown()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.secondsUntilTokenRefresh > 0 {
                    self.secondsUntilTokenRefresh -= 1
                } else {
                    self.updateTokenRefreshCountdown()
                }
                if self.secondsUntilDataRefresh > 0 {
                    self.secondsUntilDataRefresh -= 1
                } else {
                    self.updateDataRefreshCountdown()
                }
            }
        }
    }
    
    private func updateTokenRefreshCountdown() {
        let now = Date()
        var earliestRefresh: Date?
        
        for data in usageData {
            let candidates = [data.nextRefreshTime, data.refreshTime, data.monthlyRefreshTime]
            for refreshTime in candidates.compactMap({ $0 }) where refreshTime > now {
                if earliestRefresh == nil || refreshTime < earliestRefresh! {
                    earliestRefresh = refreshTime
                }
            }
        }
        
        if let refresh = earliestRefresh {
            secondsUntilTokenRefresh = Int(refresh.timeIntervalSince(now))
        } else {
            secondsUntilTokenRefresh = 0
        }
    }

    private func updateDataRefreshCountdown() {
        guard let nextAutoRefreshDate else {
            secondsUntilDataRefresh = 0
            return
        }
        let seconds = Int(nextAutoRefreshDate.timeIntervalSince(Date()))
        secondsUntilDataRefresh = max(seconds, 0)
    }

    func setNextAutoRefreshDate(_ date: Date?) {
        nextAutoRefreshDate = date
        updateDataRefreshCountdown()
    }
    
    func resetCountdown() {
        startCountdownTimer()
    }
    
    func refreshAll(reloadSettings: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        if reloadSettings {
            loadSettings()
        }
        let activeAccounts = settings.accounts.filter { $0.isEnabled && !$0.apiKey.isEmpty }
        var orderedResults = Array<UsageData?>(repeating: nil, count: activeAccounts.count)
        
        await withTaskGroup(of: (Int, UsageData).self) { group in
            for (index, account) in activeAccounts.enumerated() {
                group.addTask {
                    return (index, await Self.fetchUsageData(for: account))
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
        Storage.shared.saveCycleLearningState(cycleLearningState)
        updateTokenRefreshCountdown()
        
        WidgetCenter.shared.reloadAllTimelines()
        
        isLoading = false
    }

    func refreshAccount(_ accountId: UUID) async {
        guard !isLoading else { return }
        guard !refreshingAccountIDs.contains(accountId) else { return }

        loadSettings()
        guard let account = settings.accounts.first(where: { $0.id == accountId && $0.isEnabled && !$0.apiKey.isEmpty }) else {
            return
        }

        refreshingAccountIDs.insert(accountId)
        let updatedData = resolveRefreshTime(await Self.fetchUsageData(for: account))

        if let existingIndex = usageData.firstIndex(where: { $0.accountId == accountId }) {
            usageData[existingIndex] = updatedData
        } else {
            usageData.append(updatedData)
        }
        ensureManualOrderContainsCurrentAccounts()

        Storage.shared.saveUsageData(usageData)
        Storage.shared.saveCycleLearningState(cycleLearningState)
        updateTokenRefreshCountdown()
        WidgetCenter.shared.reloadAllTimelines()
        refreshingAccountIDs.remove(accountId)
    }
    
    func saveSettings(_ newSettings: AppSettings) {
        settings = newSettings
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

    var displayUsageData: [UsageData] {
        switch dashboardSortMode {
        case .manual:
            let orderIndex = Dictionary(uniqueKeysWithValues: dashboardManualOrder.enumerated().map { ($1, $0) })
            return usageData.sorted { lhs, rhs in
                let l = orderIndex[lhs.accountId] ?? Int.max
                let r = orderIndex[rhs.accountId] ?? Int.max
                if l != r { return l < r }
                return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
            }
        case .risk:
            return usageData.sorted { lhs, rhs in
                let lRank = riskRank(for: lhs)
                let rRank = riskRank(for: rhs)
                if lRank != rRank { return lRank < rRank }
                if abs(lhs.usagePercentage - rhs.usagePercentage) > .ulpOfOne {
                    return lhs.usagePercentage > rhs.usagePercentage
                }
                return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
            }
        case .provider:
            return usageData.sorted { lhs, rhs in
                if lhs.provider.displayName != rhs.provider.displayName {
                    return lhs.provider.displayName.localizedCaseInsensitiveCompare(rhs.provider.displayName) == .orderedAscending
                }
                return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
            }
        case .name:
            return usageData.sorted {
                $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending
            }
        }
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

    nonisolated private static func fetchUsageData(for account: APIAccount) async -> UsageData {
        let service = getService(for: account.provider)

        do {
            let result = try await service.fetchUsage(apiKey: account.apiKey)
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
        } catch {
            return UsageData(
                accountId: account.id,
                accountName: account.name.isEmpty ? account.provider.displayName : account.name,
                provider: account.provider,
                tokenRemaining: nil,
                tokenUsed: nil,
                tokenTotal: nil,
                refreshTime: nil,
                lastUpdated: Date(),
                errorMessage: error.localizedDescription,
                monthlyRemaining: nil,
                monthlyTotal: nil,
                monthlyUsed: nil,
                monthlyRefreshTime: nil,
                nextRefreshTime: nil,
                subscriptionPlan: nil
            )
        }
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

    private func riskRank(for data: UsageData) -> Int {
        if data.errorMessage != nil { return 0 }
        if data.tokenTotal != nil {
            let pct = data.usagePercentage
            if pct > 90 { return 1 }
            if pct > 70 { return 2 }
            if pct > 50 { return 3 }
            return 4
        }
        return 5
    }
}
