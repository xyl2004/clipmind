import AppKit
import BigInt
import Darwin
import Foundation

enum CoreSelfTests {
    static func run() async throws -> String {
        var suite = CoreSelfTestSuite()
        try testWalletIntentParser(&suite)
        try testStructuredIntentTypes(&suite)
        try testStructuredIntentAdapter(&suite)
        try await testIntentClassifierStub(&suite)
        try testIntentClassifierPrompt(&suite)
        try await testAppStoreIntentDispatch(&suite)
        try await testAppStoreCheckActions(&suite)
        try await testAppStoreIntentStatePreservation(&suite)
        try testTransferPlanBuilder(&suite)
        try testTransactionSafety(&suite)
        try testTradeIntentDraft(&suite)
        try testChainProfiles(&suite)
        try testWalletAssetsAndSurfParsing(&suite)
        try await testLocalWalletExport(&suite)
        return [
            "self_test_core=ok",
            "passed=\(suite.passed)"
        ].joined(separator: "\n")
    }

    private static func testWalletIntentParser(_ suite: inout CoreSelfTestSuite) throws {
        let recipient = "0x2222222222222222222222222222222222222222"
        let transfer = WalletIntentParser.parse(
            selectedText: recipient,
            question: "给这个地址转 5 USDC",
            chain: ChainRegistry.base
        )
        try suite.equal(transfer.action, WalletIntentAction.transfer, "transfer intent action")
        try suite.equal(transfer.recipientAddress, recipient, "transfer intent recipient")
        try suite.equal(transfer.spendAmount, "5", "transfer intent amount")
        try suite.equal(transfer.spendAsset.symbol, "USDC", "transfer intent asset")
        try suite.check(transfer.isComplete, "transfer intent complete")

        let swap = WalletIntentParser.parse(
            selectedText: "doge",
            question: "我想买5u这个代币",
            chain: ChainRegistry.base
        )
        try suite.equal(swap.action, WalletIntentAction.swap, "swap intent action")
        try suite.equal(swap.targetQuery, "doge", "swap intent target query")
        try suite.equal(swap.targetAddress, "", "swap intent has no premature address")
        try suite.equal(swap.spendAmount, "5", "swap intent amount")
        try suite.equal(swap.spendAsset.symbol, "USDC", "swap intent U means USDC")
        try suite.check(swap.isComplete, "swap intent complete with token name")

        try suite.equal(
            QueryClassifier.classify("$zec", preferredKind: .auto),
            QueryKind.project,
            "cashtag token symbol classified as project lookup"
        )
        let missingSwapAmount = WalletIntentParser.parse(
            selectedText: "$zec",
            question: "我能购买这个吗",
            chain: ChainRegistry.base
        )
        try suite.equal(missingSwapAmount.action, WalletIntentAction.swap, "cashtag swap intent action")
        try suite.equal(missingSwapAmount.targetQuery, "zec", "cashtag swap target normalized")
        try suite.check(missingSwapAmount.missingFields.contains("支付金额"), "cashtag swap asks for amount")

        let continuedSwap = WalletIntentParser.parse(
            selectedText: "$zec",
            question: "5u",
            chain: ChainRegistry.base,
            continuing: missingSwapAmount
        )
        try suite.equal(continuedSwap.action, WalletIntentAction.swap, "amount-only follow-up continues swap")
        try suite.equal(continuedSwap.targetQuery, "zec", "continued swap keeps target query")
        try suite.equal(continuedSwap.spendAmount, "5", "continued swap amount")
        try suite.equal(continuedSwap.spendAsset.symbol, "USDC", "continued swap U means USDC")
        try suite.check(continuedSwap.isComplete, "continued swap is complete")

        let missingAmount = WalletIntentParser.parse(
            selectedText: "",
            question: "转给 \(recipient)",
            chain: ChainRegistry.base
        )
        try suite.equal(missingAmount.action, WalletIntentAction.transfer, "transfer intent with inline address")
        try suite.equal(missingAmount.recipientAddress, recipient, "inline recipient extracted")
        try suite.check(missingAmount.missingFields.contains("转账金额"), "address digits are not parsed as amount")

        let ask = WalletIntentParser.parse(
            selectedText: "Uniswap",
            question: "这个项目是做什么的？",
            chain: ChainRegistry.base
        )
        try suite.equal(ask.action, WalletIntentAction.ask, "plain question stays ask")
        try suite.check(!ask.requiresConfirmation, "ask intent does not require confirmation")
    }

