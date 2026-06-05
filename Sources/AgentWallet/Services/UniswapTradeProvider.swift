import Foundation

struct UniswapTradePlan: Identifiable {
    static let quoteValiditySeconds: TimeInterval = 30

    let id = UUID()
    let createdAt: Date
    let expiresAt: Date
    let chain: ChainProfile
    let walletAddress: String
    let inputToken: TokenProfile
    let outputTokenAddress: String
    let inputAmount: String
    let inputAmountBaseUnits: String
    let slippageTolerance: Double
    let approvalTransaction: EVMTransactionRequest?
    let approvalGasFee: String?
    let quoteRequestID: String?
    let routing: String
    let outputAmount: String?
    let gasFee: String?
    let swapTransaction: EVMTransactionRequest?
    let safetyChecks: [String]
    let rawQuoteJSON: String
    let rawSwapJSON: String?

    var needsApproval: Bool {
        approvalTransaction?.hasCalldata == true
    }

    var confirmationCode: String {
        String(walletAddress.suffix(4)).uppercased()
    }

    var quoteFreshnessStatus: String {
        if isFreshForSigning {
            return "约 \(max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.down)))) 秒内有效"
        }

        return "已过期，请重新生成"
    }

    var isFreshForSigning: Bool {
        isFresh(at: Date())
    }

    func isFresh(at date: Date) -> Bool {
        date < expiresAt
    }
}

enum ContractRiskLevel: Int, Hashable {
    case low = 0
    case medium = 1
    case high = 2
    case blocked = 3

    var title: String {
        switch self {
        case .low:
            return "低风险"
        case .medium:
            return "中风险"
        case .high:
            return "高风险"
        case .blocked:
            return "已拦截"
        }
    }
}

struct UniswapTokenCandidate: Identifiable, Hashable {
    enum LiquidityStatus: String {
        case quoted
        case noQuote

        var title: String {
            switch self {
            case .quoted:
                return "可报价"
            case .noQuote:
                return "无可用报价"
            }
        }
    }

    let id: String
    let chain: ChainProfile
    let name: String
    let symbol: String
    let address: String
    let decimals: Int
    let safetyLevel: String?
    let isSpam: Bool?
    let rank: Int
    let matchReason: String
    let status: LiquidityStatus
    let riskLevel: ContractRiskLevel
    let riskReasons: [String]
    let outputAmount: String?
    let referencePriceUSD: Double?
    let impliedPriceUSD: Double?
    let priceDeviationPercent: Double?
    let gasFeeUSD: String?
    let priceImpact: Double?
    let routeSummary: String?
    let liquiditySummary: String?
    let quoteError: String?
    let rawQuoteJSON: String?

    var tokenProfile: TokenProfile {
        TokenProfile(symbol: symbol, address: address, decimals: decimals)
    }

    var canSelectForSwap: Bool {
        status == .quoted && riskLevel != .blocked
    }

    var shortAddress: String {
        JSONPrettyPrinter.shortAddress(address)
    }
}

struct EVMTransactionRequest: Hashable {
    let to: String
    let from: String?
    let data: String?
    let value: String?
    let gasLimit: String?
    let chainID: Int?
    let maxFeePerGas: String?
    let maxPriorityFeePerGas: String?
    let gasPrice: String?

    var hasCalldata: Bool {
        guard let data else {
            return false
        }
        return data != "0x" && !data.isEmpty && Self.isHex(data)
    }

    var shortTo: String {
        JSONPrettyPrinter.shortAddress(to)
    }

    init(
        to: String,
        from: String?,
        data: String?,
        value: String?,
        gasLimit: String?,
        chainID: Int?,
        maxFeePerGas: String?,
        maxPriorityFeePerGas: String?,
        gasPrice: String?
    ) {
        self.to = to
        self.from = from
        self.data = data
        self.value = value
        self.gasLimit = gasLimit
        self.chainID = chainID
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.gasPrice = gasPrice
    }

    init?(_ object: Any?) {
        guard let dictionary = object as? [String: Any],
              let to = dictionary["to"] as? String,
              !to.isEmpty else {
            return nil
        }

        self.to = to
        self.from = dictionary["from"] as? String
        self.data = dictionary["data"] as? String
        self.value = dictionary["value"].map { "\($0)" }
        self.gasLimit = dictionary["gasLimit"].map { "\($0)" }
        self.chainID = dictionary["chainId"] as? Int ?? (dictionary["chainId"] as? NSNumber)?.intValue
        self.maxFeePerGas = dictionary["maxFeePerGas"].map { "\($0)" }
        self.maxPriorityFeePerGas = dictionary["maxPriorityFeePerGas"].map { "\($0)" }
        self.gasPrice = dictionary["gasPrice"].map { "\($0)" }
    }

