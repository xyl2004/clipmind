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
    targets: [
        .executableTarget(
            name: "AgentWallet",
            path: "Sources/AgentWallet"
        )
    ]
)