    private static func testStructuredIntentTypes(_ suite: inout CoreSelfTestSuite) throws {
        let transfer = StructuredIntent(
            action: .transfer,
            chain: "base",
            targetAddress: "0x2222222222222222222222222222222222222222",
            targetQuery: "",
            transactionHash: "",
            spendAssetSymbol: "USDC",
            spendAmount: "5",
            slippagePercent: nil,
            unsupportedReason: ""
        )
        try suite.equal(transfer.action, StructuredIntentAction.transfer, "structured intent transfer action")
        try suite.equal(transfer.chain, "base", "structured intent chain id")

        let ask = StructuredIntent.empty(action: .ask)
        try suite.equal(ask.action, StructuredIntentAction.ask, "structured intent ask via empty()")
        try suite.equal(ask.chain, nil, "structured intent ask has nil chain")
        try suite.equal(ask.targetAddress, "", "structured intent ask empty target_address")

        let allCases = StructuredIntentAction.allCases.map(\.rawValue).sorted()
        try suite.equal(
            allCases,
            ["ask", "check_address", "check_balance", "check_token", "check_tx", "swap", "transfer", "unsupported"].sorted(),
            "structured intent action vocabulary is exactly 8 values"
        )

        let validTransferJSON = """
        {"action":"transfer","chain":"base","target_address":"0x2222222222222222222222222222222222222222","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
        """
        let decodedTransfer = try StructuredIntent.decode(raw: validTransferJSON)
        try suite.equal(decodedTransfer.action, StructuredIntentAction.transfer, "decode transfer action")
        try suite.equal(decodedTransfer.targetAddress, "0x2222222222222222222222222222222222222222", "decode transfer target_address")
        try suite.equal(decodedTransfer.spendAmount, "5", "decode transfer spend_amount")
        try suite.equal(decodedTransfer.slippagePercent, nil, "decode transfer null slippage")

        let validSwapJSON = """
        {"action":"swap","chain":null,"target_address":"","target_query":"doge","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":1.0,"unsupported_reason":""}
        """
        let decodedSwap = try StructuredIntent.decode(raw: validSwapJSON)
        try suite.equal(decodedSwap.action, StructuredIntentAction.swap, "decode swap action")
        try suite.equal(decodedSwap.chain, nil, "decode swap null chain")
        try suite.equal(decodedSwap.targetQuery, "doge", "decode swap target_query")
        try suite.equal(decodedSwap.slippagePercent, 1.0, "decode swap slippage 1.0")

        let validCheckTxJSON = """
        {"action":"check_tx","chain":"ethereum","target_address":"","target_query":"","transaction_hash":"0xabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """
        let decodedCheckTx = try StructuredIntent.decode(raw: validCheckTxJSON)
        try suite.equal(decodedCheckTx.action, StructuredIntentAction.checkTx, "decode check_tx action")
        try suite.equal(decodedCheckTx.transactionHash.count, 66, "decode check_tx hash length")

        let wrapped = """
        Sure, here is the JSON:
        ```json
        {"action":"ask","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        ```
        Hope this helps.
        """
        let decodedWrapped = try StructuredIntent.decode(raw: wrapped)
        try suite.equal(decodedWrapped.action, StructuredIntentAction.ask, "decode strips markdown wrapper")

        let trailingText = """
        {"action":"unsupported","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":"Bridge 暂未支持"}
        用户希望跨链。
        """
        let decodedTrailing = try StructuredIntent.decode(raw: trailingText)
        try suite.equal(decodedTrailing.action, StructuredIntentAction.unsupported, "decode strips trailing prose")
        try suite.equal(decodedTrailing.unsupportedReason, "Bridge 暂未支持", "decode keeps unsupported_reason")

        try suite.expectThrows("decode rejects unknown action") {
            _ = try StructuredIntent.decode(raw: """
            {"action":"buy_nft","chain":"base","target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
            """)
        }

        try suite.expectThrows("decode rejects bad target_address hex") {
            _ = try StructuredIntent.decode(raw: """
            {"action":"transfer","chain":"base","target_address":"0xnotvalid","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
            """)
        }

        try suite.expectThrows("decode rejects bad transaction_hash") {
            _ = try StructuredIntent.decode(raw: """
            {"action":"check_tx","chain":"base","target_address":"","target_query":"","transaction_hash":"0xtoolittle","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
            """)
        }

        try suite.expectThrows("decode rejects unknown chain") {
            _ = try StructuredIntent.decode(raw: """
            {"action":"swap","chain":"solana","target_address":"","target_query":"doge","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
            """)
        }

        try suite.expectThrows("decode rejects truly broken JSON") {
            _ = try StructuredIntent.decode(raw: "not json at all")
        }
    }

