import Foundation

actor SurfClient {
    private let commandTimeout: TimeInterval = 30
    private var cachedExecutable: String?

    func research(query: String, kind: QueryKind, chainFilter: ChainFilter) async throws -> ResearchSnapshot {
        let ops = operations(for: query, kind: kind, chainFilter: chainFilter)
        guard !ops.isEmpty else {
            throw SurfClientError.unsupportedInput
        }

        let executable = try resolveExecutable()
        let timeout = commandTimeout

        let results = await withTaskGroup(
            of: (Int, SurfCommandResult).self,
            returning: [SurfCommandResult].self
        ) { group in
            for (index, op) in ops.enumerated() {
                group.addTask {
                    let result = await Self.runDetached(
                        operation: op,
                        executable: executable,
                        timeout: timeout
                    )
                    return (index, result)
                }
            }

            var buffer: [(Int, SurfCommandResult)] = []
            for await pair in group {
                buffer.append(pair)
            }
            return buffer.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        return ResearchSnapshotBuilder.snapshot(
            query: query,
            kind: kind,
            chainFilter: chainFilter,
            results: results
        )
    }

    func walletTokenAssets(
        address: String,
        chains: [ChainProfile]
    ) async throws -> [WalletChainTokenAssets] {
        let surfChains = chains.filter(Self.supportsOnchainQuery)
        guard QueryClassifier.isAddress(address), !surfChains.isEmpty else {
            throw SurfClientError.unsupportedInput
        }

        let executable = try resolveExecutable()
        let timeout = commandTimeout
        let operations = surfChains.map { chain in
            SurfOperation(
                command: "wallet-detail",
                arguments: [
                    "--address", address,
                    "--chain", chain.surfSlug,
                    "--fields", "balance,tokens"
                ],
                title: "\(chain.shortName) 钱包资产",
                chain: chain
            )
        }

        let results = await withTaskGroup(
            of: (Int, SurfCommandResult).self,
            returning: [SurfCommandResult].self
        ) { group in
            for (index, operation) in operations.enumerated() {
                group.addTask {
                    let result = await Self.runDetached(
                        operation: operation,
                        executable: executable,
                        timeout: timeout
                    )
                    return (index, result)
                }
            }

            var buffer: [(Int, SurfCommandResult)] = []
            for await pair in group {
                buffer.append(pair)
            }
            return buffer.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        return results.map(Self.walletChainTokenAssets)
    }

    func tokenPriceAnchor(symbol rawSymbol: String) async throws -> TokenPriceAnchor {
        let symbol = QueryClassifier.normalizedLookupText(rawSymbol).uppercased()
        guard !symbol.isEmpty else {
            throw SurfClientError.unsupportedInput
        }

        let executable = try resolveExecutable()
        let operation = SurfOperation(
            command: "market-price",
            arguments: [
                "--symbol", symbol,
                "--time-range", "1d",
                "--currency", "usd"
            ],
            title: "\(symbol) Surf 价格",
            chain: nil
        )
        let result = await Self.runDetached(
            operation: operation,
            executable: executable,
            timeout: commandTimeout
        )

        guard result.succeeded else {
            throw SurfClientError.commandFailed(result.errorMessage ?? "Surf 价格查询失败。")
        }
        guard let anchor = TokenPriceAnchor(result: result, fallbackSymbol: symbol) else {
            throw SurfClientError.invalidResponse("Surf 没有返回可用的最新价格。")
        }
        return anchor
    }

    private func operations(for query: String, kind: QueryKind, chainFilter: ChainFilter) -> [SurfOperation] {
        switch kind {
        case .auto:
            let classified = QueryClassifier.classify(query, preferredKind: .auto)
            guard classified != .auto else { return [] }
            return operations(for: query, kind: classified, chainFilter: chainFilter)
        case .wallet:
            return targetChains(for: query, kind: kind, chainFilter: chainFilter).flatMap { chain in
                [
                    SurfOperation(
                        command: "wallet-detail",
                        arguments: [
                            "--address", query,
                            "--chain", chain.surfSlug,
                            "--fields", "balance,tokens,labels,approvals"
                        ],
                        title: "\(chain.shortName) 钱包资产",
                        chain: chain
                    ),
                    SurfOperation(
                        command: "wallet-transfers",
                        arguments: [
                            "--address", query,
                            "--chain", chain.surfSlug,
                            "--limit", "10",
                            "--include", "labels"
                        ],
                        title: "近期 \(chain.shortName) 转账",
                        chain: chain
                    )
                ]
            }
        case .token:
            return targetChains(for: query, kind: kind, chainFilter: chainFilter).flatMap { chain in
                [
                    SurfOperation(
                        command: "token-holders",
                        arguments: [
                            "--address", query,
                            "--chain", chain.surfSlug,
                            "--limit", "10",
                            "--include", "labels"
                        ],
                        title: "\(chain.shortName) 代币持仓分布",
                        chain: chain
                    ),
                    SurfOperation(
                        command: "token-dex-trades",
                        arguments: [
                            "--address", query,
                            "--chain", chain.surfSlug,
                            "--limit", "10",
                            "--include", "labels"
                        ],
                        title: "近期 \(chain.shortName) DEX 交易",
                        chain: chain
                    ),
                    SurfOperation(
                        command: "token-transfers",
                        arguments: [
                            "--address", query,
                            "--chain", chain.surfSlug,
                            "--limit", "10",
                            "--include", "labels"
                        ],
                        title: "近期 \(chain.shortName) 代币转账",
                        chain: chain
                    )
                ]
            }
        case .transaction:
            return targetChains(for: query, kind: kind, chainFilter: chainFilter).map { chain in
                SurfOperation(
                    command: "onchain-tx",
                    arguments: [
                        "--hash", query,
                        "--chain", chain.surfSlug,
                        "--include", "labels"
                    ],
                    title: "\(chain.shortName) 交易详情",
                    chain: chain
                )
            }
        case .project:
            let lookupQuery = QueryClassifier.normalizedLookupText(query)
            return [
                SurfOperation(
                    command: "project-detail",
                    arguments: [
                        "--q", lookupQuery,
                        "--fields", "overview,token_info,contracts,social"
                    ],
                    title: "项目详情",
                    chain: nil
                ),
                SurfOperation(
                    command: "search-news",
                    arguments: [
                        "--q", lookupQuery,
                        "--limit", "5"
                    ],
                    title: "近期加密新闻",
                    chain: nil
                )
            ]
        }
    }

    static func walletChainTokenAssets(from result: SurfCommandResult) -> WalletChainTokenAssets {
        let chain = result.operation.chain ?? ChainRegistry.base
        guard result.succeeded else {
            return WalletChainTokenAssets(
                chain: chain,
                tokens: [],
                totalUSD: nil,
                errorMessage: result.errorMessage,
                updatedAt: Date()
            )
        }

        guard let data = JSONPrettyPrinter.dictionary(result.jsonObject, path: ["data"]) else {
            return WalletChainTokenAssets(
                chain: chain,
                tokens: [],
                totalUSD: nil,
                errorMessage: "Surf 没有返回钱包资产数据。",
                updatedAt: Date()
            )
        }

        let balance = data["evm_balance"] as? [String: Any]
        let totalUSD = optionalCurrency(balance?["total_usd"])
        let tokens = JSONPrettyPrinter.array(data["evm_tokens"]).compactMap(walletTokenBalance)

        return WalletChainTokenAssets(
            chain: chain,
            tokens: tokens,
            totalUSD: totalUSD,
            errorMessage: nil,
            updatedAt: Date()
        )
    }

    private static func walletTokenBalance(_ item: Any) -> WalletTokenBalance? {
        guard let dict = item as? [String: Any] else {
            return nil
        }

        let symbol = string(dict["symbol"])
            ?? string(dict["token_symbol"])
            ?? string(dict["ticker"])
            ?? "TOKEN"
        let balance = string(dict["balance"])
            ?? string(dict["amount"])
            ?? string(dict["token_balance"])
            ?? "-"
        let address = string(dict["address"])
            ?? string(dict["token_address"])
            ?? string(dict["contract_address"])
        let name = string(dict["name"]) ?? string(dict["token_name"])
        let usdValue = optionalCurrency(dict["usd_value"] ?? dict["value_usd"])

        return WalletTokenBalance(
            symbol: symbol,
            name: name,
            balance: balance,
            usdValue: usdValue,
            address: address
        )
    }

    private static func optionalCurrency(_ value: Any?) -> String? {
        guard value != nil else {
            return nil
        }

        return JSONPrettyPrinter.formatCurrency(value)
    }

    private static func string(_ value: Any?) -> String? {
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

    private func targetChains(for query: String, kind: QueryKind, chainFilter: ChainFilter) -> [ChainProfile] {
        if let profile = chainFilter.profile {
            return Self.supportsOnchainQuery(profile) ? [profile] : []
        }

        if kind == .wallet || kind == .token || kind == .transaction {
            return ChainRegistry.supported.filter(Self.supportsOnchainQuery)
        }

        return [ChainRegistry.base]
    }

    private static func supportsOnchainQuery(_ chain: ChainProfile) -> Bool {
        chain.surfSlug != ChainRegistry.unichain.surfSlug
    }

    private func resolveExecutable() throws -> String {
        if let cached = cachedExecutable,
           FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        let candidates = [
            "\(NSHomeDirectory())/.local/bin/surf",
            "\(NSHomeDirectory())/.surf/bin/surf",
            "/opt/homebrew/bin/surf",
            "/usr/local/bin/surf"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            cachedExecutable = candidate
            return candidate
        }

        if let result = try? Self.runProcessSafely(
            executable: "/usr/bin/env",
            arguments: ["which", "surf"],
            timeout: 5,
            operation: SurfOperation(command: "which", arguments: [], title: "", chain: nil)
        ),
           result.exitCode == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                cachedExecutable = path
                return path
            }
        }

        throw SurfClientError.missingSurfCLI
    }

    private static func runDetached(
        operation: SurfOperation,
        executable: String,
        timeout: TimeInterval
    ) async -> SurfCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = (try? runProcessSafely(
                    executable: executable,
                    arguments: [operation.command] + operation.arguments + ["--json", "--quiet"],
                    timeout: timeout,
                    operation: operation
                )) ?? SurfCommandResult(
                    operation: operation,
                    stdout: "",
                    stderr: "Surf 进程未能启动。",
                    exitCode: -1,
                    jsonObject: nil
                )
                continuation.resume(returning: result)
            }
        }
    }

    fileprivate static func runProcessSafely(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        operation: SurfOperation
    ) throws -> SurfCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let apiKey = CredentialStore.readSurfAPIKey(), !apiKey.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            environment["SURF_API_KEY"] = apiKey
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return SurfCommandResult(
                operation: operation,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: -1,
                jsonObject: nil
            )
        }

        // Drain stdout & stderr concurrently to avoid pipe-buffer deadlock when
        // the child writes more than ~64 KB before we read.
        let group = DispatchGroup()
        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            stdoutData = data
            lock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            stderrData = data
            lock.unlock()
            group.leave()
        }

        let deadline = DispatchTime.now() + timeout
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            group.wait()
            process.waitUntilExit()
            return SurfCommandResult(
                operation: operation,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: "Surf 命令在 \(Int(timeout)) 秒内未返回，已中止。",
                exitCode: -1,
                jsonObject: nil
            )
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let jsonObject = JSONPrettyPrinter.parse(stdout)

        return SurfCommandResult(
            operation: operation,
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            jsonObject: jsonObject
        )
    }
}

