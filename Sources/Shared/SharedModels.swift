import Foundation
import AppKit

enum APIProvider: String, Codable, CaseIterable, Identifiable {
    case miniMax = "miniMax"
    case glm = "glm"
    case tavily = "tavily"
    case openAI = "openAI"
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
            return "OpenAI"
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
        case .kimi:
            return "moon.stars"
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
}

final class Storage {
    static let shared = Storage()
    
    private let suiteName = "group.com.mactools.apiusagetracker"
    private let usageKey = "usageData"
    private let settingsKey = "appSettings"
    private let refreshIntervalKey = "widgetRefreshInterval"
    
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
        
        // Save API keys to Keychain
        for account in settings.accounts {
            if !account.apiKey.isEmpty {
                do {
                    try KeychainManager.shared.saveAPIKey(account.apiKey, for: account.id)
                } catch {
                    Logger.log("Failed to save API key to Keychain: \(error)")
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
    
    func loadSettings() -> AppSettings {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: settingsKey),
              var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        
        // Load API keys from Keychain
        for i in decoded.accounts.indices {
            if let keychainKey = KeychainManager.shared.loadAPIKey(for: decoded.accounts[i].id) {
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
        userDefaults?.integer(forKey: refreshIntervalKey) ?? 5
    }
}