    func validateForBroadcast(
        expectedFrom: String,
        expectedChainID: Int,
        requiresCalldata: Bool
    ) throws {
        guard QueryClassifier.isAddress(to) else {
            throw UniswapTradeError.invalidTransaction("交易目标地址无效。")
        }

        guard let from, QueryClassifier.isAddress(from) else {
            throw UniswapTradeError.invalidTransaction("交易发起地址无效。")
        }

        guard from.lowercased() == expectedFrom.lowercased() else {
            throw UniswapTradeError.invalidTransaction("交易发起地址和本地钱包不一致。")
        }

        guard chainID == nil || chainID == expectedChainID else {
            throw UniswapTradeError.invalidTransaction("交易链 ID 和当前链不一致。")
        }

        if requiresCalldata {
            guard hasCalldata else {
                throw UniswapTradeError.invalidTransaction("交易 calldata 为空或不是有效十六进制。请重新生成报价。")
            }
        }

        guard value != nil else {
            throw UniswapTradeError.invalidTransaction("交易 value 缺失。")
        }
    }

    private static func isHex(_ value: String) -> Bool {
        guard value.hasPrefix("0x"), value.count > 2 else {
            return false
        }

        return value.dropFirst(2).allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character.lowercased())
        }
    }
}

protocol TradeProvider {
    func buildSwapPlan(
        draft: TradeIntentDraft,
        chain: ChainProfile,
        walletAddress: String
    ) async throws -> UniswapTradePlan
}

struct UniswapTradeProvider: TradeProvider {
    private static let defaultBaseURL = URL(string: "https://trade-api.gateway.uniswap.org/v1")!
    private static let tokenListURL = URL(string: "https://tokens.uniswap.org")!
    private static let baseURLOverrideEnvKeys = ["CLIPMIND_UNISWAP_BASE_URL", "AGENTWALLET_UNISWAP_BASE_URL"]
    private static let candidateProbeLimit = 8
    private let session: URLSession
    private let apiKeyOverride: String?

    init(session: URLSession = .shared, apiKeyOverride: String? = nil) {
        self.session = session
        self.apiKeyOverride = apiKeyOverride
    }

    private var baseURL: URL {
        let environment = ProcessInfo.processInfo.environment
        return Self.baseURLOverrideEnvKeys.compactMap { environment[$0] }
            .first(where: { !$0.isEmpty })
            .flatMap { URL(string: $0) }
            ?? Self.defaultBaseURL
    }

