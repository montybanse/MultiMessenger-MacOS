// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiMessenger",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MultiMessenger",
            path: "Sources/MultiMessenger"
        ),
        // Share Extension (.appex) – fürs native „Teilen“-Menü.
        .executableTarget(
            name: "MMShareExtension",
            path: "Sources/MMShareExtension"
        )
    ]
)
