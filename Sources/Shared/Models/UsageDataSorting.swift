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
}
