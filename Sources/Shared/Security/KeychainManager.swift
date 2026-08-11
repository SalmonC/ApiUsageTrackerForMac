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

enum KeychainMigrationPolicy {
    static func shouldReadLegacy(v3Status: OSStatus?, migrationCompleted: Bool) -> Bool {
        v3Status == errSecItemNotFound && !migrationCompleted
    }
}

enum KeychainQueryBuilder {
    static func dataProtectionBase(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

enum KeyringPersistencePolicy {
    static func requiresWrite(current: [UUID: String], target: [UUID: String]) -> Bool {
        current != target
    }
}

final class KeychainManager {
    private enum LoadState {
        case notLoaded
        case loaded
        case absent
        case unavailable(OSStatus)
        case corrupt
    }

    static let shared = KeychainManager()
    
    private let service = "com.mactools.apiusagetracker"
    private let keyringAccount = "__api_keys_v3__"
    private let legacyKeyringAccount = "__api_keys_v2__"
    private let migrationCompletedKey = "keychain.v3.migrationCompleted"
    private let migrationDefaults: UserDefaults
    private var cachedKeys: [UUID: String] = [:]
    private var cachedMissingKeys: Set<UUID> = []
    private var keyringLoaded = false
    private var hasKeyringItem = false
    private var didAttemptLegacyMigration = false
    private var loadState: LoadState = .notLoaded
    private(set) var lastKeyringLoadStatus: OSStatus?
    private(set) var lastKeyringSaveStatus: OSStatus?
    private(set) var lastLegacyLoadStatus: OSStatus?
    
    private init() {
        migrationDefaults = UserDefaults(suiteName: "group.com.mactools.apiusagetracker") ?? .standard
    }
    
    // Load multiple API keys in one go. This prefers a single keyring item so macOS only
    // needs to authorize one Keychain read instead of prompting once per account item.
    func loadAPIKeys(for accountIDs: [UUID]) -> [UUID: String] {
        if !keyringLoaded {
            _ = loadKeyringIntoCache()
        }

        if accountIDs.contains(where: { cachedKeys[$0] == nil }) {
            attemptLegacyMigrationIfNeeded()
        }

        var result: [UUID: String] = [:]
        for accountId in accountIDs {
            if let cached = cachedKeys[accountId] {
                result[accountId] = cached
            } else {
                // Avoid another Keychain read for the same missing ID this session.
                cachedMissingKeys.insert(accountId)
            }
        }
        return result
    }
    
    // Save API key to Keychain
    func saveAPIKey(_ apiKey: String, for accountId: UUID) throws {
        var next = try cachedKeysAfterPreparingForMutation()
        next[accountId] = apiKey
        try replaceAPIKeys(next)
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
        var next = try cachedKeysAfterPreparingForMutation()
        next.removeValue(forKey: accountId)
        try replaceAPIKeys(next)
    }

    /// Replaces the complete keyring with one verified Keychain write. The in-memory
    /// cache is changed only after the persisted payload can be read back exactly.
    @discardableResult
    func replaceAPIKeys(_ keys: [UUID: String]) throws -> [UUID: String] {
        let previous = try cachedKeysAfterPreparingForMutation()
        let normalized = keys.filter { !$0.value.isEmpty }
        guard KeyringPersistencePolicy.requiresWrite(current: previous, target: normalized) else {
            return previous
        }

        guard saveKeyring(normalized) else {
            loadState = .unavailable(lastKeyringSaveStatus ?? errSecDecode)
            throw KeychainError.invalidStatus(lastKeyringSaveStatus ?? errSecDecode)
        }
        guard verifyKeyring(normalized) else {
            lastKeyringSaveStatus = errSecDecode
            let didRollback = saveKeyring(previous) && verifyKeyring(previous)
            loadState = didRollback ? .loaded : .unavailable(errSecDecode)
            throw KeychainError.invalidStatus(errSecDecode)
        }

        cachedKeys = normalized
        cachedMissingKeys.removeAll()
        loadState = .loaded
        migrationDefaults.set(true, forKey: migrationCompletedKey)
        return previous
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
        
        let result = copyKeychainItemData(account: keyringAccount)
        lastKeyringLoadStatus = result.status

        guard result.status == errSecSuccess, let data = result.data else {
            hasKeyringItem = false
            loadState = result.status == errSecItemNotFound
                ? .absent
                : .unavailable(result.status)
            if result.status != errSecItemNotFound {
                Logger.critical("Keychain keyring load failed: status=\(result.status)")
            }
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
            loadState = .loaded
            migrationDefaults.set(true, forKey: migrationCompletedKey)
            return !decoded.isEmpty
        }
        
        loadState = .corrupt
        Logger.critical("Keychain keyring decode failed; keeping settings without API keys")
        return false
    }

    private func cachedKeysAfterPreparingForMutation() throws -> [UUID: String] {
        if !keyringLoaded {
            _ = loadKeyringIntoCache()
        }

        attemptLegacyMigrationIfNeeded()

        switch loadState {
        case .loaded, .absent:
            return cachedKeys
        case .unavailable(let status):
            throw KeychainError.invalidStatus(status)
        case .corrupt:
            throw KeychainError.invalidStatus(errSecDecode)
        case .notLoaded:
            throw KeychainError.invalidStatus(errSecNotAvailable)
        }
    }

    private func attemptLegacyMigrationIfNeeded() {
        guard case .absent = loadState,
              KeychainMigrationPolicy.shouldReadLegacy(
                  v3Status: lastKeyringLoadStatus,
                  migrationCompleted: migrationDefaults.bool(forKey: migrationCompletedKey)
              ),
              !didAttemptLegacyMigration else { return }

        didAttemptLegacyMigration = true
        let legacyResult = loadLegacyAPIKeysForMigration()
        lastLegacyLoadStatus = legacyResult.status

        switch legacyResult.status {
        case errSecSuccess:
            cachedKeys = legacyResult.keys
            cachedMissingKeys.removeAll()
            if saveKeyring(cachedKeys), verifyKeyring(cachedKeys) {
                loadState = .loaded
                migrationDefaults.set(true, forKey: migrationCompletedKey)
                Logger.log("Keychain v3 migration verified; legacy rollback copy retained")
            } else {
                let migrationFailureStatus = lastKeyringSaveStatus == errSecSuccess
                    ? errSecDecode
                    : (lastKeyringSaveStatus ?? errSecDecode)
                let deleteStatus = deleteKeychainItem(account: keyringAccount)
                let confirmationStatus = copyKeychainItemData(account: keyringAccount).status
                let rollbackConfirmed = (deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound)
                    && confirmationStatus == errSecItemNotFound
                if rollbackConfirmed {
                    hasKeyringItem = false
                    loadState = .absent
                    lastKeyringSaveStatus = migrationFailureStatus
                    Logger.critical("Keychain v3 migration verification failed and partial v3 item was removed; legacy items preserved")
                } else {
                    let rollbackFailureStatus = (deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound)
                        ? confirmationStatus
                        : deleteStatus
                    loadState = .unavailable(rollbackFailureStatus)
                    lastKeyringSaveStatus = rollbackFailureStatus
                    Logger.critical("Keychain v3 migration verification failed and partial-item rollback failed: status=\(rollbackFailureStatus); legacy items preserved")
                }
            }
        case errSecItemNotFound:
            loadState = .absent
        default:
            loadState = .unavailable(legacyResult.status)
        }
    }
    
    private func saveKeyring(_ keys: [UUID: String]) -> Bool {
        let payload = Dictionary(uniqueKeysWithValues: keys.map { ($0.key.uuidString, $0.value) })
        
        guard let data = try? JSONEncoder().encode(payload) else {
            lastKeyringSaveStatus = errSecParam
            return false
        }
        let preferredStatus = hasKeyringItem
            ? updateKeychainItem(account: keyringAccount, data: data)
            : addKeychainItem(account: keyringAccount, data: data)
        lastKeyringSaveStatus = preferredStatus
        
        if preferredStatus == errSecSuccess {
            hasKeyringItem = true
            return true
        }
        
        // Recover from stale in-memory existence state without doing an extra Keychain read.
        if preferredStatus == errSecItemNotFound {
            let addStatus = addKeychainItem(account: keyringAccount, data: data)
            lastKeyringSaveStatus = addStatus
            if addStatus == errSecSuccess {
                hasKeyringItem = true
                return true
            }
            return false
        }
        
        if preferredStatus == errSecDuplicateItem {
            let updateStatus = updateKeychainItem(account: keyringAccount, data: data)
            lastKeyringSaveStatus = updateStatus
            if updateStatus == errSecSuccess {
                hasKeyringItem = true
                return true
            }
            return false
        }
        
        return false
    }
    
    private func loadLegacyAPIKeysForMigration() -> (status: OSStatus, keys: [UUID: String]) {
        let aggregateResult = copyLegacyKeychainItemData(account: legacyKeyringAccount)
        if aggregateResult.status == errSecSuccess, let data = aggregateResult.data {
            guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                Logger.critical("Legacy Keychain keyring decode failed; legacy items preserved")
                return (errSecDecode, [:])
            }
            var keys: [UUID: String] = [:]
            for (idString, key) in decoded {
                guard let id = UUID(uuidString: idString), !key.isEmpty else { continue }
                keys[id] = key
            }
            return (errSecSuccess, keys)
        }

        // Authorization or interaction failures must not trigger another Keychain query.
        guard aggregateResult.status == errSecItemNotFound else {
            Logger.critical("Legacy Keychain keyring load failed: status=\(aggregateResult.status)")
            return (aggregateResult.status, [:])
        }

        return loadAllLegacyAPIKeys()
    }

    private func loadAllLegacyAPIKeys() -> (status: OSStatus, keys: [UUID: String]) {
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
                Logger.critical("Failed to bulk-load legacy Keychain items: status=\(status)")
            }
            return (status, [:])
        }
        
