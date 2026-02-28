import Foundation
import AppKit

enum APIProvider: String, Codable, CaseIterable, Identifiable {
    case miniMax = "miniMax"
    case glm = "glm"
    case tavily = "tavily"
    case openAI = "openAI"
    case chatGPT = "chatGPT"
    case kimi = "kimi"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .miniMax:
            return "MiniMax"
        case .glm:
            return "GLM (智谱AI)"
        case .tavily:
            return "Tavily"
        case .openAI:
            return "OpenAI API (Token)"
        case .chatGPT:
            return "ChatGPT (Subscription)"
        case .kimi:
            return "KIMI (Moonshot)"
        }
    }
    
    var icon: String {
        switch self {
        case .miniMax:
            return "brain"
        case .glm:
            return "cpu"
        case .tavily:
            return "magnifyingglass"
        case .openAI:
            return "sparkles"
        case .chatGPT:
            return "message.badge"
        case .kimi:
            return "moon.stars"
        }
    }

    var supportsRemainingQuotaQuery: Bool {
        switch self {
        case .glm:
            return false
        default:
            return true
        }
    }

    var remainingQuotaQueryUnsupportedReason: String? {
        switch self {
        case .glm:
            return "智谱当前未公开可通过 API Key 直接查询账户余额/Token 余量的稳定接口；现有监控端点会返回成功状态但不包含有效数据。"
        default:
            return nil
        }
    }

    static var selectableForNewAccounts: [APIProvider] {
        allCases.filter(\.supportsRemainingQuotaQuery)
    }

    static var unsupportedForRemainingQuotaQuery: [APIProvider] {
        allCases.filter { !$0.supportsRemainingQuotaQuery }
    }
}

enum DashboardSortMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case risk
    case provider
    case name
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .manual:
            return "手动排序"
        case .risk:
            return "风险优先"
        case .provider:
            return "按平台"
        case .name:
            return "按名称"
        }
    }
}

struct APIAccount: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var provider: APIProvider = .miniMax
    var apiKey: String = ""
    var isEnabled: Bool = true
    
    static func == (lhs: APIAccount, rhs: APIAccount) -> Bool {
        lhs.id == rhs.id
    }
}

struct HotkeySetting: Codable, Equatable {
    var keyCode: UInt16 = 0
    var modifiers: UInt32 = 0
    
    static let defaultHotkey = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue))
    
    static func validate(keyCode: UInt16, modifiers: UInt32) -> String? {
        let hasCommand = (modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue)) != 0
        let hasShift = (modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue)) != 0
        let hasOption = (modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue)) != 0
        let hasControl = (modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue)) != 0
        
        if !hasCommand && !hasShift && !hasOption && !hasControl {
            return "Must include at least one modifier key (⌘⇧⌥⌃)"
        }
        
        let invalidKeyCodes: [UInt16] = [48, 49, 51, 53, 36, 76]
        if invalidKeyCodes.contains(keyCode) {
            return "This key cannot be used as hotkey (Tab, Caps Lock, Delete, Escape, Return, Enter)"
        }
        
        return nil
    }
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 {
            parts.append("⌘")
        }
        
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 118: "F4", 119: "F2",
            120: "F1", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "?"
    }
}

struct AppSettings: Codable {
    var accounts: [APIAccount] = []
    var refreshInterval: Int = 5
    var hotkey: HotkeySetting = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue))
    
    static let `default` = AppSettings()
}

struct UsageData: Codable, Equatable {
    var accountId: UUID
    var accountName: String
    var provider: APIProvider
    var tokenRemaining: Double?
    var tokenUsed: Double?
    var tokenTotal: Double?
    var refreshTime: Date?
    var lastUpdated: Date
    var errorMessage: String?
    
    // Additional fields for monthly/limit data
    var monthlyRemaining: Double?      // Monthly remaining quota
    var monthlyTotal: Double?          // Monthly total quota
    var monthlyUsed: Double?           // Monthly used amount
    var monthlyRefreshTime: Date?      // Monthly quota refresh time
    var nextRefreshTime: Date?         // Next refresh time (for limited periods)
    var subscriptionPlan: String? = nil
    
    var displayRemaining: String {
        guard let remaining = tokenRemaining else { return "--" }
        if remaining >= 1000 {
            return String(format: "%.1fK", remaining / 1000)
        }
        return String(format: "%.0f", remaining)
    }
    
    var displayUsed: String {
        guard let used = tokenUsed else { return "--" }
        if used >= 1000 {
            return String(format: "%.1fK", used / 1000)
        }
        return String(format: "%.0f", used)
    }
    
    var displayTotal: String {
        guard let total = tokenTotal else { return "--" }
        if total >= 1000 {
            return String(format: "%.1fK", total / 1000)
        }
        return String(format: "%.0f", total)
    }
    
    var displayMonthlyRemaining: String {
        guard let remaining = monthlyRemaining else { return "--" }
        if remaining >= 1000 {
            return String(format: "%.1fK", remaining / 1000)
        }
        return String(format: "%.0f", remaining)
    }
    
    var displayMonthlyTotal: String {
        guard let total = monthlyTotal else { return "--" }
        if total >= 1000 {
            return String(format: "%.1fK", total / 1000)
        }
        return String(format: "%.0f", total)
    }
    
