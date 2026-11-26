import AppKit

// The app starts here rather than with `@main`, so launch arguments are handled before any
// window opens.
//
// `--render-previews <folder>` draws the main window's key states to PNG files and exits,
// without starting the app: no window on screen, no Dock icon, no focus.
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: PreviewRenderer.argument) {
    guard index + 1 < arguments.count else {
        print("\(PreviewRenderer.argument) needs an output folder.")
        exit(2)
    }
    let folder = URL(filePath: (arguments[index + 1] as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    MainActor.assumeIsolated { PreviewRenderer.render(to: folder) }
    exit(0)
}

SheetsApp.main()