    private static func testStructuredIntentAdapter(_ suite: inout CoreSelfTestSuite) throws {
        let transferIntent = StructuredIntent(
            action: .transfer,
            chain: "base",
            targetAddress: "0x2222222222222222222222222222222222222222",
            targetQuery: "",
            transactionHash: "",
            spendAssetSymbol: "USDC",
            spendAmount: "5",
            slippagePercent: nil,
            unsupportedReason: ""
        )
        let transferDraft = transferIntent.toWalletIntentDraft(
            selectedContext: "0x2222222222222222222222222222222222222222",
            fallbackChain: ChainRegistry.ethereum
        )
        try suite.equal(transferDraft?.action, WalletIntentAction.transfer, "adapter transfer action")
        try suite.equal(
            transferDraft?.recipientAddress,
            "0x2222222222222222222222222222222222222222",
            "adapter transfer recipient"
        )
        try suite.equal(transferDraft?.spendAmount, "5", "adapter transfer amount")
        try suite.equal(transferDraft?.spendAsset.symbol, "USDC", "adapter transfer asset")
        try suite.equal(transferDraft?.chain.id, "base", "adapter transfer chain follows intent")
        try suite.check(transferDraft?.isComplete == true, "adapter transfer complete")

        let swapIntent = StructuredIntent(
            action: .swap,
            chain: nil,
            targetAddress: "",
            targetQuery: "doge",
            transactionHash: "",
            spendAssetSymbol: "USDC",
            spendAmount: "5",
            slippagePercent: 1.0,
            unsupportedReason: ""
        )
        let swapDraft = swapIntent.toWalletIntentDraft(selectedContext: "doge", fallbackChain: ChainRegistry.base)
        try suite.equal(swapDraft?.action, WalletIntentAction.swap, "adapter swap action")
        try suite.equal(swapDraft?.targetQuery, "doge", "adapter swap target_query")
        try suite.equal(swapDraft?.targetAddress, "", "adapter swap no premature address")
        try suite.equal(swapDraft?.chain.id, "base", "adapter swap chain falls back when null")
        try suite.equal(swapDraft?.slippage, 1.0, "adapter swap slippage explicit")

        let swapMissingAmount = StructuredIntent(
            action: .swap,
            chain: "base",
            targetAddress: "",
            targetQuery: "doge",
            transactionHash: "",
            spendAssetSymbol: "USDC",
            spendAmount: "",
            slippagePercent: nil,
            unsupportedReason: ""
        )
        let missingDraft = swapMissingAmount.toWalletIntentDraft(selectedContext: "doge", fallbackChain: ChainRegistry.base)
        try suite.check(missingDraft?.missingFields.contains("支付金额") == true, "adapter recomputes missing amount")

        let ask = StructuredIntent.empty(action: .ask)
        try suite.equal(
            ask.toWalletIntentDraft(selectedContext: "Uniswap", fallbackChain: ChainRegistry.base) == nil,
            true,
            "adapter returns nil for ask"
        )

        for action in [
            StructuredIntentAction.checkBalance,
            .checkToken,
            .checkTx,
            .checkAddress,
            .unsupported
        ] {
            try suite.equal(
                StructuredIntent.empty(action: action)
                    .toWalletIntentDraft(selectedContext: "", fallbackChain: ChainRegistry.base) == nil,
                true,
                "adapter returns nil for \(action.rawValue)"
            )
        }
    }

    private static func testIntentClassifierStub(_ suite: inout CoreSelfTestSuite) async throws {
        let goodJSON = """
        {"action":"transfer","chain":"base","target_address":"0x2222222222222222222222222222222222222222","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
        """
        let stub = StubIntentClassifierBackend(responses: [.success(goodJSON)])
        let classifier = IntentClassifier(backend: stub)

        let result = try await classifier.classify(
            selectedContext: "0x2222222222222222222222222222222222222222",
            previousIntent: nil,
            chainHint: "base",
            question: "给这个地址转 5 USDC"
        )
        try suite.equal(result.action, StructuredIntentAction.transfer, "classifier returns parsed intent")
        try suite.equal(stub.callCount, 1, "classifier called backend exactly once on happy path")

        let badThenGood = StubIntentClassifierBackend(responses: [
            .success("not json at all"),
            .success("""
            {"action":"swap","chain":"base","target_address":"","target_query":"doge","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":1.0,"unsupported_reason":""}
            """)
        ])
        let retryClassifier = IntentClassifier(backend: badThenGood)
        let retried = try await retryClassifier.classify(
            selectedContext: "doge",
            previousIntent: nil,
            chainHint: "base",
            question: "我想买 5u 这个代币"
        )
        try suite.equal(retried.action, StructuredIntentAction.swap, "classifier retries once on bad JSON")
        try suite.equal(badThenGood.callCount, 2, "classifier called backend twice on retry path")
        try suite.check(
            badThenGood.lastUsers.last?.contains("Your previous output was rejected") == true,
            "retry payload includes rejection feedback"
        )

        let alwaysBad = StubIntentClassifierBackend(responses: [
            .success("not json"),
            .success("still not json")
        ])
        let exhaustClassifier = IntentClassifier(backend: alwaysBad)
        var thrown: Error?
        do {
            _ = try await exhaustClassifier.classify(
                selectedContext: "anything",
                previousIntent: nil,
                chainHint: "base",
                question: "?"
            )
        } catch {
            thrown = error
        }
        try suite.check(thrown is IntentClassifierError, "classifier throws IntentClassifierError after retry exhausted")
        try suite.equal(alwaysBad.callCount, 2, "classifier stops at one retry (two calls total)")
    }

    private static func testIntentClassifierPrompt(_ suite: inout CoreSelfTestSuite) throws {
        let prompt = IntentClassifierPrompt()
        try suite.check(prompt.systemPrompt.contains("check_balance"), "system prompt lists check_balance")
        try suite.check(prompt.systemPrompt.contains("check_address"), "system prompt lists check_address")
        try suite.check(prompt.systemPrompt.contains("unichain"), "system prompt lists unichain")
        try suite.check(prompt.systemPrompt.contains("ethereum"), "system prompt lists ethereum")

        let firstTurn = prompt.buildUserPayload(
            selectedContext: "doge",
            previousIntent: nil,
            chainHint: "base",
            question: "我想买 5u 这个代币"
        )
        try suite.check(firstTurn.contains("[selected_context]"), "user payload includes selected_context block")
        try suite.check(firstTurn.contains("[user_question]"), "user payload includes user_question block")
        try suite.check(!firstTurn.contains("[previous_intent]"), "first turn omits previous_intent block entirely")

        let priorDraft = WalletIntentParser.parse(
            selectedText: "doge",
            question: "我想买这个币",
            chain: ChainRegistry.base
        )
        let secondTurn = prompt.buildUserPayload(
            selectedContext: "doge",
            previousIntent: priorDraft,
            chainHint: "base",
            question: "5u"
        )
        try suite.check(secondTurn.contains("[previous_intent]"), "continuation turn includes previous_intent block")
        try suite.check(secondTurn.contains("\"action\":\"swap\""), "previous_intent block serializes prior action")

        let longContext = String(repeating: "中", count: 2000)
        let truncated = prompt.buildUserPayload(
            selectedContext: longContext,
            previousIntent: nil,
            chainHint: "base",
            question: "?"
        )
        try suite.check(truncated.count < longContext.count, "user payload truncates oversized selected context")
    }