    var displayMonthlyUsed: String {
        guard let used = monthlyUsed else { return "--" }
        if used >= 1000 {
            return String(format: "%.1fK", used / 1000)
        }
        return String(format: "%.0f", used)
    }
    
    var usagePercentage: Double {
        guard let used = tokenUsed, let total = tokenTotal, total > 0 else { return 0 }
        return min(used / total * 100, 100)
    }
    
    var monthlyUsagePercentage: Double {
        guard let used = monthlyUsed, let total = monthlyTotal, total > 0 else { return 0 }
        return min(used / total * 100, 100)
    }
    
    var displaySubscriptionPlan: String? {
        guard let subscriptionPlan, !subscriptionPlan.isEmpty else { return nil }
        switch subscriptionPlan.lowercased() {
        case "plus":
            return "Plus"
        case "pro":
            return "Pro"
        case "free":
            return "Free"
        case "team":
            return "Team"
        case "business":
            return "Business"
        case "enterprise":
            return "Enterprise"
        case "active":
            return "Subscribed"
        default:
            return subscriptionPlan.capitalized
        }
    }
}

final class Storage {
    static let shared = Storage()
    
    private let suiteName = "group.com.mactools.apiusagetracker"
    private let usageKey = "usageData"
    private let settingsKey = "appSettings"
    private let refreshIntervalKey = "widgetRefreshInterval"
    private let dashboardSortModeKey = "dashboardSortMode"
    private let dashboardManualOrderKey = "dashboardManualOrder"
    
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    
    private init() {}
    
    func saveUsageData(_ data: [UsageData]) {
        guard let defaults = userDefaults else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: usageKey)
        }
    }
    
    func loadUsageData() -> [UsageData] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: usageKey),
              let decoded = try? JSONDecoder().decode([UsageData].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveSettings(_ settings: AppSettings) {
        guard let defaults = userDefaults else { return }
        let existingSettings = loadSettings(includeAPIKeys: false)
        let newAccountIDs = Set(settings.accounts.map(\.id))
        let keychainSnapshot = KeychainManager.shared.loadAPIKeys(for: settings.accounts.map(\.id))
        
        // Remove keys for deleted accounts so they do not linger in Keychain.
        for oldAccount in existingSettings.accounts where !newAccountIDs.contains(oldAccount.id) {
            do {
                try KeychainManager.shared.deleteAPIKey(for: oldAccount.id)
            } catch {
                Logger.log("Failed to delete removed account API key from Keychain: \(error)")
            }
        }
        
        // Save only changed API keys to Keychain to avoid repeated authorization prompts.
        for account in settings.accounts {
            let existingKey = keychainSnapshot[account.id] ?? ""
            if account.apiKey == existingKey {
                continue
            }
            
            if !account.apiKey.isEmpty {
                do {
                    try KeychainManager.shared.saveAPIKey(account.apiKey, for: account.id)
                } catch {
                    Logger.log("Failed to save API key to Keychain: \(error)")
                }
            } else {
                do {
                    try KeychainManager.shared.deleteAPIKey(for: account.id)
                } catch {
                    Logger.log("Failed to clear API key from Keychain: \(error)")
                }
            }
        }
        
        // Save settings without API keys to UserDefaults
        var settingsWithoutKeys = settings
        for i in settingsWithoutKeys.accounts.indices {
            settingsWithoutKeys.accounts[i].apiKey = ""
        }
        
        if let encoded = try? JSONEncoder().encode(settingsWithoutKeys) {
            defaults.set(encoded, forKey: settingsKey)
        }
    }
    
    func loadSettings(includeAPIKeys: Bool = true) -> AppSettings {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: settingsKey),
              var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        
        guard includeAPIKeys else { return decoded }
        
        let keyMap = KeychainManager.shared.loadAPIKeys(for: decoded.accounts.map(\.id))
        for i in decoded.accounts.indices {
            if let keychainKey = keyMap[decoded.accounts[i].id] {
                decoded.accounts[i].apiKey = keychainKey
            }
        }
        
        return decoded
    }
    
    // Save refresh interval separately for widget access
    func saveRefreshInterval(_ minutes: Int) {
        userDefaults?.set(minutes, forKey: refreshIntervalKey)
    }
    
    func loadRefreshInterval() -> Int {
        let interval = userDefaults?.integer(forKey: refreshIntervalKey) ?? 5
        return interval > 0 ? interval : 5
    }
    
    func saveDashboardSortMode(_ mode: DashboardSortMode) {
        userDefaults?.set(mode.rawValue, forKey: dashboardSortModeKey)
    }
    
    func loadDashboardSortMode() -> DashboardSortMode {
        guard
            let rawValue = userDefaults?.string(forKey: dashboardSortModeKey),
            let mode = DashboardSortMode(rawValue: rawValue)
        else {
            return .manual
        }
        return mode
    }
    
    func saveDashboardManualOrder(_ ids: [UUID]) {
        let rawIDs = ids.map(\.uuidString)
        userDefaults?.set(rawIDs, forKey: dashboardManualOrderKey)
    }
    
    func loadDashboardManualOrder() -> [UUID] {
        guard let rawIDs = userDefaults?.stringArray(forKey: dashboardManualOrderKey) else {
            return []
        }
        return rawIDs.compactMap(UUID.init(uuidString:))
    }
}
