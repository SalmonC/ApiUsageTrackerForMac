import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidStatus(OSStatus)
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found"
        case .duplicateItem:
            return "Keychain item already exists"
        case .invalidStatus(let status):
            return "Keychain error: \(status)"
        case .conversionFailed:
            return "Failed to convert data"
        }
    }
}

final class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.mactools.apiusagetracker"
    
    private init() {}
    
    // Save API key to Keychain
    func saveAPIKey(_ apiKey: String, for accountId: UUID) throws {
        let key = accountId.uuidString
        
        // Delete existing item first (to avoid duplicate error)
        try? deleteAPIKey(for: accountId)
        
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.conversionFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.invalidStatus(status)
        }
    }
    
    // Load API key from Keychain
    func loadAPIKey(for accountId: UUID) -> String? {
        let key = accountId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    // Delete API key from Keychain
    func deleteAPIKey(for accountId: UUID) throws {
        let key = accountId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.invalidStatus(status)
        }
    }
    
    // Migrate from UserDefaults to Keychain
    func migrateFromUserDefaults() {
        let defaults = UserDefaults(suiteName: "group.com.mactools.apiusagetracker")
        
        if let data = defaults?.data(forKey: "appSettings"),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            
            for account in settings.accounts where !account.apiKey.isEmpty {
                do {
                    try saveAPIKey(account.apiKey, for: account.id)
                } catch {
                    Logger.log("Failed to migrate API key for account \(account.id): \(error)")
                }
            }
        }
    }
}
