// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TradingPlatform",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TradingPlatform",
            targets: ["TradingPlatform"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.0"),
        .package(url: "https://github.com/willdale/SwiftUICharts", from: "2.10.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "TradingPlatform",
            dependencies: [
                "Alamofire",
                "KeychainAccess",
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                "SwiftUICharts",
                "SwiftSoup",
            ],
            resources: [
                .process("Resources"),
                .process("Models/SECBERT.mlmodel")
            ]
        ),
    ]
)