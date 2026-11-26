import CoreGraphics
import Foundation

/// Draws the app icon's artwork: white sheets on a clear background, one image per layer of
/// the Icon Composer file. `scripts/render-icon.sh` turns them into `Resources/AppIcon.icon`,
/// and the system adds the background shape and the glass.
///
/// Every design is the app's own stack: sheets laid over each other, each one lower and
/// further to the trailing side than the one under it. Each sheet is its own layer in its own
/// group, so each casts a shadow on the ones below.
///
/// There are three designs, for choosing. `shipped` is the one in the app.
public enum AppIconDrawing {
    /// The side of the square canvas, in pixels. Icon Composer's canvas for a Mac icon.
    public static let canvas: CGFloat = 1024

    /// The design in `Resources/AppIcon.icon`. To ship another, change this one line and run
    /// `scripts/render-icon.sh`.
    public static let shipped = Design.windowStack

    public enum Design: Int, CaseIterable, Sendable {
        /// Three rounded cards of one size, each over and down to the right of the last, the
        /// lower ones fainter.
        case cards = 1
        /// Four sheets as the window stacks them: each starts lower and further right, all run
        /// to the same bottom right corner, and each is round at its top leading corner.
        case windowStack = 2
        /// The three cards drawn as glass: faint fills with a bright top and leading edge, the
        /// lit edge the app gives a raised sheet.
        case litEdges = 3

        public var title: String {
            switch self {
            case .cards: "Cards"
            case .windowStack: "Window stack"
            case .litEdges: "Lit edges"
            }
        }

        /// The background gradient, top color first, as sRGB components.
        public var gradient: (top: [CGFloat], bottom: [CGFloat]) {
            switch self {
            case .cards, .windowStack: ([0.25, 0.28, 0.36], [0.07, 0.08, 0.12])
            case .litEdges: ([0.20, 0.27, 0.52], [0.05, 0.07, 0.18])
            }
        }

        /// The layers, front first, as Icon Composer lists them.
        public var layers: [Layer] {
            switch self {
            case .cards:
                AppIconDrawing.cardRects.enumerated().reversed().map { index, rect in
                    let alpha = AppIconDrawing.cardAlphas[index]
                    return Layer(name: "sheet-\(index + 1)") { context in
                        AppIconDrawing.fill(context, AppIconDrawing.roundedPath(rect, radius: 72), alpha: alpha)
                    }
                }
            case .windowStack:
                AppIconDrawing.stackRects.enumerated().reversed().map { index, rect in
                    let alpha = AppIconDrawing.stackAlphas[index]
                    return Layer(name: "sheet-\(index + 1)") { context in
                        AppIconDrawing.fill(context, AppIconDrawing.sheetPath(rect), alpha: alpha)
                    }
                }
            case .litEdges:
                AppIconDrawing.cardRects.enumerated().reversed().map { index, rect in
                    let alpha = AppIconDrawing.glassAlphas[index]
                    return Layer(name: "sheet-\(index + 1)") { context in
                        AppIconDrawing.litCard(context, rect, fillAlpha: alpha)
                    }
                }
            }
        }
    }

    /// One layer of the icon: a name for its image, and a routine that draws it on a clear,
    /// canvas-sized context with y pointing up.
    public struct Layer: Sendable {
        public let name: String
        public let draw: @Sendable (CGContext) -> Void
    }

    // MARK: Cards

    /// Three cards, back first. Each is 96 px right of and 96 px below the one under it.
    static let cardRects: [CGRect] = (0..<3).map { index in
        let step = CGFloat(index) * 96
        return CGRect(x: 176 + step, y: 368 - step, width: 480, height: 480)
    }
    static let cardAlphas: [CGFloat] = [0.38, 0.66, 1]
    static let glassAlphas: [CGFloat] = [0.14, 0.22, 0.34]

    // MARK: Window stack

    /// Four sheets, back first, all running to one bottom right corner. Each starts 112 px
    /// further right and 80 px lower than the one under it.
    static let stackRects: [CGRect] = (0..<4).map { index in
        let left = 176 + CGFloat(index) * 112
        let top = 848 - CGFloat(index) * 80
        return CGRect(x: left, y: 176, width: 848 - left, height: top - 176)
    }
    static let stackAlphas: [CGFloat] = [0.3, 0.5, 0.74, 1]

    /// A sheet as the app draws one: round at the top leading corner, a little round at the
    /// others. In canvas coordinates, y up, so the top leading corner is at (minX, maxY).
    static func sheetPath(_ rect: CGRect) -> CGPath {
        let big: CGFloat = 88, small: CGFloat = 28
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + small))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - big))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX + big, y: rect.maxY), radius: big)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: small)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: small)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: small)
        path.closeSubpath()
        return path
    }

    // MARK: Drawing

    static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func fill(_ context: CGContext, _ path: CGPath, alpha: CGFloat) {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        context.addPath(path)
        context.fillPath()
    }

    /// A faint card with a bright line along its top and leading edges.
    static func litCard(_ context: CGContext, _ rect: CGRect, fillAlpha: CGFloat) {
        let radius: CGFloat = 72
        fill(context, roundedPath(rect, radius: radius), alpha: fillAlpha)
        let width: CGFloat = 20
        let inner = rect.insetBy(dx: width / 2, dy: width / 2)
        let r = radius - width / 2
        let edge = CGMutablePath()
        edge.move(to: CGPoint(x: inner.minX, y: inner.minY + r))
        edge.addLine(to: CGPoint(x: inner.minX, y: inner.maxY - r))
        edge.addArc(tangent1End: CGPoint(x: inner.minX, y: inner.maxY), tangent2End: CGPoint(x: inner.minX + r, y: inner.maxY), radius: r)
        edge.addLine(to: CGPoint(x: inner.maxX - r, y: inner.maxY))
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.addPath(edge)
        context.strokePath()
    }

    // MARK: Output

    /// Draws one layer on a clear canvas.
    public static func image(of layer: Layer) -> CGImage? {
        let size = Int(canvas)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        layer.draw(context)
        return context.makeImage()
    }

    /// The Icon Composer file's `icon.json` for a design. Each layer gets a group of its own,
    /// front first, so each sheet casts a shadow on the sheets under it.
    public static func iconJSON(for design: Design) -> String {
        func color(_ c: [CGFloat]) -> String {
            "srgb:" + (c + [1]).map { String(format: "%.5f", Double($0)) }.joined(separator: ",")
        }
        let groups = design.layers.map {
            """
                {
                  "layers" : [
                    {
                      "image-name" : "\($0.name).png",
                      "name" : "\($0.name)"
                    }
                  ],
                  "shadow" : {
                    "kind" : "neutral",
                    "opacity" : 0.5
                  },
                  "translucency" : {
                    "enabled" : false,
                    "value" : 0.5
                  }
                }
            """
        }.joined(separator: ",\n")
        return """
        {
          "fill" : {
            "linear-gradient" : [
              "\(color(design.gradient.top))",
              "\(color(design.gradient.bottom))"
            ]
          },
          "groups" : [
        \(groups)
          ],
          "supported-platforms" : {
            "squares" : [
              "macOS"
            ]
          }
        }

        """
    }
}
