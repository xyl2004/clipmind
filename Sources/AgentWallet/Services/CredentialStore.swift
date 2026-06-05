import Foundation
import Security

enum CredentialStore {
    private static let baiService = "AgentWallet.BAIAPIKey"
    private static let surfService = "AgentWallet.SurfAPIKey"
    private static let uniswapService = "AgentWallet.UniswapAPIKey"
    private static let account = "default"
    private static let cacheLock = NSLock()
    private static var cachedBAIAPIKey: String?
    private static var cachedSurfAPIKey: String?
    private static var cachedUniswapAPIKey: String?

    static func readBAIAPIKey() -> String? {
        readAPIKey(
            service: baiService,
            cachedValue: { cachedBAIAPIKey },
            cacheStore: { cachedBAIAPIKey = $0 },
            environmentKeys: ["CLIPMIND_BAI_API_KEY", "AGENTWALLET_BAI_API_KEY", "B_AI_API_KEY"]
        )
    }

    static func hasBAIAPIKey() -> Bool {
        hasAPIKey(
            service: baiService,
            cachedValue: { cachedBAIAPIKey },
            environmentKeys: ["CLIPMIND_BAI_API_KEY", "AGENTWALLET_BAI_API_KEY", "B_AI_API_KEY"]
        )
    }

    static func saveBAIAPIKey(_ key: String) throws {
        try saveAPIKey(key, service: baiService) { cachedBAIAPIKey = $0 }
    }

    static func readSurfAPIKey() -> String? {
        readAPIKey(
            service: surfService,
            cachedValue: { cachedSurfAPIKey },
            cacheStore: { cachedSurfAPIKey = $0 },
            environmentKeys: ["CLIPMIND_SURF_API_KEY", "SURF_API_KEY"]
        )
    }

    static func hasSurfAPIKey() -> Bool {
        hasAPIKey(
            service: surfService,
            cachedValue: { cachedSurfAPIKey },
            environmentKeys: ["CLIPMIND_SURF_API_KEY", "SURF_API_KEY"]
        )
    }

    static func saveSurfAPIKey(_ key: String) throws {
        try saveAPIKey(key, service: surfService) { cachedSurfAPIKey = $0 }
    }

    static func readUniswapAPIKey() -> String? {
        readAPIKey(
            service: uniswapService,
            cachedValue: { cachedUniswapAPIKey },
            cacheStore: { cachedUniswapAPIKey = $0 },
            environmentKeys: ["CLIPMIND_UNISWAP_API_KEY", "AGENTWALLET_UNISWAP_API_KEY", "UNISWAP_API_KEY"]
        )
    }

    static func readUniswapAPIKeyWithoutPrompt() -> String? {
        readCachedOrEnvironmentAPIKey(
            cachedValue: { cachedUniswapAPIKey },
            cacheStore: { cachedUniswapAPIKey = $0 },
            environmentKeys: ["CLIPMIND_UNISWAP_API_KEY", "AGENTWALLET_UNISWAP_API_KEY", "UNISWAP_API_KEY"]
        )
    }

    static func hasUniswapAPIKey() -> Bool {
        hasAPIKey(
            service: uniswapService,
            cachedValue: { cachedUniswapAPIKey },
            environmentKeys: ["CLIPMIND_UNISWAP_API_KEY", "AGENTWALLET_UNISWAP_API_KEY", "UNISWAP_API_KEY"]
        )
    }

    static func saveUniswapAPIKey(_ key: String) throws {
        try saveAPIKey(key, service: uniswapService) { cachedUniswapAPIKey = $0 }
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
        return clearAPIKey(service: baiService)
    }

    @discardableResult
    static func clearSurfAPIKey() -> Bool {
        cacheLock.lock()
        cachedSurfAPIKey = nil
        cacheLock.unlock()
        return clearAPIKey(service: surfService)
    }

    @discardableResult
    static func clearUniswapAPIKey() -> Bool {
        cacheLock.lock()
        cachedUniswapAPIKey = nil
        cacheLock.unlock()
        return clearAPIKey(service: uniswapService)
    }

    private static func readAPIKey(
        service: String,
        cachedValue: () -> String?,
        cacheStore: (String) -> Void,
        environmentKeys: [String]
    ) -> String? {
        if let available = readCachedOrEnvironmentAPIKey(
            cachedValue: cachedValue,
            cacheStore: cacheStore,
            environmentKeys: environmentKeys
        ) {
            return available
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

        cacheLock.lock()
        cacheStore(key)
        cacheLock.unlock()
        return key
    }

    private static func readCachedOrEnvironmentAPIKey(
        cachedValue: () -> String?,
        cacheStore: (String) -> Void,
        environmentKeys: [String]
    ) -> String? {
        cacheLock.lock()
        let cached = cachedValue()
        cacheLock.unlock()

        if let cached, !cached.isEmpty {
            return cached
        }

        let environment = ProcessInfo.processInfo.environment
        for key in environmentKeys {
            if let value = environment[key], !value.isEmpty {
                cacheLock.lock()
                cacheStore(value)
                cacheLock.unlock()
                return value
            }
        }

        return nil
    }

    private static func hasAPIKey(
        service: String,
        cachedValue: () -> String?,
        environmentKeys: [String]
    ) -> Bool {
        cacheLock.lock()
        let cached = cachedValue()
        cacheLock.unlock()

        if let cached, !cached.isEmpty {
            return true
        }

        let environment = ProcessInfo.processInfo.environment
        for key in environmentKeys where !(environment[key] ?? "").isEmpty {
            return true
        }

        return keychainItemExists(service: service)
    }

    private static func saveAPIKey(
        _ key: String,
        service: String,
        cacheStore: (String) -> Void
    ) throws {
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
            cacheLock.lock()
            cacheStore(trimmed)
            cacheLock.unlock()
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

        cacheLock.lock()
        cacheStore(trimmed)
        cacheLock.unlock()
    }

    private static func clearAPIKey(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func keychainItemExists(service: String) -> Bool {
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
