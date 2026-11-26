import CoreGraphics
import Foundation
import Testing
@testable import SheetsCore

@Suite struct AppIconDrawingTests {
    /// The box, in canvas pixels, of every pixel a layer draws, or nil when it draws nothing.
    private func inkBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Every layer of every design draws something, and keeps clear of the edges, where the
    /// system's rounded corners and its glass would cut into it.
    @Test(arguments: AppIconDrawing.Design.allCases)
    func everyLayerDrawsInsideTheSafeArea(design: AppIconDrawing.Design) throws {
        let names = design.layers.map(\.name)
        #expect(Set(names).count == names.count)
        let safe = CGRect(x: 0, y: 0, width: AppIconDrawing.canvas, height: AppIconDrawing.canvas).insetBy(dx: 160, dy: 160)
        for layer in design.layers {
            let image = try #require(AppIconDrawing.image(of: layer))
            let ink = try #require(inkBounds(of: image), "\(design) \(layer.name) draws nothing")
            #expect(safe.contains(ink), "\(design) \(layer.name) draws at \(ink)")
        }
    }

    /// The Icon Composer file in the repo is the shipped design, so changing `shipped`
    /// without running scripts/render-icon.sh fails here.
    @Test func theIconInTheRepoIsTheShippedDesign() throws {
        let icon = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icon")
        let json = try String(contentsOf: icon.appendingPathComponent("icon.json"), encoding: .utf8)
        #expect(json == AppIconDrawing.iconJSON(for: AppIconDrawing.shipped))
        let images = try FileManager.default.contentsOfDirectory(atPath: icon.appendingPathComponent("Assets").path)
        #expect(Set(images) == Set(AppIconDrawing.shipped.layers.map { "\($0.name).png" }))
    }
}
