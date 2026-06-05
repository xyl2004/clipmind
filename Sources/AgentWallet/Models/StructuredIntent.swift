import Foundation

enum StructuredIntentAction: String, CaseIterable, Equatable {
    case ask
    case transfer
    case swap
    case unsupported
    case checkBalance = "check_balance"
    case checkToken = "check_token"
    case checkTx = "check_tx"
    case checkAddress = "check_address"
}

struct StructuredIntent: Equatable {
    let action: StructuredIntentAction
    let chain: String?
    let targetAddress: String
    let targetQuery: String
    let transactionHash: String
    let spendAssetSymbol: String
    let spendAmount: String
    let slippagePercent: Double?
    let unsupportedReason: String

    static func empty(action: StructuredIntentAction) -> StructuredIntent {
        StructuredIntent(
            action: action,
            chain: nil,
            targetAddress: "",
            targetQuery: "",
            transactionHash: "",
            spendAssetSymbol: "",
            spendAmount: "",
            slippagePercent: nil,
            unsupportedReason: ""
        )
    }
}

enum StructuredIntentDecodeError: LocalizedError, Equatable {
    case invalidJSON(String)
    case missingField(String)
    case unexpectedFields([String])
    case invalidFieldType(String)
    case invalidAction(String)
    case invalidAddress(String)
    case invalidTransactionHash(String)
    case invalidChain(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "intent JSON unparseable: \(detail)"
        case .missingField(let name):
            return "intent JSON missing field: \(name)"
        case .unexpectedFields(let names):
            return "intent JSON has unexpected fields: \(names.joined(separator: ", "))"
        case .invalidFieldType(let name):
            return "intent JSON field has invalid type: \(name)"
        case .invalidAction(let raw):
            return "intent action not in vocabulary: \(raw)"
        case .invalidAddress(let raw):
            return "intent target_address not 0x+40 hex: \(raw)"
        case .invalidTransactionHash(let raw):
            return "intent transaction_hash not 0x+64 hex: \(raw)"
        case .invalidChain(let raw):
            return "intent chain not in supported list: \(raw)"
        }
    }
}

extension StructuredIntent {
    private static let expectedKeys: Set<String> = [
        "action",
        "chain",
        "target_address",
        "target_query",
        "transaction_hash",
        "spend_asset_symbol",
        "spend_amount",
        "slippage_percent",
        "unsupported_reason"
    ]

    private static let allowedChainIDs = Set(ChainRegistry.supported.map(\.id))

    static func decode(raw: String) throws -> StructuredIntent {
        let payload = raw.data(using: .utf8) ?? Data()
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: payload, options: [])
        } catch {
            throw StructuredIntentDecodeError.invalidJSON(error.localizedDescription)
        }

        guard let object = parsed as? [String: Any] else {
            throw StructuredIntentDecodeError.invalidJSON("top level is not an object")
        }

        try validateKeys(in: object)

        let actionRaw = try requiredString(in: object, key: "action")
        guard let action = StructuredIntentAction(rawValue: actionRaw) else {
            throw StructuredIntentDecodeError.invalidAction(actionRaw)
        }

        let chain = try optionalString(in: object, key: "chain")
        if let chain, !allowedChainIDs.contains(chain) {
            throw StructuredIntentDecodeError.invalidChain(chain)
        }

        let targetAddress = try requiredString(in: object, key: "target_address")
        if !targetAddress.isEmpty, !QueryClassifier.isAddress(targetAddress) {
            throw StructuredIntentDecodeError.invalidAddress(targetAddress)
        }

        let transactionHash = try requiredString(in: object, key: "transaction_hash")
        if !transactionHash.isEmpty, !QueryClassifier.isTransactionHash(transactionHash) {
            throw StructuredIntentDecodeError.invalidTransactionHash(transactionHash)
        }

        return StructuredIntent(
            action: action,
            chain: chain,
            targetAddress: targetAddress,
            targetQuery: try requiredString(in: object, key: "target_query"),
            transactionHash: transactionHash,
            spendAssetSymbol: try requiredString(in: object, key: "spend_asset_symbol"),
            spendAmount: try requiredString(in: object, key: "spend_amount"),
            slippagePercent: try optionalDouble(in: object, key: "slippage_percent"),
            unsupportedReason: try requiredString(in: object, key: "unsupported_reason")
        )
    }

    private static func validateKeys(in object: [String: Any]) throws {
        let keys = Set(object.keys)
        if let missing = expectedKeys.subtracting(keys).sorted().first {
            throw StructuredIntentDecodeError.missingField(missing)
        }

        let unexpected = keys.subtracting(expectedKeys).sorted()
        if !unexpected.isEmpty {
            throw StructuredIntentDecodeError.unexpectedFields(unexpected)
        }
    }

    private static func requiredString(in object: [String: Any], key: String) throws -> String {
        guard let value = object[key] else {
            throw StructuredIntentDecodeError.missingField(key)
        }
        guard let string = value as? String else {
            throw StructuredIntentDecodeError.invalidFieldType(key)
        }
        return string
    }

    private static func optionalString(in object: [String: Any], key: String) throws -> String? {
        guard let value = object[key] else {
            throw StructuredIntentDecodeError.missingField(key)
        }
        if value is NSNull {
            return nil
        }
        guard let string = value as? String else {
            throw StructuredIntentDecodeError.invalidFieldType(key)
        }
        return string.isEmpty ? nil : string
    }

    private static func optionalDouble(in object: [String: Any], key: String) throws -> Double? {
        guard let value = object[key] else {
            throw StructuredIntentDecodeError.missingField(key)
        }
        if value is NSNull {
            return nil
        }
        guard let number = value as? NSNumber else {
            throw StructuredIntentDecodeError.invalidFieldType(key)
        }
        return number.doubleValue
    }
}
