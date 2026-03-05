import Foundation

/// Shared sorting logic for UsageData to ensure consistency between app and widget
enum UsageDataSorting {
    static func sort(
        _ data: [UsageData],
        mode: DashboardSortMode,
        manualOrder: [UUID]
    ) -> [UsageData] {
        switch mode {
        case .manual:
            return sortByManualOrder(data, manualOrder: manualOrder)
        case .risk:
            return sortByRisk(data)
        case .provider:
            return sortByProvider(data)
        case .name:
            return sortByName(data)
        }
    }
    
    private static func sortByManualOrder(_ data: [UsageData], manualOrder: [UUID]) -> [UsageData] {
        let orderIndex = Dictionary(uniqueKeysWithValues: manualOrder.enumerated().map { ($1, $0) })
        return data.sorted { lhs, rhs in
            let l = orderIndex[lhs.accountId] ?? Int.max
            let r = orderIndex[rhs.accountId] ?? Int.max
            if l != r { return l < r }
            return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
        }
    }
    
    private static func sortByRisk(_ data: [UsageData]) -> [UsageData] {
        return data.sorted { lhs, rhs in
            let lRank = riskRank(for: lhs)
            let rRank = riskRank(for: rhs)
            if lRank != rRank { return lRank < rRank }
            if abs(lhs.usagePercentage - rhs.usagePercentage) > .ulpOfOne {
                return lhs.usagePercentage > rhs.usagePercentage
            }
            if abs(lhs.monthlyUsagePercentage - rhs.monthlyUsagePercentage) > .ulpOfOne {
                return lhs.monthlyUsagePercentage > rhs.monthlyUsagePercentage
            }
            return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
        }
    }
    
    private static func sortByProvider(_ data: [UsageData]) -> [UsageData] {
        return data.sorted { lhs, rhs in
            if lhs.provider.displayName != rhs.provider.displayName {
                return lhs.provider.displayName.localizedCaseInsensitiveCompare(rhs.provider.displayName) == .orderedAscending
            }
            return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
        }
    }
    
    private static func sortByName(_ data: [UsageData]) -> [UsageData] {
        return data.sorted {
            $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending
        }
    }
    
    static func riskRank(for data: UsageData) -> Int {
        if data.errorMessage != nil { return 0 }
        if data.tokenTotal != nil {
            let pct = data.usagePercentage
            if pct > 90 { return 1 }
            if pct > 70 { return 2 }
            if pct > 50 { return 3 }
            return 4
        }
        if data.monthlyTotal != nil {
            let pct = data.monthlyUsagePercentage
            if pct > 90 { return 1 }
            if pct > 70 { return 2 }
            if pct > 50 { return 3 }
            return 4
        }
        return 5
    }
}
