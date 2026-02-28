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
    private let keyringAccount = "__api_keys_v2__"
    private var cachedKeys: [UUID: String] = [:]
    private var cachedMissingKeys: Set<UUID> = []
    private var keyringLoaded = false
    private var hasKeyringItem = false
    private var didAttemptLegacyMigration = false
    
    private init() {}
    
    // Load multiple API keys in one go. This prefers a single keyring item so macOS only
    // needs to authorize one Keychain read instead of prompting once per account item.
    func loadAPIKeys(for accountIDs: [UUID]) -> [UUID: String] {
        if !keyringLoaded {
            _ = loadKeyringIntoCache()
        }
        
        var result: [UUID: String] = [:]
        var missingIDs: [UUID] = []
        
        for accountId in accountIDs {
            if let cached = cachedKeys[accountId] {
                result[accountId] = cached
            } else {
                missingIDs.append(accountId)
            }
        }
        
        guard !missingIDs.isEmpty else { return result }
        
        // Legacy migration path: older versions stored one Keychain item per account.
        // We read all legacy items once, migrate to the single keyring item, and avoid
        // repeated prompts on future launches.
        if !hasKeyringItem && !didAttemptLegacyMigration {
            didAttemptLegacyMigration = true
            
            if let legacyMap = loadAllLegacyAPIKeys(),
               !legacyMap.isEmpty {
                for (id, key) in legacyMap {
                    cachedKeys[id] = key
                    cachedMissingKeys.remove(id)
                }
                let _ = saveKeyring(cachedKeys)
                
                for id in legacyMap.keys {
                    try? deleteLegacyAPIKey(for: id)
                }
                
                for accountId in accountIDs {
                    if let key = cachedKeys[accountId] {
                        result[accountId] = key
                    }
                }
                return result
            }
        }
        
        // Mark unresolved ids as missing to avoid repeated Keychain hits in this session.
        for accountId in missingIDs {
            cachedMissingKeys.insert(accountId)
        }
        
        return result
    }
    
    // Save API key to Keychain
    func saveAPIKey(_ apiKey: String, for accountId: UUID) throws {
        if !keyringLoaded {
            _ = loadKeyringIntoCache()
        }
        
        cachedKeys[accountId] = apiKey
        cachedMissingKeys.remove(accountId)
        
        guard saveKeyring(cachedKeys) else {
            throw KeychainError.invalidStatus(errSecIO)
        }
        
        cachedKeys[accountId] = apiKey
        cachedMissingKeys.remove(accountId)
        
        // Cleanup legacy per-account entry if it exists.
        try? deleteLegacyAPIKey(for: accountId)
    }
    
    // Load API key from Keychain
    func loadAPIKey(for accountId: UUID) -> String? {
        if let cached = cachedKeys[accountId] {
            return cached
        }
        if cachedMissingKeys.contains(accountId) {
            return nil
        }

        return loadAPIKeys(for: [accountId])[accountId]
    }
    
    // Delete API key from Keychain
    func deleteAPIKey(for accountId: UUID) throws {
        if !keyringLoaded {
            _ = loadKeyringIntoCache()
        }
        
        cachedKeys.removeValue(forKey: accountId)
        cachedMissingKeys.insert(accountId)
        
        if !saveKeyring(cachedKeys) {
            throw KeychainError.invalidStatus(errSecIO)
        }
        
        cachedKeys.removeValue(forKey: accountId)
        cachedMissingKeys.insert(accountId)
        
        try? deleteLegacyAPIKey(for: accountId)
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
    
    private func loadKeyringIntoCache() -> Bool {
        defer { keyringLoaded = true }
        
        guard let data = loadKeychainItemData(account: keyringAccount) else {
            hasKeyringItem = false
            return false
        }
        hasKeyringItem = true
        
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            for (idString, key) in decoded {
                if let id = UUID(uuidString: idString) {
                    cachedKeys[id] = key
                    cachedMissingKeys.remove(id)
                }
            }
            return !decoded.isEmpty
        }
        
        Logger.log("Failed to decode keyring item, ignoring cached keyring")
        return false
    }
    
    private func saveKeyring(_ keys: [UUID: String]) -> Bool {
        let payload = Dictionary(uniqueKeysWithValues: keys.map { ($0.key.uuidString, $0.value) })
        
        // Empty keyring: remove the aggregate item.
        if payload.isEmpty {
            let status = deleteKeychainItem(account: keyringAccount)
            if status == errSecSuccess || status == errSecItemNotFound {
                hasKeyringItem = false
            }
            return status == errSecSuccess || status == errSecItemNotFound
        }
        
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        let preferredStatus = hasKeyringItem
            ? updateKeychainItem(account: keyringAccount, data: data)
            : addKeychainItem(account: keyringAccount, data: data)
        
        if preferredStatus == errSecSuccess {
            hasKeyringItem = true
            return true
        }
        
        // Recover from stale in-memory existence state without doing an extra Keychain read.
        if preferredStatus == errSecItemNotFound {
            let addStatus = addKeychainItem(account: keyringAccount, data: data)
            if addStatus == errSecSuccess {
                hasKeyringItem = true
                return true
            }
            return false
        }
        
        if preferredStatus == errSecDuplicateItem {
            let updateStatus = updateKeychainItem(account: keyringAccount, data: data)
            if updateStatus == errSecSuccess {
                hasKeyringItem = true
                return true
            }
            return false
        }
        
        return false
    }
    
    private func loadAllLegacyAPIKeys() -> [UUID: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Logger.log("Failed to bulk-load legacy Keychain items: \(status)")
            }
            return nil
        }
        
        let items = (result as? [[String: Any]]) ?? []
        var legacy: [UUID: String] = [:]
        
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account != keyringAccount,
                  let id = UUID(uuidString: account),
                  let data = item[kSecValueData as String] as? Data,
                  let key = String(data: data, encoding: .utf8),
                  !key.isEmpty else {
                continue
            }
            legacy[id] = key
        }
        
        return legacy
    }
    
    private func loadKeychainItemData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    private func addKeychainItem(account: String, data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }
    
    private func updateKeychainItem(account: String, data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data
        ]
        return SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    }
    
    private func deleteKeychainItem(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }
    
    private func deleteLegacyAPIKey(for accountId: UUID) throws {
        let status = deleteKeychainItem(account: accountId.uuidString)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.invalidStatus(status)
        }
    }
}
