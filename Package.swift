// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "sheets",
    platforms: [.macOS(.v27)],
    dependencies: [
        // The updater. Only the app target uses it, and only `AppUpdater.swift` imports it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
        // The first terminal engine. Pinned exactly: the 1.99 releases lead up to 2.0 and change
        // API between them. Only the SheetsSwiftTermEngine target uses it.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.99.4"),
    ],
    targets: [
        // Pure logic: the pane tree, the stack of sheets on screen, the split layout, and the
        // terminal engine seam with its session store. No UI, so every rule here is tested
        // without a window.
        .target(name: "SheetsCore"),
        // The SwiftTerm terminal engine: a `TerminalEngine` from SheetsCore, and the AppKit
        // view it draws in. Nothing else imports SwiftTerm, so a second engine sits beside it.
        .target(
            name: "SheetsSwiftTermEngine",
            dependencies: ["SheetsCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        // The app: its scenes and views.
        .executableTarget(
            name: "sheets",
            dependencies: [
                "SheetsCore", "SheetsSwiftTermEngine", .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(name: "SheetsCoreTests", dependencies: ["SheetsCore"]),
        .testTarget(name: "SheetsSwiftTermEngineTests", dependencies: ["SheetsSwiftTermEngine"]),
        // The app's own model and views, drawn in a window that is never put on screen.
        .testTarget(name: "SheetsAppTests", dependencies: ["sheets"]),
    ]
)
