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
        let cleaned = extractFirstJSONObject(from: raw)
        let payload = cleaned.data(using: .utf8) ?? Data()
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

    static func extractFirstJSONObject(from raw: String) -> String {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let fenceStart = working.range(of: "```") {
            let afterFence = working[fenceStart.upperBound...]
            if let newline = afterFence.firstIndex(of: "\n") {
                working = String(afterFence[afterFence.index(after: newline)...])
            } else {
                working = String(afterFence)
            }

            if let fenceEnd = working.range(of: "```") {
                working = String(working[..<fenceEnd.lowerBound])
            }
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = working.firstIndex(of: "{") else {
            return working
        }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < working.endIndex {
            let character = working[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(working[start...index])
                }
            }

            index = working.index(after: index)
        }

        return String(working[start...])
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

extension StructuredIntent {
    func toWalletIntentDraft(
        selectedContext: String,
        fallbackChain: ChainProfile
    ) -> WalletIntentDraft? {
        switch action {
        case .transfer:
            let resolvedChain = ChainRegistry.profile(for: chain ?? "") ?? fallbackChain
            let asset = resolveSpendAsset(chain: resolvedChain, defaultForSwap: false)
            var missingFields: [String] = []
            if targetAddress.isEmpty {
                missingFields.append("收款地址")
            }
            if spendAmount.isEmpty {
                missingFields.append("转账金额")
            }
            if asset == nil {
                missingFields.append("转账资产")
            }

            let resolvedAsset = asset ?? resolvedChain.defaultSpendToken
            return WalletIntentDraft(
                action: .transfer,
                selectedContext: selectedContext,
                targetAddress: targetAddress,
                targetQuery: "",
                chain: resolvedChain,
                spendAsset: resolvedAsset,
                spendAmount: spendAmount,
                recipientAddress: targetAddress,
                slippage: 0,
                missingFields: missingFields,
                riskNotes: [
                    "AI 只生成计划，不会签名或广播。",
                    "请确认收款地址不可撤销。",
                    "签名前需要输入收款地址后 4 位。"
                ],
                confirmationSummary: "准备在 \(resolvedChain.displayName) 向 \(targetAddress.isEmpty ? "待补充地址" : JSONPrettyPrinter.shortAddress(targetAddress)) 转账 \(spendAmount.isEmpty ? "待补充" : spendAmount) \(resolvedAsset.symbol)。"
            )

        case .swap:
            let resolvedChain = ChainRegistry.profile(for: chain ?? "") ?? fallbackChain
            let asset = resolveSpendAsset(chain: resolvedChain, defaultForSwap: true)
            var missingFields: [String] = []
            if targetAddress.isEmpty && targetQuery.isEmpty {
                missingFields.append("目标代币地址或名称")
            }
            if spendAmount.isEmpty {
                missingFields.append("支付金额")
            }
            if asset == nil {
                missingFields.append("支付资产")
            }

            let resolvedAsset = asset ?? resolvedChain.defaultSpendToken
            let displayTarget: String
            if !targetAddress.isEmpty {
                displayTarget = JSONPrettyPrinter.shortAddress(targetAddress)
            } else if !targetQuery.isEmpty {
                displayTarget = "\(targetQuery)（待确认合约）"
            } else {
                displayTarget = "待补充代币"
            }

            return WalletIntentDraft(
                action: .swap,
                selectedContext: selectedContext,
                targetAddress: targetAddress,
                targetQuery: targetQuery,
                chain: resolvedChain,
                spendAsset: resolvedAsset,
                spendAmount: spendAmount,
                recipientAddress: "",
                slippage: slippagePercent ?? 1.0,
                missingFields: missingFields,
                riskNotes: [
                    "AI 只生成计划，不会签名或广播。",
                    "Uniswap 报价过期后必须重新生成。",
                    "签名前需要核对目标代币合约和支付金额。"
                ],
                confirmationSummary: "准备在 \(resolvedChain.displayName) 用 \(spendAmount.isEmpty ? "待补充" : spendAmount) \(resolvedAsset.symbol) 购买 \(displayTarget)。"
            )

        case .ask, .unsupported, .checkBalance, .checkToken, .checkTx, .checkAddress:
            return nil
        }
    }

    private func resolveSpendAsset(chain: ChainProfile, defaultForSwap: Bool) -> TokenProfile? {
        let normalizedSymbol = spendAssetSymbol.uppercased()
        if normalizedSymbol == "ETH" {
            return .nativeETH
        }

        if normalizedSymbol == "USDC" {
            guard chain.defaultSpendToken.symbol.uppercased() == "USDC" else {
                return nil
            }
            return chain.defaultSpendToken
        }

        if normalizedSymbol.isEmpty {
            return defaultForSwap ? chain.defaultSpendToken : nil
        }

        return nil
    }
}
