// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ayinbox-swift",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "AyInbox", targets: ["AyInbox"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "AyInbox",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")]
        ),
        .executableTarget(name: "list-campaigns", dependencies: ["AyInbox"], path: "Examples/ListCampaigns"),
        .executableTarget(name: "verify-webhook", dependencies: ["AyInbox"], path: "Examples/VerifyWebhook"),
        .testTarget(
            name: "AyInboxTests",
            dependencies: ["AyInbox"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
