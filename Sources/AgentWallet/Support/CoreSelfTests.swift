import AppKit
import BigInt
import Darwin
import Foundation

enum CoreSelfTests {
    static func run() async throws -> String {
        var suite = CoreSelfTestSuite()
        try testWalletIntentParser(&suite)
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
