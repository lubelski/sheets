// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "sheets",
    platforms: [.macOS(.v27)],
    dependencies: [
        // The updater. Only the app target uses it, and only `AppUpdater.swift` imports it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        // Pure logic: the pane tree, the stack of sheets on screen, and the split layout.
        // No UI, so every rule here is tested without a window.
        .target(name: "SheetsCore"),
        // The app: its scenes and views.
        .executableTarget(
            name: "sheets",
            dependencies: ["SheetsCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "SheetsCoreTests", dependencies: ["SheetsCore"]),
    ]
)
