import Foundation

enum ResearchSnapshotBuilder {
    static func snapshot(
        query: String,
        kind: QueryKind,
        results: [SurfCommandResult]
    ) -> ResearchSnapshot {
        var sections: [ResearchSection] = []
        var warnings: [String] = []

        for result in results {
            if result.succeeded {
                sections.append(contentsOf: sectionsForResult(result))
            } else if let message = result.errorMessage {
                warnings.append("\(result.operation.title): \(message)")
            }
        }

        if sections.isEmpty {
            sections.append(
                ResearchSection(
                    title: "暂无数据",
                    rows: [
                        ResearchRow("结果", "Surf 没有返回可展示的数据。", style: .warning)
                    ]
                )
            )
        }

        let commandSummaries = results.map { result in
            SurfCommandSummary(
                command: "surf \(result.operation.command)",
                succeeded: result.succeeded,
                summary: result.succeeded ? result.operation.title : (result.errorMessage ?? "失败")
            )
        }

        return ResearchSnapshot(
            title: title(for: kind),
            subtitle: "Base 网络 · Surf 实时数据",
            query: query,
            kind: kind,
            createdAt: Date(),
            sections: sections,
            commands: commandSummaries,
            rawJSON: combinedRawJSON(results),
            warnings: warnings
        )
    }

    private static func title(for kind: QueryKind) -> String {
        switch kind {
        case .auto:
            "Base 查询"
        case .wallet:
            "钱包查询"
        case .token:
            "代币查询"
        case .transaction:
            "交易查询"
        case .project:
            "项目查询"
        }
    }

    private static func sectionsForResult(_ result: SurfCommandResult) -> [ResearchSection] {
        switch result.operation.command {
        case "wallet-detail":
            walletSections(result)
        case "wallet-transfers":
            transferSections(result)
        case "token-holders":
            holderSections(result)
        case "token-dex-trades":
            dexTradeSections(result)
        case "token-transfers":
            transferSections(result)
        case "onchain-tx":
            transactionSections(result)
        case "onchain-gas-price":
            gasSections(result)
        case "project-detail":
            projectSections(result)
        case "search-news":
            newsSections(result)
        default:
            genericSections(result)
        }
    }

    private static func walletSections(_ result: SurfCommandResult) -> [ResearchSection] {
        guard let data = JSONPrettyPrinter.dictionary(result.jsonObject, path: ["data"]) else {
            return genericSections(result)
        }

        var sections: [ResearchSection] = []

        if let balance = data["evm_balance"] as? [String: Any] {
            let totalUSD = JSONPrettyPrinter.formatCurrency(balance["total_usd"])
            let chains = JSONPrettyPrinter.array(balance["chain_balances"])
            sections.append(
                ResearchSection(
                    title: "资产概览",
                    rows: [
                        ResearchRow("EVM 总价值", totalUSD, style: .positive),
                        ResearchRow("查询范围", "链过滤：Base")
                    ] + chains.prefix(4).compactMap { item in
                        guard let dict = item as? [String: Any] else { return nil }
                        return ResearchRow(
                            dict["chain"] as? String ?? "链",
                            JSONPrettyPrinter.formatCurrency(dict["usd_value"])
                        )
                    }
                )
            )
        }

        let tokens = JSONPrettyPrinter.array(data["evm_tokens"])
        if !tokens.isEmpty {
            sections.append(
                ResearchSection(
                    title: "主要代币",
                    rows: tokens.prefix(8).compactMap { item in
                        guard let dict = item as? [String: Any] else { return nil }
                        let symbol = dict["symbol"] as? String ?? "代币"
                        let balance = dict["balance"] as? String ?? "-"
                        let usd = JSONPrettyPrinter.formatCurrency(dict["usd_value"])
                        return ResearchRow(symbol, "\(balance) · \(usd)")
                    }
                )
            )
        }

        if let labels = data["labels"] as? [String: Any] {
            var rows: [ResearchRow] = []
            if let name = labels["entity_name"] as? String {
                rows.append(ResearchRow("实体", name, style: .positive))
            }
            if let type = labels["entity_type"] as? String {
                rows.append(ResearchRow("类型", type))
            }
            rows.append(contentsOf: JSONPrettyPrinter.array(labels["labels"]).prefix(4).compactMap { item in
                guard let dict = item as? [String: Any] else { return nil }
                return ResearchRow(
                    "标签",
                    dict["label"] as? String ?? "-"
                )
            })
            if !rows.isEmpty {
                sections.append(ResearchSection(title: "地址标签", rows: rows))
            }
        }

        let approvals = JSONPrettyPrinter.array(data["approvals"])
        if !approvals.isEmpty {
            sections.append(
                ResearchSection(
                    title: "授权",
                    rows: approvals.prefix(6).compactMap { item in
                        guard let dict = item as? [String: Any] else { return nil }
                        let symbol = dict["symbol"] as? String ?? "代币"
                        let spenderCount = JSONPrettyPrinter.array(dict["spenders"]).count
                        return ResearchRow(symbol, "\(spenderCount) 个授权对象", style: spenderCount > 0 ? .warning : .regular)
                    }
                )
            )
        }

        return sections
    }

