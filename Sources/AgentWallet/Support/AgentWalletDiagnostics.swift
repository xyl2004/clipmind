import Foundation

enum AgentWalletDiagnostics {
    static func runIfRequested() {
        if CommandLine.arguments.contains("--self-test-core") {
            runCoreSelfTestsAndExit()
        }

        if let index = CommandLine.arguments.firstIndex(of: "--self-test-surf-price") {
            let symbol = CommandLine.arguments.dropFirst(index + 1).first ?? "ZEC"
            runSurfPriceSelfTestAndExit(symbol: symbol)
        }

        guard CommandLine.arguments.contains("--self-test-uniswap-sepolia") else {
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 1

        Task {
            do {
                let output = try await runUniswapSepoliaDryRun()
                print(output)
                exitCode = 0
            } catch {
                print("self_test_uniswap_sepolia=failed")
                print(error.localizedDescription)
                exitCode = 1
            }
            semaphore.signal()
        }

        semaphore.wait()
        Foundation.exit(exitCode)
    }

    private static func runCoreSelfTestsAndExit() {
        DispatchQueue.main.async {
            Task {
                do {
                    let output = try await CoreSelfTests.run()
                    print(output)
                    Foundation.exit(0)
                } catch {
                    print("self_test_core=failed")
                    print(error.localizedDescription)
                    Foundation.exit(1)
                }
            }
        }
    }

    private static func runSurfPriceSelfTestAndExit(symbol: String) {
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 1

        Task {
            do {
                let anchor = try await SurfClient().tokenPriceAnchor(symbol: symbol)
                let latestTimestamp = anchor.latestTimestamp.map { String($0) } ?? "unknown"
                let changePercent = anchor.changePercent24h.map { String($0) } ?? "unknown"
                print(
                    [
                        "self_test_surf_price=ok",
                        "symbol=\(anchor.symbol)",
                        "price_usd=\(anchor.priceUSD)",
                        "latest_dt=\(latestTimestamp)",
                        "change_pct_24h=\(changePercent)"
                    ].joined(separator: "\n")
                )
                exitCode = 0
            } catch {
                print("self_test_surf_price=failed")
                print(error.localizedDescription)
                exitCode = 1
            }
            semaphore.signal()
        }

        semaphore.wait()
        Foundation.exit(exitCode)
    }

    private static func runUniswapSepoliaDryRun() async throws -> String {
        guard let apiKey = CredentialStore.readUniswapAPIKeyWithoutPrompt() else {
            throw DiagnosticError.missingUniswapKey
        }

        let chain = ChainRegistry.ethereumSepolia
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let provider = UniswapTradeProvider(
            session: URLSession(configuration: configuration),
            apiKeyOverride: apiKey
        )
        let draft = TradeIntentDraft(
            spendAmount: "0.001",
            spendTokenSymbol: "ETH",
            spendTokenAddress: TokenProfile.nativeETH.address,
            spendTokenDecimals: TokenProfile.nativeETH.decimals,
            tokenAddress: "0xfff9976782d46cc05630d1f6ebab18b2324d6b14",
            slippage: 1.0,
            recipientAddress: ""
        )
        let plan = try await provider.buildSwapPlan(
            draft: draft,
            chain: chain,
            walletAddress: "0x000000000000000000000000000000000000dEaD"
        )

        return [
            "self_test_uniswap_sepolia=ok",
            "chain_id=\(plan.chain.chainID)",
            "input=\(plan.inputAmount) \(plan.inputToken.symbol)",
            "output_amount=\(plan.outputAmount ?? "unknown")",
            "needs_approval=\(plan.needsApproval)",
            "swap_to=\(plan.swapTransaction?.shortTo ?? "none")",
            "gas_fee=\(plan.gasFee ?? "unknown")"
        ].joined(separator: "\n")
    }
}

private enum DiagnosticError: LocalizedError {
    case missingUniswapKey

    var errorDescription: String? {
        switch self {
        case .missingUniswapKey:
            "未检测到 Uniswap API Key。请先在 App 的服务连接区保存 Key。"
        }
    }
}