        let items = (result as? [[String: Any]]) ?? []
        var legacy: [UUID: String] = [:]
        
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account != keyringAccount,
                  account != legacyKeyringAccount,
                  let id = UUID(uuidString: account),
                  let data = item[kSecValueData as String] as? Data,
                  let key = String(data: data, encoding: .utf8),
                  !key.isEmpty else {
                continue
            }
            legacy[id] = key
        }

        return legacy.isEmpty ? (errSecItemNotFound, [:]) : (errSecSuccess, legacy)
    }
    
    private func copyKeychainItemData(account: String) -> (status: OSStatus, data: Data?) {
        var query = KeychainQueryBuilder.dataProtectionBase(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return (status, nil) }
        return (status, result as? Data)
    }

    private func copyLegacyKeychainItemData(account: String) -> (status: OSStatus, data: Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return (status, nil) }
        return (status, result as? Data)
    }
    
    private func addKeychainItem(account: String, data: Data) -> OSStatus {
        var query = KeychainQueryBuilder.dataProtectionBase(service: service, account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil)
    }
    
    private func updateKeychainItem(account: String, data: Data) -> OSStatus {
        let query = KeychainQueryBuilder.dataProtectionBase(service: service, account: account)
        let attrs: [String: Any] = [
            kSecValueData as String: data
        ]
        return SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    }

    private func deleteKeychainItem(account: String) -> OSStatus {
        let query = KeychainQueryBuilder.dataProtectionBase(service: service, account: account)
        return SecItemDelete(query as CFDictionary)
    }
    
    private func verifyKeyring(_ expected: [UUID: String]) -> Bool {
        let result = copyKeychainItemData(account: keyringAccount)
        guard result.status == errSecSuccess,
              let data = result.data,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return false
        }
        let expectedPayload = Dictionary(uniqueKeysWithValues: expected.map { ($0.key.uuidString, $0.value) })
        return decoded == expectedPayload
    }

}