    private static func holderSections(_ result: SurfCommandResult) -> [ResearchSection] {
        let rows = JSONPrettyPrinter.array(result.jsonObject, path: ["data"]).prefix(10).compactMap { item -> ResearchRow? in
            guard let dict = item as? [String: Any] else { return nil }
            let address = dict["address"] as? String ?? "-"
            let percentage = JSONPrettyPrinter.formatPercent(dict["percentage"])
            let entity = dict["entity_name"] as? String
            return ResearchRow(
                JSONPrettyPrinter.shortAddress(address),
                [percentage, entity].compactMap { $0 }.joined(separator: " · "),
                style: percentage == "-" ? .regular : .mono
            )
        }

        guard !rows.isEmpty else {
            return []
        }

        return [ResearchSection(title: "主要持仓地址", rows: rows)]
    }

    private static func dexTradeSections(_ result: SurfCommandResult) -> [ResearchSection] {
        let rows = JSONPrettyPrinter.array(result.jsonObject, path: ["data"]).prefix(10).compactMap { item -> ResearchRow? in
            guard let dict = item as? [String: Any] else { return nil }
            let pair = dict["token_pair"] as? String ?? "交易对"
            let project = dict["project"] as? String ?? "DEX"
            let amount = JSONPrettyPrinter.formatCurrency(dict["amount_usd"])
            let symbol = "\(dict["token_sold_symbol"] as? String ?? "?") → \(dict["token_bought_symbol"] as? String ?? "?")"
            return ResearchRow("\(project) · \(pair)", "\(symbol) · \(amount)")
        }

        guard !rows.isEmpty else {
            return []
        }

        return [ResearchSection(title: "近期 DEX 交易", rows: rows)]
    }

    private static func transferSections(_ result: SurfCommandResult) -> [ResearchSection] {
        let rows = JSONPrettyPrinter.array(result.jsonObject, path: ["data"]).prefix(10).compactMap { item -> ResearchRow? in
            guard let dict = item as? [String: Any] else { return nil }
            let hash = dict["tx_hash"] as? String ?? dict["hash"] as? String ?? "-"
            let from = JSONPrettyPrinter.shortAddress(dict["from_address"] as? String ?? dict["from"] as? String ?? "")
            let to = JSONPrettyPrinter.shortAddress(dict["to_address"] as? String ?? dict["to"] as? String ?? "")
            let symbol = dict["symbol"] as? String ?? dict["token_symbol"] as? String ?? "转账"
            return ResearchRow(symbol, "\(from) → \(to) · \(JSONPrettyPrinter.shortHash(hash))")
        }

        guard !rows.isEmpty else {
            return []
        }

        return [ResearchSection(title: result.operation.title, rows: rows)]
    }

    private static func transactionSections(_ result: SurfCommandResult) -> [ResearchSection] {
        guard let tx = JSONPrettyPrinter.array(result.jsonObject, path: ["data"]).first as? [String: Any] else {
            return []
        }

        let rows = [
            ResearchRow("哈希", JSONPrettyPrinter.shortHash(tx["hash"] as? String ?? "-"), style: .mono),
            ResearchRow("发送方", JSONPrettyPrinter.shortAddress(tx["from"] as? String ?? "-"), style: .mono),
            ResearchRow("接收方", JSONPrettyPrinter.shortAddress(tx["to"] as? String ?? "-"), style: .mono),
            ResearchRow("金额", JSONPrettyPrinter.weiHexToETH(tx["value"] as? String), style: .positive),
            ResearchRow("Gas 价格", JSONPrettyPrinter.weiHexToGwei(tx["gasPrice"] as? String)),
            ResearchRow("类型", tx["type"] as? String ?? "-")
        ]

        return [ResearchSection(title: "交易详情", rows: rows)]
    }