struct SurfOperation: Sendable {
    let command: String
    let arguments: [String]
    let title: String
    let chain: ChainProfile?

    var renderedCommand: String {
        (["surf", command] + arguments).joined(separator: " ")
    }
}

struct SurfCommandResult: @unchecked Sendable {
    let operation: SurfOperation
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let jsonObject: Any?

    var succeeded: Bool {
        exitCode == 0
    }

    var errorMessage: String? {
        guard !succeeded else {
            return nil
        }

        if let message = JSONPrettyPrinter.stringValue(jsonObject, path: ["error", "message"]) {
            return message
        }

        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStderr.isEmpty {
            return trimmedStderr
        }

        return "Surf 命令执行失败。"
    }
}

struct TokenPriceAnchor: Equatable, Sendable {
    let symbol: String
    let priceUSD: Double
    let latestTimestamp: Int?
    let changePercent24h: Double?
    let high24h: Double?
    let low24h: Double?
    let rawJSON: String?

    var formattedPrice: String {
        JSONPrettyPrinter.formatCurrency(priceUSD)
    }

    var formattedChange: String? {
        guard let changePercent24h else {
            return nil
        }
        return JSONPrettyPrinter.formatPercent(changePercent24h)
    }

    init?(
        result: SurfCommandResult,
        fallbackSymbol: String
    ) {
        guard let object = result.jsonObject as? [String: Any],
              let summary = object["summary"] as? [String: Any],
              let price = Self.doubleValue(summary["last"]) else {
            return nil
        }

        self.symbol = (object["symbol"] as? String ?? fallbackSymbol).uppercased()
        self.priceUSD = price
        self.latestTimestamp = Self.intValue(summary["latest_dt"])
        self.changePercent24h = Self.doubleValue(summary["change_pct"])
        self.high24h = Self.doubleValue(summary["high"])
        self.low24h = Self.doubleValue(summary["low"])
        self.rawJSON = JSONPrettyPrinter.prettyString(object)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}

enum SurfClientError: LocalizedError {
    case missingSurfCLI
    case unsupportedInput
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingSurfCLI:
            "没有找到 Surf CLI。请先安装 Surf，然后运行 surf sync。"
        case .unsupportedInput:
            "暂不支持这种输入。"
        case .commandFailed(let message):
            "Surf 查询失败：\(message)"
        case .invalidResponse(let message):
            message
        }
    }
}
