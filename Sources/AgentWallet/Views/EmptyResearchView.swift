import SwiftUI

struct EmptyResearchView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Base 查询台", systemImage: "sparkle.magnifyingglass")
                .font(.title2.weight(.semibold))

            Text("粘贴代币合约、钱包地址、交易哈希或项目名称。AgentWallet 会通过 Surf 获取 Base 实时数据，并把交易执行留在确认边界之后。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)

            HStack(spacing: 12) {
                CapabilityPill(title: "钱包标签", systemImage: "tag")
                CapabilityPill(title: "持仓分布", systemImage: "person.3")
                CapabilityPill(title: "DEX 交易", systemImage: "chart.line.uptrend.xyaxis")
                CapabilityPill(title: "Gas", systemImage: "fuelpump")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .productPanel(padding: 20)
    }
}

private struct CapabilityPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.panelSoft, in: Capsule())
    }
}

struct StatusBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