    private static func gasSections(_ result: SurfCommandResult) -> [ResearchSection] {
        guard let data = JSONPrettyPrinter.dictionary(result.jsonObject, path: ["data"]) else {
            return []
        }

        return [
            ResearchSection(
                title: "Base Gas",
                rows: [
                    ResearchRow("当前 Gas", "\(JSONPrettyPrinter.formatNumber(data["gas_price_gwei"])) gwei", style: .positive),
                    ResearchRow("链", data["chain"] as? String ?? "base")
                ]
            )
        ]
    }

    private static func projectSections(_ result: SurfCommandResult) -> [ResearchSection] {
        guard let data = JSONPrettyPrinter.dictionary(result.jsonObject, path: ["data"]) else {
            return []
        }

        guard let overview = data["overview"] as? [String: Any] else {
            return genericSections(result)
        }

        var sections: [ResearchSection] = []
        var overviewRows: [ResearchRow] = []

        if let name = overview["name"] as? String {
            overviewRows.append(ResearchRow("名称", name, style: .positive))
        }
        if let symbol = overview["token_symbol"] as? String {
            overviewRows.append(ResearchRow("代币", symbol))
        }
        if let website = overview["website"] as? String {
            overviewRows.append(ResearchRow("官网", website))
        }
        if let handle = overview["x_handle"] as? String {
            let followers = JSONPrettyPrinter.formatNumber(overview["x_followers"])
            overviewRows.append(ResearchRow("X", "@\(handle) · \(followers) 关注者"))
        }
        if let description = overview["description"] as? String, !description.isEmpty {
            overviewRows.append(ResearchRow("简介", description))
        }

        if !overviewRows.isEmpty {
            sections.append(ResearchSection(title: "项目概览", rows: overviewRows))
        }

        if let tokenInfo = data["token_info"] as? [String: Any] {
            var tokenRows: [ResearchRow] = []
            if let price = tokenInfo["price_usd"] {
                tokenRows.append(ResearchRow("价格", JSONPrettyPrinter.formatCurrency(price), style: .positive))
            }
            if let marketCap = tokenInfo["market_cap_usd"] {
                tokenRows.append(ResearchRow("市值", JSONPrettyPrinter.formatCurrency(marketCap)))
            }
            if let fdv = tokenInfo["fdv"] {
                tokenRows.append(ResearchRow("FDV", JSONPrettyPrinter.formatCurrency(fdv)))
            }
            if let change = tokenInfo["price_change_24h"] {
                tokenRows.append(ResearchRow("24h", JSONPrettyPrinter.formatPercent(change)))
            }
            if !tokenRows.isEmpty {
                sections.append(ResearchSection(title: "代币信息", rows: tokenRows))
            }
        }

        if let contracts = data["contracts"] as? [String: Any] {
            let rows = JSONPrettyPrinter.array(contracts["contracts"]).prefix(8).compactMap { item -> ResearchRow? in
                guard let dict = item as? [String: Any] else { return nil }
                let chain = dict["chain"] as? String ?? "链"
                let address = dict["address"] as? String ?? "-"
                return ResearchRow(chain, JSONPrettyPrinter.shortAddress(address), style: .mono)
            }
            if !rows.isEmpty {
                sections.append(ResearchSection(title: "合约地址", rows: rows))
            }
        }

        return sections
    }

    private static func newsSections(_ result: SurfCommandResult) -> [ResearchSection] {
        let rows = JSONPrettyPrinter.array(result.jsonObject, path: ["data"]).prefix(5).compactMap { item -> ResearchRow? in
            guard let dict = item as? [String: Any] else { return nil }
            let title = dict["title"] as? String ?? "新闻"
            let source = dict["source"] as? String ?? "来源"
            return ResearchRow(source, title)
        }

        guard !rows.isEmpty else {
            return []
        }

        return [ResearchSection(title: "相关新闻", rows: rows)]
    }

    private static func genericSections(_ result: SurfCommandResult) -> [ResearchSection] {
        let summary = JSONPrettyPrinter.compactSummary(result.jsonObject) ?? "下方可查看原始 JSON。"
        return [
            ResearchSection(
                title: result.operation.title,
                rows: [ResearchRow("响应", summary)]
            )
        ]
    }

    private static func combinedRawJSON(_ results: [SurfCommandResult]) -> String {
        results.map { result in
            let body = JSONPrettyPrinter.prettyString(result.jsonObject) ?? result.stdout
            return "## surf \(result.operation.command)\n\(body)"
        }
        .joined(separator: "\n\n")
    }
}
