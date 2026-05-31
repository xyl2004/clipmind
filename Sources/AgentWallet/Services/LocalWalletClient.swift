import BigInt
import Foundation
import Security
import Web3Core
import web3swift

struct LocalWalletAccount: Equatable {
    let address: String
    let createdAt: Date

    var shortAddress: String {
        JSONPrettyPrinter.shortAddress(address)
    }
}

struct LocalWalletClient {
    private static let service = "AgentWallet.LocalPrivateKey"
    private static let account = "default"

    func loadAccount() throws -> LocalWalletAccount? {
        guard let privateKey = try readPrivateKey() else {
            return nil
        }

        return LocalWalletAccount(address: try Self.address(from: privateKey), createdAt: Date())
    }

    func createWallet() throws -> LocalWalletAccount {
        for _ in 0..<32 {
            var bytes = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                throw LocalWalletError.randomGenerationFailed(status)
            }

            let privateKey = Data(bytes)
            if let publicKey = Utilities.privateToPublic(privateKey),
               let address = Utilities.publicToAddress(publicKey)?.address {
                try savePrivateKey(privateKey)
                return LocalWalletAccount(address: address, createdAt: Date())
            }
        }

        throw LocalWalletError.invalidPrivateKey
    }

    func importWallet(privateKeyHex: String) throws -> LocalWalletAccount {
        let privateKey = try Self.privateKeyData(from: privateKeyHex)
        let address = try Self.address(from: privateKey)
        try savePrivateKey(privateKey)
        return LocalWalletAccount(address: address, createdAt: Date())
    }

    @discardableResult
    func deleteWallet() -> Bool {
        let status = SecItemDelete(Self.baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func signAndBroadcast(
        _ request: EVMTransactionRequest,
        chain: ChainProfile
    ) async throws -> String {
        guard let privateKey = try readPrivateKey() else {
            throw LocalWalletError.walletNotFound
        }

        let walletAddress = try Self.address(from: privateKey)
        let normalizedWallet = walletAddress.lowercased()
        if let from = request.from,
           !from.isEmpty,
           from.lowercased() != normalizedWallet {
            throw LocalWalletError.fromAddressMismatch(expected: walletAddress, actual: from)
        }
        if let chainID = request.chainID, chainID != chain.chainID {
            throw LocalWalletError.chainMismatch(expected: chain.chainID, actual: chainID)
        }

        guard let rpcURL = chain.rpcURL else {
            throw LocalWalletError.missingRPCURL(chain.displayName)
        }

        guard let to = EthereumAddress(request.to, ignoreChecksum: true),
              let from = EthereumAddress(walletAddress, ignoreChecksum: true) else {
            throw LocalWalletError.invalidTransaction
        }

        let network: Networks = .Custom(networkID: BigUInt(chain.chainID))
        let provider = try await Web3HttpProvider(
            url: rpcURL,
            network: network,
            keystoreManager: nil
        )
        let web3 = Web3(provider: provider)
        let nonce = try await web3.eth.getTransactionCount(for: from, onBlock: .pending)

        let value = try Self.bigUInt(from: request.value, defaultValue: 0)
        let data = try Self.data(from: request.data)
        let maxFeePerGas = try Self.optionalBigUInt(from: request.maxFeePerGas)
        let maxPriorityFeePerGas = try Self.optionalBigUInt(from: request.maxPriorityFeePerGas)
        let gasPrice = try await Self.gasPrice(
            from: request.gasPrice,
            web3: web3,
            needsLegacyFallback: maxFeePerGas == nil || maxPriorityFeePerGas == nil
        )

        let transactionType: TransactionType = maxFeePerGas != nil && maxPriorityFeePerGas != nil ? .eip1559 : .legacy
        var transaction = CodableTransaction(
            type: transactionType,
            to: to,
            nonce: nonce,
            chainID: BigUInt(chain.chainID),
            value: value,
            data: data,
            gasLimit: try Self.bigUInt(from: request.gasLimit, defaultValue: 0),
            maxFeePerGas: transactionType == .eip1559 ? maxFeePerGas : nil,
            maxPriorityFeePerGas: transactionType == .eip1559 ? maxPriorityFeePerGas : nil,
            gasPrice: transactionType == .legacy ? gasPrice : nil
        )
        transaction.from = from

        if transaction.gasLimit == 0 {
            let estimated = try await web3.eth.estimateGas(for: transaction)
            transaction.gasLimit = estimated + max(estimated / 10, BigUInt(1))
        }

        try transaction.sign(privateKey: privateKey)
        guard let raw = transaction.encode(for: .transaction) else {
            throw LocalWalletError.signingFailed
        }

        let result = try await web3.eth.send(raw: raw)
        return result.hash
    }

    private func readPrivateKey() throws -> Data? {
        var item: CFTypeRef?
        var query = Self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw LocalWalletError.keychainStatus(status)
        }

        guard let data = item as? Data, data.count == 32 else {
            throw LocalWalletError.invalidPrivateKey
        }

        return data
    }

    private func savePrivateKey(_ privateKey: Data) throws {
        guard privateKey.count == 32 else {
            throw LocalWalletError.invalidPrivateKey
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(Self.baseQuery() as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw LocalWalletError.keychainStatus(updateStatus)
        }

        var addQuery = Self.baseQuery()
        addQuery[kSecValueData as String] = privateKey
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LocalWalletError.keychainStatus(addStatus)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func privateKeyData(from hex: String) throws -> Data {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data.fromHex(trimmed), data.count == 32 else {
            throw LocalWalletError.invalidPrivateKey
        }

        guard Utilities.privateToPublic(data) != nil else {
            throw LocalWalletError.invalidPrivateKey
        }

        return data
    }

    private static func address(from privateKey: Data) throws -> String {
        guard let publicKey = Utilities.privateToPublic(privateKey),
              let address = Utilities.publicToAddress(publicKey)?.address else {
            throw LocalWalletError.invalidPrivateKey
        }

        return address
    }

    private static func data(from value: String?) throws -> Data {
        guard let value, !value.isEmpty else {
            return Data()
        }

        guard let data = Data.fromHex(value) else {
            throw LocalWalletError.invalidTransaction
        }

        return data
    }

    private static func optionalBigUInt(from value: String?) throws -> BigUInt? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return try bigUInt(from: value, defaultValue: nil)
    }

    private static func bigUInt(from value: String?, defaultValue: BigUInt?) throws -> BigUInt {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let defaultValue {
                return defaultValue
            }
            throw LocalWalletError.invalidTransaction
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            guard let number = BigUInt(trimmed.dropFirst(2), radix: 16) else {
                throw LocalWalletError.invalidTransaction
            }
            return number
        }

        guard let number = BigUInt(trimmed, radix: 10) else {
            throw LocalWalletError.invalidTransaction
        }
        return number
    }

    private static func gasPrice(
        from value: String?,
        web3: Web3,
        needsLegacyFallback: Bool
    ) async throws -> BigUInt? {
        if let parsed = try optionalBigUInt(from: value) {
            return parsed
        }

        guard needsLegacyFallback else {
            return nil
        }

        return try await web3.eth.gasPrice()
    }
}

