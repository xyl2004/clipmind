import Foundation

struct ChainProfile: Identifiable, Hashable, Sendable {
    let id: String
    let chainID: Int
    let displayName: String
    let shortName: String
    let surfSlug: String
    let explorerBaseURL: URL
    let nativeTokenSymbol: String
    let supportsSwap: Bool
    let defaultSpendToken: TokenProfile

    var explorerTransactionURLPrefix: String {
        explorerBaseURL.appendingPathComponent("tx").absoluteString
    }
}

struct TokenProfile: Hashable, Sendable {
    let symbol: String
    let address: String
    let decimals: Int

    static let nativeETH = TokenProfile(
        symbol: "ETH",
        address: "0x0000000000000000000000000000000000000000",
        decimals: 18
    )
}

enum ChainRegistry {
    static let ethereum = ChainProfile(
        id: "ethereum",
        chainID: 1,
        displayName: "Ethereum",
        shortName: "ETH",
        surfSlug: "ethereum",
        explorerBaseURL: URL(string: "https://etherscan.io")!,
        nativeTokenSymbol: "ETH",
        supportsSwap: true,
        defaultSpendToken: TokenProfile(
            symbol: "USDC",
            address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            decimals: 6
        )
    )

    static let base = ChainProfile(
        id: "base",
        chainID: 8453,
        displayName: "Base",
        shortName: "Base",
        surfSlug: "base",
        explorerBaseURL: URL(string: "https://basescan.org")!,
        nativeTokenSymbol: "ETH",
        supportsSwap: true,
        defaultSpendToken: TokenProfile(
            symbol: "USDC",
            address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            decimals: 6
        )
    )

    static let arbitrum = ChainProfile(
        id: "arbitrum",
        chainID: 42161,
        displayName: "Arbitrum",
        shortName: "ARB",
        surfSlug: "arbitrum",
        explorerBaseURL: URL(string: "https://arbiscan.io")!,
        nativeTokenSymbol: "ETH",
        supportsSwap: true,
        defaultSpendToken: TokenProfile(
            symbol: "USDC",
            address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
            decimals: 6
        )
    )

    static let optimism = ChainProfile(
        id: "optimism",
        chainID: 10,
        displayName: "OP Mainnet",
        shortName: "OP",
        surfSlug: "optimism",
        explorerBaseURL: URL(string: "https://optimistic.etherscan.io")!,
        nativeTokenSymbol: "ETH",
        supportsSwap: true,
        defaultSpendToken: TokenProfile(
            symbol: "USDC",
            address: "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
            decimals: 6
        )
    )

    static let polygon = ChainProfile(
        id: "polygon",
        chainID: 137,
        displayName: "Polygon",
        shortName: "Polygon",
        surfSlug: "polygon",
        explorerBaseURL: URL(string: "https://polygonscan.com")!,
        nativeTokenSymbol: "POL",
        supportsSwap: true,
        defaultSpendToken: TokenProfile(
            symbol: "USDC",
            address: "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359",
            decimals: 6
        )
    )

    static let unichain = ChainProfile(
        id: "unichain",
        chainID: 130,
        displayName: "Unichain",
        shortName: "Unichain",
        surfSlug: "unichain",
        explorerBaseURL: URL(string: "https://uniscan.xyz")!,
        nativeTokenSymbol: "ETH",
        supportsSwap: true,
        defaultSpendToken: .nativeETH
    )

    static let supported: [ChainProfile] = [
        ethereum,
        base,
        arbitrum,
        optimism,
        polygon,
        unichain
    ]

    static func profile(for id: String) -> ChainProfile? {
        supported.first { $0.id == id }
    }

    static func profile(chainID: Int) -> ChainProfile? {
        supported.first { $0.chainID == chainID }
    }
}

struct ChainFilter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let profile: ChainProfile?

    var isAutomatic: Bool {
        profile == nil
    }

    static let automatic = ChainFilter(
        id: "auto",
        title: "自动",
        systemImage: "sparkle.magnifyingglass",
        profile: nil
    )

    static let all: [ChainFilter] = [automatic] + ChainRegistry.supported.map { profile in
        ChainFilter(
            id: profile.id,
            title: profile.shortName,
            systemImage: "link",
            profile: profile
        )
    }

    static func filter(for id: String) -> ChainFilter {
        all.first { $0.id == id } ?? automatic
    }
}
