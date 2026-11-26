// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "sheets",
    platforms: [.macOS(.v27)],
    targets: [
        // Pure logic: the pane tree, the stack of sheets on screen, and the split layout.
        // No UI, so every rule here is tested without a window.
        .target(name: "SheetsCore"),
        // The app: its scenes and views.
        .executableTarget(name: "sheets", dependencies: ["SheetsCore"]),
        .testTarget(name: "SheetsCoreTests", dependencies: ["SheetsCore"]),
    ]
)