enum LocalWalletError: LocalizedError {
    case walletNotFound
    case invalidPrivateKey
    case invalidTransaction
    case missingRPCURL(String)
    case fromAddressMismatch(expected: String, actual: String)
    case chainMismatch(expected: Int, actual: Int)
    case randomGenerationFailed(OSStatus)
    case keychainStatus(OSStatus)
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .walletNotFound:
            "请先创建或导入本地钱包。"
        case .invalidPrivateKey:
            "私钥无效。请输入 32 字节的 EVM 私钥十六进制字符串。"
        case .invalidTransaction:
            "交易请求无效，无法在本机签名。"
        case .missingRPCURL(let chain):
            "\(chain) 没有可用 RPC。可以设置对应的 AGENTWALLET_RPC_* 环境变量。"
        case .fromAddressMismatch(let expected, let actual):
            "交易发起地址不匹配。本地钱包是 \(JSONPrettyPrinter.shortAddress(expected))，交易要求 \(JSONPrettyPrinter.shortAddress(actual))。"
        case .chainMismatch(let expected, let actual):
            "交易链 ID 不匹配。当前链是 \(expected)，交易要求 \(actual)。"
        case .randomGenerationFailed(let status):
            "生成本地钱包失败，状态码：\(status)。"
        case .keychainStatus(let status):
            "Keychain 钱包操作失败，状态码：\(status)。"
        case .signingFailed:
            "交易签名失败。"
        }
    }
}
