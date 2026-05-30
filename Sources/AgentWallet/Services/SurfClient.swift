import Foundation

actor SurfClient {
    private let baseChain = "base"
    private let commandTimeout: TimeInterval = 30
    private var cachedExecutable: String?

    func research(query: String, kind: QueryKind) async throws -> ResearchSnapshot {
        let ops = operations(for: query, kind: kind)
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
            results: results
        )
    }

    private func operations(for query: String, kind: QueryKind) -> [SurfOperation] {
        switch kind {
        case .auto:
            let classified = QueryClassifier.classify(query, preferredKind: .auto)
            guard classified != .auto else { return [] }
            return operations(for: query, kind: classified)
        case .wallet:
            return [
                SurfOperation(
                    command: "wallet-detail",
                    arguments: [
                        "--address", query,
                        "--chain", baseChain,
                        "--fields", "balance,tokens,labels,approvals"
                    ],
                    title: "Base 钱包资产"
                ),
                SurfOperation(
                    command: "wallet-transfers",
                    arguments: [
                        "--address", query,
                        "--chain", baseChain,
                        "--limit", "10",
                        "--include", "labels"
                    ],
                    title: "近期 Base 转账"
                ),
                gasOperation()
            ]
        case .token:
            return [
                SurfOperation(
                    command: "token-holders",
                    arguments: [
                        "--address", query,
                        "--chain", baseChain,
                        "--limit", "10",
                        "--include", "labels"
                    ],
                    title: "Base 代币持仓分布"
                ),
                SurfOperation(
                    command: "token-dex-trades",
                    arguments: [
                        "--address", query,
                        "--chain", baseChain,
                        "--limit", "10",
                        "--include", "labels"
                    ],
                    title: "近期 Base DEX 交易"
                ),
                SurfOperation(
                    command: "token-transfers",
                    arguments: [
                        "--address", query,
                        "--chain", baseChain,
                        "--limit", "10",
                        "--include", "labels"
                    ],
                    title: "近期 Base 代币转账"
                ),
                gasOperation()
            ]
        case .transaction:
            return [
                SurfOperation(
                    command: "onchain-tx",
                    arguments: [
                        "--hash", query,
                        "--chain", baseChain,
                        "--include", "labels"
                    ],
                    title: "Base 交易详情"
                ),
                gasOperation()
            ]
        case .project:
            return [
                SurfOperation(
                    command: "project-detail",
                    arguments: [
                        "--q", query,
                        "--fields", "overview,token_info,contracts,social"
                    ],
                    title: "项目详情"
                ),
                SurfOperation(
                    command: "search-news",
                    arguments: [
                        "--q", query,
                        "--limit", "5"
                    ],
                    title: "近期加密新闻"
                ),
                gasOperation()
            ]
        }
    }

    private func gasOperation() -> SurfOperation {
        SurfOperation(
            command: "onchain-gas-price",
            arguments: ["--chain", baseChain],
            title: "Base Gas 价格"
        )
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
            operation: SurfOperation(command: "which", arguments: [], title: "")
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

enum SurfClientError: LocalizedError {
    case missingSurfCLI
    case unsupportedInput

    var errorDescription: String? {
        switch self {
        case .missingSurfCLI:
            "没有找到 Surf CLI。请先安装 Surf，然后运行 surf sync。"
        case .unsupportedInput:
            "暂不支持这种输入。"
        }
    }
}
