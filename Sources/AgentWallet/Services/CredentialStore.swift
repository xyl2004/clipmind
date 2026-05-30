import Foundation
import Security

enum CredentialStore {
    private static let service = "AgentWallet.BAIAPIKey"
    private static let account = "default"
    private static let cacheLock = NSLock()
    private static var cachedBAIAPIKey: String?

    static func readBAIAPIKey() -> String? {
        cacheLock.lock()
        let cached = cachedBAIAPIKey
        cacheLock.unlock()

        if let cached, !cached.isEmpty {
            return cached
        }

        let environment = ProcessInfo.processInfo.environment
        if let value = environment["AGENTWALLET_BAI_API_KEY"], !value.isEmpty {
            store(cache: value)
            return value
        }
        if let value = environment["B_AI_API_KEY"], !value.isEmpty {
            store(cache: value)
            return value
        }

        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }

        store(cache: key)
        return key
    }

    static func hasBAIAPIKey() -> Bool {
        cacheLock.lock()
        let cached = cachedBAIAPIKey
        cacheLock.unlock()

        if let cached, !cached.isEmpty {
            return true
        }

        let environment = ProcessInfo.processInfo.environment
        if let value = environment["AGENTWALLET_BAI_API_KEY"], !value.isEmpty {
            return true
        }
        if let value = environment["B_AI_API_KEY"], !value.isEmpty {
            return true
        }

        return keychainItemExists()
    }

    static func saveBAIAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw CredentialStoreError.emptyKey
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            store(cache: trimmed)
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychainStatus(addStatus)
        }

        store(cache: trimmed)
    }

    /// Drop the in-memory cache so the next read consults the environment / Keychain again.
    /// Used when an HTTP 401 suggests the cached value is stale.
    static func invalidateCache() {
        cacheLock.lock()
        cachedBAIAPIKey = nil
        cacheLock.unlock()
    }

    /// Remove the API key from Keychain (and clear cache). Environment-provided keys
    /// can't be removed by us, so callers should also unset those env vars.
    @discardableResult
    static func clearBAIAPIKey() -> Bool {
        invalidateCache()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func store(cache value: String) {
        cacheLock.lock()
        cachedBAIAPIKey = value
        cacheLock.unlock()
    }

    private static func keychainItemExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

enum CredentialStoreError: LocalizedError {
    case emptyKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "API Key 不能为空。"
        case .keychainStatus(let status):
            "Keychain 保存失败，状态码：\(status)。"
        }
    }
}
