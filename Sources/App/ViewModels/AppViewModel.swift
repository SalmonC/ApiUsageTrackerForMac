import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var isLoading = false
    @Published var settings: AppSettings = .default
    @Published var secondsUntilTokenRefresh: Int = 0
    @Published var refreshingAccountIDs: Set<UUID> = []
    @Published var dashboardSortMode: DashboardSortMode = Storage.shared.loadDashboardSortMode()
    @Published var dashboardManualOrder: [UUID] = Storage.shared.loadDashboardManualOrder()
    
    private var refreshTimer: Timer?
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
            }
        }
    }
    
    private func updateTokenRefreshCountdown() {
        let now = Date()
        var earliestRefresh: Date?
        
        for data in usageData {
            if let refreshTime = data.refreshTime, refreshTime > now {
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
        
        let newData = orderedResults.compactMap { $0 }
        
        usageData = newData
        ensureManualOrderContainsCurrentAccounts()
        Storage.shared.saveUsageData(newData)
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
        let updatedData = await Self.fetchUsageData(for: account)

        if let existingIndex = usageData.firstIndex(where: { $0.accountId == accountId }) {
            usageData[existingIndex] = updatedData
        } else {
            usageData.append(updatedData)
        }
        ensureManualOrderContainsCurrentAccounts()

        Storage.shared.saveUsageData(usageData)
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
                subscriptionPlan: result.subscriptionPlan
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