    func resolveTokenCandidates(
        query: String,
        chain: ChainProfile,
        spendAsset: TokenProfile,
        spendAmount: String,
        walletAddress: String,
        referencePriceUSD: Double?
    ) async throws -> [UniswapTokenCandidate] {
        let normalizedQuery = QueryClassifier.normalizedLookupText(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let amountBaseUnits = try Self.baseUnits(amount: spendAmount, decimals: spendAsset.decimals)
        let entries = try await tokenListEntries(matching: normalizedQuery, chain: chain)
        guard !entries.isEmpty else {
            return []
        }

        var candidates: [UniswapTokenCandidate] = []
        for entry in entries.prefix(Self.candidateProbeLimit) {
            let candidate = await liquidityCandidate(
                entry: entry,
                chain: chain,
                spendAsset: spendAsset,
                spendAmount: spendAmount,
                amountBaseUnits: amountBaseUnits,
                walletAddress: walletAddress,
                referencePriceUSD: referencePriceUSD
            )
            candidates.append(candidate)
        }

        return candidates.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .quoted
            }
            if lhs.priceDeviationPercent != rhs.priceDeviationPercent {
                switch (lhs.priceDeviationPercent, rhs.priceDeviationPercent) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
            }
            if lhs.riskLevel != rhs.riskLevel {
                return lhs.riskLevel.rawValue < rhs.riskLevel.rawValue
            }
            return lhs.rank < rhs.rank
        }
    }

    private struct TokenListEntry {
        let name: String
        let symbol: String
        let address: String
        let decimals: Int
        let safetyLevel: String?
        let isSpam: Bool?
        let rank: Int
        let matchReason: String
    }

    private func tokenListEntries(
        matching query: String,
        chain: ChainProfile
    ) async throws -> [TokenListEntry] {
        var request = URLRequest(url: Self.tokenListURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = JSONPrettyPrinter.parse(String(data: data, encoding: .utf8) ?? "") as? [String: Any] else {
            throw UniswapTradeError.invalidResponse
        }

        let normalizedQuery = query.lowercased()
        var seenAddresses = Set<String>()
        let entries = JSONPrettyPrinter.array(object, path: ["tokens"]).compactMap { item -> TokenListEntry? in
            guard let dictionary = item as? [String: Any],
                  let chainID = dictionary["chainId"] as? Int,
                  chainID == chain.chainID,
                  let address = dictionary["address"] as? String,
                  QueryClassifier.isAddress(address),
                  let name = dictionary["name"] as? String,
                  let symbol = dictionary["symbol"] as? String else {
                return nil
            }

            let normalizedAddress = address.lowercased()
            guard !seenAddresses.contains(normalizedAddress) else {
                return nil
            }

            guard let match = Self.matchRankAndReason(
                query: normalizedQuery,
                name: name,
                symbol: symbol
            ) else {
                return nil
            }

            seenAddresses.insert(normalizedAddress)
            let decimals = dictionary["decimals"] as? Int
                ?? (dictionary["decimals"] as? NSNumber)?.intValue
                ?? 18
            let project = dictionary["project"] as? [String: Any]
            let safetyLevel = dictionary["safetyLevel"] as? String
                ?? project?["safetyLevel"] as? String
            let isSpam = dictionary["isSpam"] as? Bool
                ?? project?["isSpam"] as? Bool
            return TokenListEntry(
                name: name,
                symbol: symbol,
                address: address,
                decimals: decimals,
                safetyLevel: safetyLevel,
                isSpam: isSpam,
                rank: match.rank,
                matchReason: match.reason
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            if lhs.symbol.count != rhs.symbol.count {
                return lhs.symbol.count < rhs.symbol.count
            }
            return lhs.name < rhs.name
        }
    }

    private func liquidityCandidate(
        entry: TokenListEntry,
        chain: ChainProfile,
        spendAsset: TokenProfile,
        spendAmount: String,
        amountBaseUnits: String,
        walletAddress: String,
        referencePriceUSD: Double?
    ) async -> UniswapTokenCandidate {
        let id = "\(chain.chainID)-\(entry.address.lowercased())"
        if entry.address.lowercased() == spendAsset.address.lowercased() {
            let risk = Self.contractRisk(
                safetyLevel: entry.safetyLevel,
                isSpam: entry.isSpam,
                status: .noQuote,
                priceImpact: nil,
                routeSummary: nil,
                liquiditySummary: nil,
                rank: entry.rank,
                priceDeviationPercent: nil,
                quoteError: "候选代币和支付资产相同。",
                txFailureReasons: []
            )
            return UniswapTokenCandidate(
                id: id,
                chain: chain,
                name: entry.name,
                symbol: entry.symbol,
                address: entry.address,
                decimals: entry.decimals,
                safetyLevel: entry.safetyLevel,
                isSpam: entry.isSpam,
                rank: entry.rank,
                matchReason: entry.matchReason,
                status: .noQuote,
                riskLevel: risk.level,
                riskReasons: risk.reasons,
                outputAmount: nil,
                referencePriceUSD: referencePriceUSD,
                impliedPriceUSD: nil,
                priceDeviationPercent: nil,
                gasFeeUSD: nil,
                priceImpact: nil,
                routeSummary: nil,
                liquiditySummary: nil,
                quoteError: "候选代币和支付资产相同。",
                rawQuoteJSON: nil
            )
        }

        do {
            let quoteObject = try await requestQuote(
                tokenIn: spendAsset.address,
                tokenOut: entry.address,
                amountBaseUnits: amountBaseUnits,
                walletAddress: walletAddress,
                chain: chain,
                slippage: 1.0,
                routingPreference: "CLASSIC"
            )
            let quote = quoteObject["quote"] as? [String: Any] ?? [:]
            let outputBaseUnits = Self.extractOutputAmount(from: quoteObject)
            let inputAmountUSD = Self.stableInputAmountUSD(spendAmount: spendAmount, spendAsset: spendAsset)
            let impliedPriceUSD = Self.impliedPriceUSD(
                inputAmountUSD: inputAmountUSD,
                outputBaseUnits: outputBaseUnits,
                outputDecimals: entry.decimals
            )
            let priceDeviationPercent = Self.priceDeviationPercent(
                referencePriceUSD: referencePriceUSD,
                impliedPriceUSD: impliedPriceUSD
            )
            let priceImpact = Self.doubleValue(quote["priceImpact"])
            let routeSummary = quote["routeString"] as? String ?? Self.routeSummary(from: quote)
            let liquiditySummary = Self.liquiditySummary(from: quote)
            let txFailureReasons = JSONPrettyPrinter.array(quote["txFailureReasons"]).map { "\($0)" }
            let risk = Self.contractRisk(
                safetyLevel: entry.safetyLevel,
                isSpam: entry.isSpam,
                status: .quoted,
                priceImpact: priceImpact,
                routeSummary: routeSummary,
                liquiditySummary: liquiditySummary,
                rank: entry.rank,
                priceDeviationPercent: priceDeviationPercent,
                quoteError: nil,
                txFailureReasons: txFailureReasons
            )
            return UniswapTokenCandidate(
                id: id,
                chain: chain,
                name: entry.name,
                symbol: entry.symbol,
                address: entry.address,
                decimals: entry.decimals,
                safetyLevel: entry.safetyLevel,
                isSpam: entry.isSpam,
                rank: entry.rank,
                matchReason: entry.matchReason,
                status: .quoted,
                riskLevel: risk.level,
                riskReasons: risk.reasons,
                outputAmount: Self.humanAmount(
                    baseUnits: outputBaseUnits,
                    decimals: entry.decimals,
                    symbol: entry.symbol
                ),
                referencePriceUSD: referencePriceUSD,
                impliedPriceUSD: impliedPriceUSD,
                priceDeviationPercent: priceDeviationPercent,
                gasFeeUSD: Self.stringValue(quote["gasFeeUSD"]),
                priceImpact: priceImpact,
                routeSummary: routeSummary,
                liquiditySummary: liquiditySummary,
                quoteError: nil,
                rawQuoteJSON: JSONPrettyPrinter.prettyString(quoteObject)
            )
        } catch {
            let risk = Self.contractRisk(
                safetyLevel: entry.safetyLevel,
                isSpam: entry.isSpam,
                status: .noQuote,
                priceImpact: nil,
                routeSummary: nil,
                liquiditySummary: nil,
                rank: entry.rank,
                priceDeviationPercent: nil,
                quoteError: error.localizedDescription,
                txFailureReasons: []
            )
            return UniswapTokenCandidate(
                id: id,
                chain: chain,
                name: entry.name,
                symbol: entry.symbol,
                address: entry.address,
                decimals: entry.decimals,
                safetyLevel: entry.safetyLevel,
                isSpam: entry.isSpam,
                rank: entry.rank,
                matchReason: entry.matchReason,
                status: .noQuote,
                riskLevel: risk.level,
                riskReasons: risk.reasons,
                outputAmount: nil,
                referencePriceUSD: referencePriceUSD,
                impliedPriceUSD: nil,
                priceDeviationPercent: nil,
                gasFeeUSD: nil,
                priceImpact: nil,
                routeSummary: nil,
                liquiditySummary: nil,
                quoteError: error.localizedDescription,
                rawQuoteJSON: nil
            )
        }
    }

    func buildSwapPlan(
        draft: TradeIntentDraft,
        chain: ChainProfile,
        walletAddress: String
    ) async throws -> UniswapTradePlan {
        guard chain.supportsSwap else {
            throw UniswapTradeError.unsupportedChain(chain.displayName)
        }

        let trimmedWallet = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard QueryClassifier.isAddress(trimmedWallet) else {
            throw UniswapTradeError.invalidWallet
        }

        let outputToken = draft.tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard QueryClassifier.isAddress(outputToken) else {
            throw UniswapTradeError.invalidToken
        }

        let inputTokenAddress = draft.spendTokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNativeInput = inputTokenAddress.lowercased() == TokenProfile.nativeETH.address.lowercased()
        guard isNativeInput || QueryClassifier.isAddress(inputTokenAddress) else {
            throw UniswapTradeError.invalidSpendToken
        }

        let amountBaseUnits = try Self.baseUnits(
            amount: draft.spendAmount,
            decimals: draft.spendTokenDecimals
        )
        let inputToken = TokenProfile(
            symbol: draft.spendTokenSymbol.isEmpty ? "TOKEN" : draft.spendTokenSymbol,
            address: inputTokenAddress,
            decimals: draft.spendTokenDecimals
        )

        let approvalObject: [String: Any]
        if isNativeInput {
            approvalObject = [:]
        } else {
            approvalObject = try await post(
                endpoint: "check_approval",
                body: [
                    "walletAddress": trimmedWallet,
                    "token": inputTokenAddress,
                    "amount": amountBaseUnits,
                    "chainId": chain.chainID
                ],
                includeRouterVersion: false
            )
        }

        let quoteObject = try await requestQuote(
            tokenIn: inputTokenAddress,
            tokenOut: outputToken,
            amountBaseUnits: amountBaseUnits,
            walletAddress: trimmedWallet,
            chain: chain,
            slippage: draft.slippage,
            routingPreference: "BEST_PRICE"
        )

        let quote = quoteObject["quote"] as? [String: Any] ?? [:]
        let swapObject = try await post(
            endpoint: "swap",
            body: [
                "quote": quote,
                "refreshGasPrice": true,
                "simulateTransaction": false,
                "safetyMode": "SAFE"
            ],
            includeRouterVersion: true
        )

        let createdAt = Date()
        let approvalTransaction = EVMTransactionRequest(approvalObject["approval"])
        if let approvalTransaction {
            try approvalTransaction.validateForBroadcast(
                expectedFrom: trimmedWallet,
                expectedChainID: chain.chainID,
                requiresCalldata: true
            )
        }

        guard let swapTransaction = EVMTransactionRequest(swapObject["swap"]) else {
            throw UniswapTradeError.invalidTransaction("Uniswap 没有返回可签名的 swap 交易。")
        }
        try swapTransaction.validateForBroadcast(
            expectedFrom: trimmedWallet,
            expectedChainID: chain.chainID,
            requiresCalldata: true
        )

        let needsApproval = approvalTransaction?.hasCalldata == true
        let safetyChecks = [
            isNativeInput ? "原生 \(chain.nativeTokenSymbol) 输入已跳过授权检查。" : "已完成 ERC-20 授权检查。",
            "Swap calldata 已校验为非空十六进制。",
            "交易 from / to / chainId 已和本地钱包及当前链匹配。",
            needsApproval ? "需要先签名授权，授权上链后重新生成报价。" : "签名前仍需要输入钱包后 4 位确认。"
        ]

        return UniswapTradePlan(
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(UniswapTradePlan.quoteValiditySeconds),
            chain: chain,
            walletAddress: trimmedWallet,
            inputToken: inputToken,
            outputTokenAddress: outputToken,
            inputAmount: draft.spendAmount,
            inputAmountBaseUnits: amountBaseUnits,
            slippageTolerance: draft.slippage,
            approvalTransaction: approvalTransaction,
            approvalGasFee: approvalObject["gasFee"].map { "\($0)" },
            quoteRequestID: quoteObject["requestId"] as? String,
            routing: quoteObject["routing"] as? String ?? "CLASSIC",
            outputAmount: Self.extractOutputAmount(from: quoteObject),
            gasFee: swapObject["gasFee"].map { "\($0)" } ?? quoteObject["gasFee"].map { "\($0)" },
            swapTransaction: swapTransaction,
            safetyChecks: safetyChecks,
            rawQuoteJSON: JSONPrettyPrinter.prettyString(quoteObject) ?? "\(quoteObject)",
            rawSwapJSON: JSONPrettyPrinter.prettyString(swapObject)
        )
    }

    private func requestQuote(
        tokenIn: String,
        tokenOut: String,
        amountBaseUnits: String,
        walletAddress: String,
        chain: ChainProfile,
        slippage: Double,
        routingPreference: String
    ) async throws -> [String: Any] {
        try await post(
            endpoint: "quote",
            body: [
                "type": "EXACT_INPUT",
                "tokenIn": tokenIn,
                "tokenOut": tokenOut,
                "tokenInChainId": chain.chainID,
                "tokenOutChainId": chain.chainID,
                "amount": amountBaseUnits,
                "swapper": walletAddress,
                "slippageTolerance": slippage,
                "routingPreference": routingPreference,
                "protocols": ["V2", "V3", "V4"]
            ],
            includeRouterVersion: true
        )
    }

    private func post(
        endpoint: String,
        body: [String: Any],
        includeRouterVersion: Bool
    ) async throws -> [String: Any] {
        guard let apiKey = apiKeyOverride ?? CredentialStore.readUniswapAPIKey() else {
            throw UniswapTradeError.missingAPIKey
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("true", forHTTPHeaderField: "x-permit2-disabled")
        if includeRouterVersion {
            request.setValue("2.0", forHTTPHeaderField: "x-universal-router-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UniswapTradeError.invalidResponse
        }

        guard let object = JSONPrettyPrinter.parse(String(data: data, encoding: .utf8) ?? "") as? [String: Any] else {
            throw UniswapTradeError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                CredentialStore.clearUniswapAPIKey()
                throw UniswapTradeError.apiError("Uniswap API Key 无效，请重新保存。")
            }
            throw UniswapTradeError.apiError(Self.errorMessage(from: object) ?? "HTTP \(httpResponse.statusCode)")
        }

        return object
    }

    private static func baseUnits(amount: String, decimals: Int) throws -> String {
        let normalized = amount
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else {
            throw UniswapTradeError.invalidAmount
        }

        let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            throw UniswapTradeError.invalidAmount
        }

        let whole = String(pieces.first ?? "0")
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= decimals else {
            throw UniswapTradeError.invalidAmount
        }

        let paddedFraction = fraction + String(repeating: "0", count: decimals - fraction.count)
        let combined = (whole + paddedFraction).drop(while: { $0 == "0" })
        let value = combined.isEmpty ? "0" : String(combined)
        guard value != "0" else {
            throw UniswapTradeError.invalidAmount
        }
        return value
    }

    private static func matchRankAndReason(
        query: String,
        name: String,
        symbol: String
    ) -> (rank: Int, reason: String)? {
        let normalizedName = name.lowercased()
        let normalizedSymbol = symbol.lowercased()

        if normalizedSymbol == query {
            return (0, "符号完全匹配")
        }
        if normalizedName == query {
            return (1, "名称完全匹配")
        }
        if normalizedSymbol.hasPrefix(query) {
            return (2, "符号前缀匹配")
        }
        if normalizedName.hasPrefix(query) {
            return (3, "名称前缀匹配")
        }
        if normalizedSymbol.contains(query) {
            return (4, "符号包含匹配")
        }
        if normalizedName.contains(query) {
            return (5, "名称包含匹配")
        }

        return nil
    }

    private static func contractRisk(
        safetyLevel: String?,
        isSpam: Bool?,
        status: UniswapTokenCandidate.LiquidityStatus,
        priceImpact: Double?,
        routeSummary: String?,
        liquiditySummary: String?,
        rank: Int,
        priceDeviationPercent: Double?,
        quoteError: String?,
        txFailureReasons: [String]
    ) -> (level: ContractRiskLevel, reasons: [String]) {
        var level: ContractRiskLevel = .low
        var reasons: [String] = []

        func escalate(to newLevel: ContractRiskLevel) {
            if newLevel.rawValue > level.rawValue {
                level = newLevel
            }
        }

        if isSpam == true {
            return (.blocked, ["Uniswap 标记为 spam token。"])
        }

        switch safetyLevel?.uppercased() {
        case "VERIFIED":
            reasons.append("Uniswap safetyLevel 为 VERIFIED。")
        case "MEDIUM_WARNING":
            escalate(to: .medium)
            reasons.append("Uniswap safetyLevel 为 MEDIUM_WARNING。")
        case "STRONG_WARNING":
            escalate(to: .high)
            reasons.append("Uniswap safetyLevel 为 STRONG_WARNING。")
        case "BLOCKED":
            return (.blocked, ["Uniswap safetyLevel 为 BLOCKED。"])
        case .some(let value):
            escalate(to: .medium)
            reasons.append("Uniswap 返回未知 safetyLevel：\(value)。")
        case .none:
            escalate(to: .medium)
            reasons.append("Uniswap token list 未返回 safetyLevel。")
        }

        if isSpam == false {
            reasons.append("未被 Uniswap 标记为 spam。")
        } else if isSpam == nil {
            escalate(to: .medium)
            reasons.append("Uniswap token list 未返回 spam 标记。")
        }

        if status == .noQuote {
            escalate(to: .high)
            if let quoteError, !quoteError.isEmpty {
                reasons.append("当前金额没有可成交 quote：\(quoteError)")
            } else {
                reasons.append("当前金额没有可成交 quote。")
            }
        }

        if let priceImpact {
            if priceImpact >= 10 {
                escalate(to: .high)
                reasons.append("价格影响较高：\(String(format: "%.2f", priceImpact))%。")
            } else if priceImpact >= 3 {
                escalate(to: .medium)
                reasons.append("价格影响偏高：\(String(format: "%.2f", priceImpact))%。")
            } else {
                reasons.append("价格影响 \(String(format: "%.2f", priceImpact))%。")
            }
        } else if status == .quoted {
            escalate(to: .medium)
            reasons.append("Quote 未返回 priceImpact。")
        }

        if let priceDeviationPercent {
            if priceDeviationPercent >= 30 {
                escalate(to: .high)
                reasons.append("Uniswap 隐含价格偏离 Surf 参考价 \(String(format: "%.2f", priceDeviationPercent))%。")
            } else if priceDeviationPercent >= 10 {
                escalate(to: .medium)
                reasons.append("Uniswap 隐含价格偏离 Surf 参考价 \(String(format: "%.2f", priceDeviationPercent))%。")
            } else {
                reasons.append("Uniswap 隐含价格接近 Surf 参考价，偏离 \(String(format: "%.2f", priceDeviationPercent))%。")
            }
        }

        if status == .quoted {
            if routeSummary == nil {
                escalate(to: .medium)
                reasons.append("Quote 未返回可读路由。")
            }
            if liquiditySummary == nil {
                escalate(to: .medium)
                reasons.append("Quote 未返回池 liquidity/reserve 摘要。")
            }
        }

        if rank >= 4 {
            escalate(to: .high)
            reasons.append("名称/符号只是包含匹配，存在同名误选风险。")
        } else if rank >= 2 {
            escalate(to: .medium)
            reasons.append("名称/符号不是完全匹配。")
        }

        if !txFailureReasons.isEmpty {
            escalate(to: .high)
            reasons.append("Uniswap 模拟返回失败原因：\(txFailureReasons.prefix(2).joined(separator: "、"))。")
        }

        if reasons.isEmpty {
            reasons.append("基础检查未发现明显风险。")
        }

        return (level, reasons)
    }

    private static func extractOutputAmount(from object: [String: Any]) -> String? {
        guard let quote = object["quote"] as? [String: Any] else {
            return nil
        }

        if let orderInfo = quote["orderInfo"] as? [String: Any],
           let outputs = orderInfo["outputs"] as? [[String: Any]],
           let first = outputs.first {
            return first["startAmount"].map { "\($0)" } ?? first["endAmount"].map { "\($0)" }
        }

        if let outputs = quote["outputs"] as? [[String: Any]],
           let first = outputs.first {
            return first["amount"].map { "\($0)" } ?? first["endAmount"].map { "\($0)" }
        }

        if let output = quote["output"] as? [String: Any] {
            return output["amount"].map { "\($0)" }
        }

        return quote["outputAmount"].map { "\($0)" }
    }

    private static func stableInputAmountUSD(spendAmount: String, spendAsset: TokenProfile) -> Double? {
        let stableSymbols = ["USDC", "USDT", "DAI"]
        guard stableSymbols.contains(spendAsset.symbol.uppercased()) else {
            return nil
        }

        return Double(
            spendAmount
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        )
    }

    private static func impliedPriceUSD(
        inputAmountUSD: Double?,
        outputBaseUnits: String?,
        outputDecimals: Int
    ) -> Double? {
        guard let inputAmountUSD,
              inputAmountUSD > 0,
              let outputAmount = decimalTokenAmount(baseUnits: outputBaseUnits, decimals: outputDecimals),
              outputAmount > 0 else {
            return nil
        }

        return inputAmountUSD / outputAmount
    }

    private static func priceDeviationPercent(
        referencePriceUSD: Double?,
        impliedPriceUSD: Double?
    ) -> Double? {
        guard let referencePriceUSD,
              let impliedPriceUSD,
              referencePriceUSD > 0,
              impliedPriceUSD > 0 else {
            return nil
        }

        return abs(impliedPriceUSD - referencePriceUSD) / referencePriceUSD * 100
    }

    private static func decimalTokenAmount(baseUnits: String?, decimals: Int) -> Double? {
        guard let baseUnits,
              let rawValue = Double(baseUnits),
              rawValue > 0 else {
            return nil
        }

        let divisor = pow(10, Double(max(0, decimals)))
        guard divisor > 0 else {
            return nil
        }

        return rawValue / divisor
    }

    private static func routeSummary(from quote: [String: Any]) -> String? {
        let routes = JSONPrettyPrinter.array(quote["route"])
        let poolCount = routes.reduce(0) { count, item in
            count + JSONPrettyPrinter.array(item).count
        }
        guard poolCount > 0 else {
            return nil
        }

        return "\(poolCount) 个 Uniswap 池"
    }

    private static func liquiditySummary(from quote: [String: Any]) -> String? {
        let routes = JSONPrettyPrinter.array(quote["route"])
        var notes: [String] = []

        for route in routes {
            for poolItem in JSONPrettyPrinter.array(route) {
                guard let pool = poolItem as? [String: Any] else {
                    continue
                }

                let type = pool["type"] as? String ?? "pool"
                let address = JSONPrettyPrinter.shortAddress(pool["address"] as? String ?? "")
                if let liquidity = stringValue(pool["liquidity"]) {
                    notes.append("\(type) \(address) · L \(compactInteger(liquidity))")
                    continue
                }

                let reserves = [reserveSummary(pool["reserve0"]), reserveSummary(pool["reserve1"])]
                    .compactMap { $0 }
                if !reserves.isEmpty {
                    notes.append("\(type) \(address) · \(reserves.joined(separator: " / "))")
                }
            }
        }

        return notes.isEmpty ? nil : notes.prefix(3).joined(separator: "\n")
    }

    private static func reserveSummary(_ object: Any?) -> String? {
        guard let reserve = object as? [String: Any],
              let quotient = stringValue(reserve["quotient"]) else {
            return nil
        }

        let token = reserve["token"] as? [String: Any]
        let symbol = token?["symbol"] as? String ?? "token"
        let decimals = Int(token?["decimals"] as? String ?? "") ?? 18
        let amount = humanAmount(baseUnits: quotient, decimals: decimals, symbol: "") ?? compactInteger(quotient)
        return "\(symbol) \(amount)"
    }

    private static func humanAmount(
        baseUnits: String?,
        decimals: Int,
        symbol: String
    ) -> String? {
        guard let baseUnits else {
            return nil
        }

        let raw = baseUnits.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.allSatisfy(\.isNumber) else {
            return baseUnits
        }

        if decimals <= 0 {
            return symbol.isEmpty ? raw : "\(raw) \(symbol)"
        }

        let padded = raw.count <= decimals
            ? String(repeating: "0", count: decimals - raw.count + 1) + raw
            : raw
        let splitIndex = padded.index(padded.endIndex, offsetBy: -decimals)
        let whole = String(padded[..<splitIndex]).drop(while: { $0 == "0" })
        var fraction = String(padded[splitIndex...])
        fraction = String(fraction.prefix(8))
        while fraction.last == "0" {
            fraction.removeLast()
        }

        let wholeText = whole.isEmpty ? "0" : String(whole)
        let value = fraction.isEmpty ? wholeText : "\(wholeText).\(fraction)"
        return symbol.isEmpty ? value : "\(value) \(symbol)"
    }

    private static func compactInteger(_ value: String) -> String {
        let digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count > 12 else {
            return digits
        }

        let prefix = digits.prefix(4)
        let decimal = digits.dropFirst(4).prefix(2)
        return "\(prefix).\(decimal)e\(digits.count - 1)"
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return "\(number)"
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func errorMessage(from object: [String: Any]) -> String? {
        if let detail = object["detail"] as? String {
            return detail
        }
        if let message = object["message"] as? String {
            return message
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }
}

enum UniswapTradeError: LocalizedError {
    case missingAPIKey
    case invalidWallet
    case invalidToken
    case invalidSpendToken
    case invalidAmount
    case unsupportedChain(String)
    case invalidResponse
    case invalidTransaction(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "未设置 Uniswap API Key。请保存到 Keychain，或设置 CLIPMIND_UNISWAP_API_KEY / AGENTWALLET_UNISWAP_API_KEY / UNISWAP_API_KEY。"
        case .invalidWallet:
            "请先创建或导入一个有效的本地 EVM 钱包。"
        case .invalidToken:
            "目标代币地址不是有效的 EVM 地址。"
        case .invalidSpendToken:
            "支付资产地址不是有效的 EVM 地址。"
        case .invalidAmount:
            "交易金额格式无效，请输入大于 0 的数字。"
        case .unsupportedChain(let chain):
            "\(chain) 暂不支持 Uniswap swap。"
        case .invalidResponse:
            "Uniswap API 返回了无效响应。"
        case .invalidTransaction(let message):
            "Uniswap 交易校验失败：\(message)"
        case .apiError(let message):
            "Uniswap API 调用失败：\(message)"
        }
    }
}