    @MainActor
    private static func testAppStoreIntentDispatch(_ suite: inout CoreSelfTestSuite) async throws {
        let swapJSON = """
        {"action":"swap","chain":"base","target_address":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
        """
        let stub = StubIntentClassifierBackend(responses: [.success(swapJSON)])
        let store = AppStore(
            intentClassifier: IntentClassifier(backend: stub),
            intentBackendMode: .auto
        )
        store.input = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
        store.chatQuestion = "用 5u 买这个"
        await store.askAboutSelectedContext()
        try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "stub swap intent applied to store")
        try suite.equal(stub.callCount, 1, "store calls classifier once")

        let failingStub = StubIntentClassifierBackend(responses: [
            .success("not json"),
            .success("still not json")
        ])
        let store2 = AppStore(
            intentClassifier: IntentClassifier(backend: failingStub),
            intentBackendMode: .auto
        )
        store2.input = "0x2222222222222222222222222222222222222222"
        store2.chatQuestion = "给这个地址转 5 USDC"
        await store2.askAboutSelectedContext()
        try suite.equal(store2.floatingWalletIntent?.action, WalletIntentAction.transfer, "rules fallback produced transfer intent")
        try suite.equal(store2.floatingWalletIntent?.spendAmount, "5", "rules fallback parsed amount")

        let unusedStub = StubIntentClassifierBackend(responses: [])
        let store3 = AppStore(
            intentClassifier: IntentClassifier(backend: unusedStub),
            intentBackendMode: .rule
        )
        store3.input = "0x2222222222222222222222222222222222222222"
        store3.chatQuestion = "给这个地址转 5 USDC"
        await store3.askAboutSelectedContext()
        try suite.equal(unusedStub.callCount, 0, "rule mode skips LLM classifier")
        try suite.equal(store3.floatingWalletIntent?.action, WalletIntentAction.transfer, "rule mode still produces intent via parser")

