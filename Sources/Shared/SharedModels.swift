import Foundation

enum ServiceType: String, Codable, CaseIterable, Identifiable {
    case miniMaxCoding = "miniMaxCoding"
    case miniMaxPayAsGo = "miniMaxPayAsGo"
    case glm = "glm"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .miniMaxCoding:
            return "MiniMax Coding Plan"
        case .miniMaxPayAsGo:
            return "MiniMax Pay-As-You-Go"
        case .glm:
            return "GLM (智谱AI)"
        }
    }
    
    var icon: String {
        switch self {
        case .miniMaxCoding, .miniMaxPayAsGo:
            return "brain"
        case .glm:
            return "cpu"
        }
    }
}

struct UsageData: Codable, Equatable {
    var serviceType: ServiceType
    var tokenRemaining: Double?
    var tokenUsed: Double?
    var tokenTotal: Double?
    var refreshTime: Date?
    var lastUpdated: Date
    var errorMessage: String?
    
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
    
    var usagePercentage: Double {
        guard let used = tokenUsed, let total = tokenTotal, total > 0 else { return 0 }
        return min(used / total * 100, 100)
    }
}

struct AppSettings: Codable {
    var miniMaxCodingAPIKey: String = ""
    var miniMaxPayAsGoAPIKey: String = ""
    var glmAPIKey: String = ""
    var refreshInterval: Int = 5
    var enabledServices: [ServiceType] = [.miniMaxCoding]
    
    static let `default` = AppSettings()
}

final class Storage {
    static let shared = Storage()
    
    private let suiteName = "group.com.mactools.macusagetracker"
    private let usageKey = "usageData"
    private let settingsKey = "appSettings"
    
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
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
        }
    }
    
    func loadSettings() -> AppSettings {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case noAPIKey
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .noAPIKey:
            return "API key not configured"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

protocol UsageService {
    var serviceType: ServiceType { get }
    func fetchUsage(apiKey: String) async throws -> UsageData
}
