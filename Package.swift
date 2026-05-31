// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentWallet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentWallet", targets: ["AgentWallet"])
    ],
    dependencies: [
        .package(url: "https://github.com/web3swift-team/web3swift.git", from: "3.3.2")
    ],
    targets: [
        .executableTarget(
            name: "AgentWallet",
            dependencies: [
                .product(name: "web3swift", package: "web3swift")
            ],
            path: "Sources/AgentWallet"
        )
    ]
)