        let zecMissingAmountJSON = """
        {"action":"swap","chain":null,"target_address":"","target_query":"zec","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """
        let zecTradeProvider = StubTradeProvider(tokenCandidates: [])
        let zecStore = AppStore(
            surfClient: StubSurfProvider(priceAnchor: zecPriceAnchor()),
            tradeProvider: zecTradeProvider,
            intentClassifier: IntentClassifier(backend: StubIntentClassifierBackend(responses: [.success(zecMissingAmountJSON)])),
            intentBackendMode: .auto
        )
        zecStore.input = "$zec"
        zecStore.chatQuestion = "我能购买这个代币吗"
        await zecStore.askAboutSelectedContext()
        try suite.equal(
            zecTradeProvider.candidateRequests.count,
            ChainRegistry.supported.filter(\.supportsSwap).count,
            "missing-amount swap still probes Uniswap chains"
        )
        try suite.equal(zecTradeProvider.candidateRequests.first?.query, "zec", "zec preflight probes normalized token query")
        try suite.equal(zecTradeProvider.candidateRequests.first?.spendAmount, "1", "zec preflight uses one USDC probe amount")
        try suite.equal(zecStore.swapPriceAnchor?.symbol, "ZEC", "zec preflight stores Surf price anchor")
        try suite.check(
            zecStore.floatingWalletIntent?.missingFields.contains("支付金额") == true,
            "zec preflight still asks user for payment amount"
        )
        try suite.check(
            zecStore.floatingWalletActionErrorMessage?.contains("Uniswap token list") == true,
            "zec preflight keeps Uniswap no-candidate message visible"
        )
    }

    @MainActor
    private static func testAppStoreCheckActions(_ suite: inout CoreSelfTestSuite) async throws {
        let isolatedClient = isolatedWalletClient()
        defer { try? isolatedClient.deleteWallet() }

        let balanceJSON = """
        {"action":"check_balance","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """
        let store = AppStore(
            localWalletClient: isolatedClient,
            intentClassifier: IntentClassifier(backend: StubIntentClassifierBackend(responses: [.success(balanceJSON)])),
            intentBackendMode: .auto
        )
        store.input = "余额"
        store.chatQuestion = "查一下我的钱包余额"
        await store.askAboutSelectedContext()
        try suite.check(
            store.chatMessages.last?.text.contains("还没有本地钱包") == true,
            "check_balance no-wallet shows specific guidance message"
        )

        let degradeJSON = """
        {"action":"check_address","chain":null,"target_address":"","target_query":"uniswap","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """
        let store2 = AppStore(
            intentClassifier: IntentClassifier(backend: StubIntentClassifierBackend(responses: [.success(degradeJSON)])),
            intentBackendMode: .auto
        )
        store2.input = "uniswap"
        store2.chatQuestion = "这个项目什么风险"
        await store2.askAboutSelectedContext()
        try suite.equal(store2.errorMessage, nil, "check_address degraded path does not set errorMessage")

        let askyTxJSON = """
        {"action":"check_tx","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """
        let store3 = AppStore(
            intentClassifier: IntentClassifier(backend: StubIntentClassifierBackend(responses: [.success(askyTxJSON)])),
            intentBackendMode: .auto
        )
        store3.input = "随便"
        store3.chatQuestion = "这笔交易怎么样"
        await store3.askAboutSelectedContext()
        try suite.equal(store3.errorMessage, nil, "check_tx degraded path does not set errorMessage")
    }

    @MainActor
    private static func testAppStoreIntentStatePreservation(_ suite: inout CoreSelfTestSuite) async throws {
        let swapJSON = """
        {"action":"swap","chain":"base","target_address":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","target_query":"","transaction_hash":"","spend_asset_symbol":"USDC","spend_amount":"5","slippage_percent":null,"unsupported_reason":""}
        """
        let askJSON = """
        {"action":"ask","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":""}
        """
        let unsupportedJSON = """
        {"action":"unsupported","chain":null,"target_address":"","target_query":"","transaction_hash":"","spend_asset_symbol":"","spend_amount":"","slippage_percent":null,"unsupported_reason":"NFT mint 暂未支持"}
        """
        let stub = StubIntentClassifierBackend(responses: [
            .success(swapJSON),
            .success(askJSON),
            .success(unsupportedJSON)
        ])
        let store = AppStore(
            intentClassifier: IntentClassifier(backend: stub),
            intentBackendMode: .auto
        )
        store.input = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
        store.chatQuestion = "用 5u 买这个"
        await store.askAboutSelectedContext()
        try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "initial swap intent set")
        let swapID = store.floatingWalletIntent?.id

        store.chatQuestion = "这个币背景是什么"
        await store.askAboutSelectedContext()
        try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "ask preserves swap intent")
        try suite.equal(store.floatingWalletIntent?.id, swapID, "swap intent identity unchanged after ask")

        store.chatQuestion = "我也想 mint 一个 NFT 给这个地址"
        await store.askAboutSelectedContext()
        try suite.equal(store.floatingWalletIntent?.action, WalletIntentAction.swap, "unsupported preserves swap intent")
        try suite.equal(store.floatingWalletIntent?.id, swapID, "swap intent identity unchanged after unsupported")
    }

    private static func testTransferPlanBuilder(_ suite: inout CoreSelfTestSuite) throws {
        let wallet = LocalWalletAccount(
            address: "0x1111111111111111111111111111111111111111",
            createdAt: Date()
        )
        let recipient = "0x2222222222222222222222222222222222222222"

        let erc20Intent = WalletIntentDraft(
            action: .transfer,
            selectedContext: recipient,
            targetAddress: recipient,
            targetQuery: "",
            chain: ChainRegistry.base,
            spendAsset: ChainRegistry.base.defaultSpendToken,
            spendAmount: "1.5",
            recipientAddress: recipient,
            slippage: 0,
            missingFields: [],
            riskNotes: [],
            confirmationSummary: ""
        )
        let erc20Plan = try TransferPlanBuilder.build(intent: erc20Intent, account: wallet)
        try suite.equal(erc20Plan.amountBaseUnits, "1500000", "erc20 base units")
        try suite.check(erc20Plan.requiresCalldata, "erc20 transfer requires calldata")
        try suite.equal(erc20Plan.transaction.to, ChainRegistry.base.defaultSpendToken.address, "erc20 transfer target")
        try suite.equal(erc20Plan.transaction.value, "0", "erc20 transfer zero native value")
        try suite.check(erc20Plan.transaction.data?.hasPrefix("0xa9059cbb") == true, "erc20 transfer calldata selector")
        try suite.equal(erc20Plan.confirmationCode, "2222", "transfer confirmation code")

        let nativeIntent = WalletIntentDraft(
            action: .transfer,
            selectedContext: recipient,
            targetAddress: recipient,
            targetQuery: "",
            chain: ChainRegistry.base,
            spendAsset: TokenProfile.nativeETH,
            spendAmount: "0.01",
            recipientAddress: recipient,
            slippage: 0,
            missingFields: [],
            riskNotes: [],
            confirmationSummary: ""
        )
        let nativePlan = try TransferPlanBuilder.build(intent: nativeIntent, account: wallet)
        try suite.equal(nativePlan.amountBaseUnits, "10000000000000000", "native transfer base units")
        try suite.check(!nativePlan.requiresCalldata, "native transfer no calldata")
        try suite.equal(nativePlan.transaction.to, recipient, "native transfer target")
        try suite.equal(nativePlan.transaction.value, "10000000000000000", "native transfer value")

        try suite.expectThrows("zero token amount rejected") {
            _ = try TokenAmountParser.baseUnits(amount: "0", decimals: 6)
        }
        try suite.expectThrows("too many fraction digits rejected") {
            _ = try TokenAmountParser.baseUnits(amount: "1.1234567", decimals: 6)
        }
        try suite.equal(
            try TokenAmountParser.baseUnits(amount: "1.234567", decimals: 6),
            "1234567",
            "valid token amount parsed"
        )
    }

    private static func testTransactionSafety(_ suite: inout CoreSelfTestSuite) throws {
        let wallet = "0x1111111111111111111111111111111111111111"
        let target = "0x2222222222222222222222222222222222222222"
        let valid = EVMTransactionRequest(
            to: target,
            from: wallet,
            data: "0x1234abcd",
            value: "0",
            gasLimit: "21000",
            chainID: ChainRegistry.base.chainID,
            maxFeePerGas: nil,
            maxPriorityFeePerGas: nil,
            gasPrice: nil
        )
        try valid.validateForBroadcast(
            expectedFrom: wallet,
            expectedChainID: ChainRegistry.base.chainID,
            requiresCalldata: true
        )
        suite.pass("valid transaction passes broadcast validation")

        let wrongSender = EVMTransactionRequest(
            to: target,
            from: "0x3333333333333333333333333333333333333333",
            data: "0x1234abcd",
            value: "0",
            gasLimit: nil,
            chainID: ChainRegistry.base.chainID,
            maxFeePerGas: nil,
            maxPriorityFeePerGas: nil,
            gasPrice: nil
        )
        try suite.expectThrows("wrong sender rejected") {
            try wrongSender.validateForBroadcast(
                expectedFrom: wallet,
                expectedChainID: ChainRegistry.base.chainID,
                requiresCalldata: true
            )
        }

        let missingCalldata = EVMTransactionRequest(
            to: target,
            from: wallet,
            data: "0x",
            value: "0",
            gasLimit: nil,
            chainID: ChainRegistry.base.chainID,
            maxFeePerGas: nil,
            maxPriorityFeePerGas: nil,
            gasPrice: nil
        )
        try suite.expectThrows("missing calldata rejected") {
            try missingCalldata.validateForBroadcast(
                expectedFrom: wallet,
                expectedChainID: ChainRegistry.base.chainID,
                requiresCalldata: true
            )
        }

        let parsed = EVMTransactionRequest([
            "to": target,
            "from": wallet,
            "data": "0xabcdef",
            "value": 0,
            "gasLimit": "21000",
            "chainId": NSNumber(value: ChainRegistry.base.chainID)
        ])
        try suite.equal(parsed?.chainID, ChainRegistry.base.chainID, "transaction dictionary chain id")
        try suite.equal(parsed?.value, "0", "transaction dictionary value")
    }

    private static func testTradeIntentDraft(_ suite: inout CoreSelfTestSuite) throws {
        var draft = TradeIntentDraft()
        draft.spendAmount = "5"
        draft.spendTokenAddress = ChainRegistry.base.defaultSpendToken.address
        draft.tokenAddress = "0x2222222222222222222222222222222222222222"
        try suite.check(draft.canBuildSwapPlan, "swap draft accepts valid target")

        draft.tokenAddress = "doge"
        try suite.check(!draft.canBuildSwapPlan, "swap draft rejects token name before resolution")

        draft.tokenAddress = "0x2222222222222222222222222222222222222222"
        draft.spendAmount = "   "
        try suite.check(!draft.canBuildSwapPlan, "swap draft rejects empty amount")

        draft.spendAmount = "5"
        draft.recipientAddress = "0x2222222222222222222222222222222222222222"
        try suite.check(draft.canBuildTransferPlan, "transfer draft accepts valid recipient")

        draft.applyDefaultSpendToken(for: ChainRegistry.ethereumSepolia)
        try suite.equal(draft.spendTokenSymbol, "ETH", "default spend token symbol")
        try suite.equal(draft.spendTokenAddress, TokenProfile.nativeETH.address, "default spend token address")
        try suite.equal(draft.spendTokenDecimals, 18, "default spend token decimals")
    }

    private static func testChainProfiles(_ suite: inout CoreSelfTestSuite) throws {
        try suite.equal(
            ChainRegistry.supported.map(\.id),
            ["ethereum", "base", "arbitrum", "optimism", "polygon", "unichain"],
            "supported chain list"
        )
        try suite.equal(ChainRegistry.profile(for: "unichain"), ChainRegistry.unichain, "unichain supported")
        try suite.equal(ChainRegistry.unichain.defaultSpendToken.symbol, "USDC", "unichain default spend token symbol")
        try suite.equal(
            ChainRegistry.unichain.defaultSpendToken.address,
            "0x078D782b760474a361dDA0AF3839290b0EF57AD6",
            "unichain USDC address"
        )
        try suite.equal(
            ChainFilter.all.map(\.id),
            ["auto", "ethereum", "base", "arbitrum", "optimism", "polygon", "unichain"],
            "chain filters match supported chains"
        )

        try withEnvironment(
            [
                "CLIPMIND_RPC_BASE": "https://clipmind.example/rpc",
                "AGENTWALLET_RPC_BASE": "https://legacy.example/rpc"
            ]
        ) {
            try suite.equal(
                ChainRegistry.base.rpcURL?.absoluteString,
                "https://clipmind.example/rpc",
                "clipmind rpc env takes priority"
            )
        }

        try withEnvironment(
            [
                "CLIPMIND_RPC_BASE": nil,
                "AGENTWALLET_RPC_BASE": "https://legacy.example/rpc"
            ]
        ) {
            try suite.equal(
                ChainRegistry.base.rpcURL?.absoluteString,
                "https://legacy.example/rpc",
                "legacy rpc env fallback"
            )
        }
    }

    private static func testWalletAssetsAndSurfParsing(_ suite: inout CoreSelfTestSuite) throws {
        let token = WalletTokenBalance(
            symbol: "USDC",
            name: "USD Coin",
            balance: "10",
            usdValue: "$10.00",
            address: "0x2222222222222222222222222222222222222222"
        )
        try suite.equal(token.displayName, "USDC · USD Coin", "wallet token display name")

        let balance = LocalWalletBalance(
            chain: ChainRegistry.base,
            balanceWei: BigUInt("1234567000000000000"),
            updatedAt: Date()
        )
        try suite.equal(balance.formattedNativeBalance, "1.234567 ETH", "native balance formatting")

        let assets = WalletChainAssets(
            chain: ChainRegistry.base,
            gasBalance: nil,
            gasErrorMessage: nil,
            tokens: [WalletTokenBalance(symbol: "USDC", name: nil, balance: "2", usdValue: "$2.00", address: nil)],
            totalUSD: "$2.00",
            tokenErrorMessage: nil,
            updatedAt: Date()
        )
        try suite.equal(assets.gasText, "未刷新", "wallet assets unrefreshed gas")
        try suite.equal(assets.assetSummary, "1 个代币 · $2.00", "wallet assets summary")

        let result = SurfCommandResult(
            operation: SurfOperation(command: "wallet-detail", arguments: [], title: "Base 钱包资产", chain: ChainRegistry.base),
            stdout: "",
            stderr: "",
            exitCode: 0,
            jsonObject: [
                "data": [
                    "evm_balance": ["total_usd": 12.34],
                    "evm_tokens": [
                        [
                            "symbol": "USDC",
                            "name": "USD Coin",
                            "balance": "12.34",
                            "usd_value": 12.34,
                            "token_address": "0x2222222222222222222222222222222222222222"
                        ]
                    ]
                ]
            ]
        )
        let parsedAssets = SurfClient.walletChainTokenAssets(from: result)
        try suite.equal(parsedAssets.chain, ChainRegistry.base, "surf wallet asset chain")
        try suite.equal(parsedAssets.tokens.count, 1, "surf token count")
        try suite.equal(parsedAssets.tokens[0].symbol, "USDC", "surf token symbol")
        try suite.equal(parsedAssets.tokens[0].name, "USD Coin", "surf token name")
        try suite.equal(parsedAssets.tokens[0].balance, "12.34", "surf token balance")
        try suite.equal(
            parsedAssets.tokens[0].address,
            "0x2222222222222222222222222222222222222222",
            "surf token address"
        )
        try suite.check(parsedAssets.totalUSD != nil, "surf total usd formatted")

        let priceAnchorResult = SurfCommandResult(
            operation: SurfOperation(command: "market-price", arguments: [], title: "ZEC Surf 价格", chain: nil),
            stdout: "",
            stderr: "",
            exitCode: 0,
            jsonObject: [
                "symbol": "ZEC",
                "summary": [
                    "last": 350.85,
                    "latest_dt": 1_780_640_700,
                    "change_pct": -41.99,
                    "high": 604.91,
                    "low": 350.85
                ]
            ]
        )
        let priceAnchor = TokenPriceAnchor(result: priceAnchorResult, fallbackSymbol: "ZEC")
        try suite.equal(priceAnchor?.symbol, "ZEC", "surf market price symbol")
        try suite.equal(priceAnchor?.priceUSD, 350.85, "surf market latest price")
        try suite.equal(priceAnchor?.latestTimestamp, 1_780_640_700, "surf market latest timestamp")

        let failedResult = SurfCommandResult(
            operation: SurfOperation(command: "wallet-detail", arguments: [], title: "", chain: ChainRegistry.base),
            stdout: "",
            stderr: "validation failed",
            exitCode: 1,
            jsonObject: nil
        )
        let failedAssets = SurfClient.walletChainTokenAssets(from: failedResult)
        try suite.equal(failedAssets.tokens.count, 0, "surf failed asset token count")
        try suite.equal(failedAssets.errorMessage, "validation failed", "surf failed asset error")
    }

    private static func testLocalWalletExport(_ suite: inout CoreSelfTestSuite) async throws {
        let privateKey = "0x1111111111111111111111111111111111111111111111111111111111111111"
        let client = isolatedWalletClient()
        defer { try? client.deleteWallet() }

        _ = try client.importWallet(privateKeyHex: privateKey)
        try suite.equal(try client.exportPrivateKeyHex(), privateKey, "local wallet exported private key")
        try suite.expectThrows("local wallet prevents overwrite") {
            _ = try client.importWallet(privateKeyHex: privateKey)
        }
        try client.deleteWallet()

        let observations = await MainActor.run {
            let store = AppStore(localWalletClient: client)
            store.privateKeyDraft = privateKey
            store.importLocalWallet()
            let imported = store.localWalletAccount != nil

            store.revealLocalWalletPrivateKey()
            let revealedPrivateKey = store.exportedPrivateKey

            let pasteboard = NSPasteboard.general
            let originalClipboard = pasteboard.string(forType: .string)
            store.copyExportedPrivateKeyAndHide()
            let hiddenAfterCopy = store.exportedPrivateKey == nil
            let copiedPrivateKey = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            if let originalClipboard {
                pasteboard.setString(originalClipboard, forType: .string)
            }

            store.revealLocalWalletPrivateKey()
            let shownBeforeDelete = store.exportedPrivateKey != nil
            store.deleteLocalWallet()
            return (
                imported: imported,
                revealedPrivateKey: revealedPrivateKey,
                hiddenAfterCopy: hiddenAfterCopy,
                copiedPrivateKey: copiedPrivateKey,
                shownBeforeDelete: shownBeforeDelete,
                accountCleared: store.localWalletAccount == nil,
                exportClearedAfterDelete: store.exportedPrivateKey == nil
            )
        }

        try suite.check(observations.imported, "app store imported test wallet")
        try suite.equal(observations.revealedPrivateKey, privateKey, "app store reveals exported private key")
        try suite.check(observations.hiddenAfterCopy, "copy hides exported private key")
        try suite.equal(observations.copiedPrivateKey, privateKey, "copy writes private key to pasteboard")
        try suite.check(observations.shownBeforeDelete, "private key shown before delete")
        try suite.check(observations.accountCleared, "delete clears wallet account")
        try suite.check(observations.exportClearedAfterDelete, "delete clears exported private key")
    }

    private static func isolatedWalletClient() -> LocalWalletClient {
        let suffix = UUID().uuidString
        return LocalWalletClient(
            service: "ClipMindTests.LocalPrivateKey.\(suffix)",
            addressService: "ClipMindTests.LocalWalletAddress.\(suffix)",
            account: "test"
        )
    }

    private static func zecPriceAnchor() -> TokenPriceAnchor {
        TokenPriceAnchor(
            result: SurfCommandResult(
                operation: SurfOperation(command: "market-price", arguments: [], title: "ZEC Surf 价格", chain: nil),
                stdout: "",
                stderr: "",
                exitCode: 0,
                jsonObject: [
                    "symbol": "ZEC",
                    "summary": [
                        "last": 350.85,
                        "latest_dt": 1_780_640_700,
                        "change_pct": -41.99,
                        "high": 604.91,
                        "low": 350.85
                    ]
                ]
            ),
            fallbackSymbol: "ZEC"
        )!
    }

    private static func withEnvironment(_ values: [String: String?], run body: () throws -> Void) rethrows {
        let originalValues = Dictionary(uniqueKeysWithValues: values.keys.map { key in
            (key, getenv(key).map { String(cString: $0) })
        })

        defer {
            for (key, value) in originalValues {
                if let value {
                    setenv(key, value, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        for (key, value) in values {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }

        try body()
    }
}

private actor StubSurfProvider: SurfProviding {
    private let priceAnchor: TokenPriceAnchor?

    init(priceAnchor: TokenPriceAnchor? = nil) {
        self.priceAnchor = priceAnchor
    }

    func research(query: String, kind: QueryKind, chainFilter: ChainFilter) async throws -> ResearchSnapshot {
        throw StubProviderError.unused
    }

    func walletTokenAssets(address: String, chains: [ChainProfile]) async throws -> [WalletChainTokenAssets] {
        throw StubProviderError.unused
    }

    func tokenPriceAnchor(symbol rawSymbol: String) async throws -> TokenPriceAnchor {
        guard let priceAnchor else {
            throw StubProviderError.unused
        }
        return priceAnchor
    }
}

private final class StubTradeProvider: TradeProvider {
    struct CandidateRequest: Equatable {
        let query: String
        let chainID: String
        let spendAssetSymbol: String
        let spendAmount: String
        let referencePriceUSD: Double?
    }

    private let tokenCandidates: [UniswapTokenCandidate]
    private(set) var candidateRequests: [CandidateRequest] = []

    init(tokenCandidates: [UniswapTokenCandidate]) {
        self.tokenCandidates = tokenCandidates
    }

    func buildSwapPlan(
        draft: TradeIntentDraft,
        chain: ChainProfile,
        walletAddress: String
    ) async throws -> UniswapTradePlan {
        throw StubProviderError.unused
    }

    func resolveTokenCandidates(
        query: String,
        chain: ChainProfile,
        spendAsset: TokenProfile,
        spendAmount: String,
        walletAddress: String,
        referencePriceUSD: Double?
    ) async throws -> [UniswapTokenCandidate] {
        candidateRequests.append(
            CandidateRequest(
                query: query,
                chainID: chain.id,
                spendAssetSymbol: spendAsset.symbol,
                spendAmount: spendAmount,
                referencePriceUSD: referencePriceUSD
            )
        )
        return tokenCandidates
    }
}

private enum StubProviderError: Error {
    case unused
}

private struct CoreSelfTestSuite {
    private(set) var passed = 0

    mutating func pass(_ name: String) {
        passed += 1
        print("pass: \(name)")
    }

    mutating func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else {
            throw CoreSelfTestError.failure(name)
        }
        pass(name)
    }

    mutating func equal<T: Equatable>(
        _ actual: @autoclosure () throws -> T,
        _ expected: T,
        _ name: String
    ) throws {
        let actualValue = try actual()
        guard actualValue == expected else {
            throw CoreSelfTestError.failure("\(name): expected \(expected), got \(actualValue)")
        }
        pass(name)
    }

    mutating func expectThrows(_ name: String, _ body: () throws -> Void) throws {
        do {
            try body()
        } catch {
            pass(name)
            return
        }

        throw CoreSelfTestError.failure("\(name): expected error")
    }
}

private enum CoreSelfTestError: LocalizedError {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message):
            return "Core self-test failed: \(message)"
        }
    }
}
