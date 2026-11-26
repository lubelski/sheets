// Writes an Icon Composer file from AppIconDrawing: icon.json and one image per layer. Run
// through scripts/render-icon.sh, which compiles this with that drawing.
//
//   render-icon <path/to/AppIcon.icon> [design number]
//   render-icon --sheet <folder>    # the contact sheet, from design-<n>-256.png and -32.png there
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(2)
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("couldn't write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("couldn't write \(url.path)") }
}

func read(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("couldn't read \(url.path)") }
    return image
}

/// Every design at 256 and 32 pixels, numbered, on a light and a dark backdrop.
func contactSheet(folder: URL) {
    let designs = AppIconDrawing.Design.allCases
    let column: CGFloat = 400, margin: CGFloat = 40, panelHeight: CGFloat = 380
    let width = margin * 2 + column * CGFloat(designs.count)
    let height = panelHeight * 2
    guard let context = CGContext(
        data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("couldn't make the sheet") }
    let backdrops: [(CGColor, CGColor)] = [
        (CGColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1), CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)),
        (CGColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1), CGColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)),
    ]
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 34, nil)!
    for (row, (backdrop, ink)) in backdrops.enumerated() {
        // The light panel on top. CG's y points up.
        let panel = CGRect(x: 0, y: height - panelHeight * CGFloat(row + 1), width: width, height: panelHeight)
        context.setFillColor(backdrop)
        context.fill(panel)
        for (index, design) in designs.enumerated() {
            let x = margin + column * CGFloat(index)
            let big = read(folder.appendingPathComponent("design-\(design.rawValue)-256.png"))
            let small = read(folder.appendingPathComponent("design-\(design.rawValue)-32.png"))
            let top = panel.maxY - 40
            context.draw(big, in: CGRect(x: x, y: top - 256, width: 256, height: 256))
            context.draw(small, in: CGRect(x: x + 256 + 24, y: top - 256, width: 32, height: 32))
            let label = "\(design.rawValue)  \(design.title)"
            let text = CFAttributedStringCreate(nil, label as CFString, [
                kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink,
            ] as CFDictionary)!
            context.textPosition = CGPoint(x: x + 8, y: top - 256 - 52)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
    }
    guard let image = context.makeImage() else { fail("couldn't draw the sheet") }
    let output = folder.appendingPathComponent("contact-sheet.png")
    write(image, to: output)
    print("Drew \(output.path)")
}

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--sheet" {
    contactSheet(folder: URL(fileURLWithPath: arguments[2]))
    exit(0)
}
guard arguments.count >= 2 else { fail("usage: render-icon <AppIcon.icon> [design number]") }
var design = AppIconDrawing.shipped
if arguments.count >= 3 {
    guard let number = Int(arguments[2]), let chosen = AppIconDrawing.Design(rawValue: number) else {
        let numbers = AppIconDrawing.Design.allCases.map { "\($0.rawValue) \($0.title)" }.joined(separator: ", ")
        fail("the design is one of \(numbers)")
    }
    design = chosen
}

let icon = URL(fileURLWithPath: arguments[1])
let assets = icon.appendingPathComponent("Assets")
let files = FileManager.default
// Start the assets over, so no image from another design is left behind.
try? files.removeItem(at: assets)
try files.createDirectory(at: assets, withIntermediateDirectories: true)
for layer in design.layers {
    guard let image = AppIconDrawing.image(of: layer) else { fail("couldn't draw \(layer.name)") }
    write(image, to: assets.appendingPathComponent("\(layer.name).png"))
}
try AppIconDrawing.iconJSON(for: design).write(
    to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Drew design \(design.rawValue), \(design.title), into \(icon.path)")
