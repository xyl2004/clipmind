import SwiftUI

struct TradeIntentView: View {
    let query: String
    @State private var spendAmount = "20"
    @State private var slippage = 1.0
    @State private var mode: TradeMode = .swap

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("交易意图草稿", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                Picker("模式", selection: $mode) {
                    ForEach(TradeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack(spacing: 12) {
                TextField("USDC", text: $spendAmount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Slider(value: $slippage, in: 0.1...5.0, step: 0.1) {
                    Text("滑点")
                }
                .frame(width: 180)

                Text("\(slippage, specifier: "%.1f")%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 52, alignment: .trailing)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                IntentRow(label: "网络", value: "Base")
                IntentRow(label: "支付资产", value: "USDC")
                IntentRow(label: mode == .swap ? "目标代币" : "接收地址", value: query)
                IntentRow(label: "状态", value: "仅生成计划。当前原型不会签名或广播交易。")
            }

            HStack {
                Button {
                } label: {
                    Label("准备确认单", systemImage: "doc.badge.gearshape")
                }
                .disabled(true)

                Text("下一步：路由报价、策略检查、本地签名确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .productPanel(padding: 16)
    }
}

private struct IntentRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private enum TradeMode: String, CaseIterable, Identifiable {
    case swap
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swap:
            "兑换"
        case .transfer:
            "转账"
        }
    }
}
