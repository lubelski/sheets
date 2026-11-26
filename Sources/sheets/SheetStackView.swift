import SheetsCore
import SwiftUI

// The stack of sheets: the sidebar at the bottom, and each open pane as a sheet over its
// parent, 10 pt lower, round at its top leading corner, with a shadow on its leading edge.
//
// A covered sheet keeps its layout. It is only covered, dimmed a little, and still: a strip of
// its leading edge shows, and a click on the strip goes back to it, or opens the row the click
// landed on. Where each sheet sits comes from `SheetStackLayout` in SheetsCore.

/// One sheet of the stack, as the stack asks for its content.
struct SheetLevel: Identifiable {
    /// 0 for the sidebar.
    let depth: Int
    /// The pane this sheet shows, or nil for the sidebar.
    let pane: Pane?
    /// The pane open from this sheet, which its row marks.
    let openedID: PaneID?
    let isCovered: Bool

    /// A sheet is known by its depth and its pane, so a different pane at the same depth is a
    /// new sheet that slides in, not the old one redrawn.
    var id: String { "\(depth)|\(pane?.id.rawValue ?? "")" }
}

/// Draws the stack. See the top of this file.
struct SheetStackView<Sheet: View>: View {
    let model: SheetsModel
    @ViewBuilder let sheet: (SheetLevel) -> Sheet

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stack = model.stack
        let levels = (0...stack.depth).map { depth in
            SheetLevel(
                depth: depth, pane: stack.entry(at: depth).flatMap(model.tree.pane),
                openedID: stack.opened(from: depth), isCovered: depth < stack.depth)
        }
        GeometryReader { proxy in
            let widths = SheetStackLayout.stripWidths(depth: stack.depth, available: proxy.size.width)
            let frames = SheetStackLayout.frames(stripWidths: widths, in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                ForEach(levels) { level in
                    let frame = frames[level.depth]
                    sheetView(level)
                        .frame(width: frame.width, height: frame.height)
                        .padding(.leading, frame.minX)
                        .padding(.top, frame.minY)
                        .transition(level.depth == 0 ? .identity : slide)
                        .zIndex(Double(level.depth))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .clipped()
        .background {
            // Escape closes the top sheet. With only the sidebar there is nothing to close, so
            // there is no button and Escape means what it meant before.
            if !stack.isAtSidebar {
                Button("Back") { model.goBack() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A short slide in from the trailing edge and back out, or a fade with Reduce Motion on.
    private var slide: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing)
    }

    @ViewBuilder
    private func sheetView(_ level: SheetLevel) -> some View {
        if level.depth == 0 {
            sheet(level)
                .overlay { CoveredDimming(isCovered: level.isCovered).allowsHitTesting(false) }
        } else {
            sheet(level)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .modifier(CoveredSheet(
                    isCovered: level.isCovered,
                    backLabel: "Back to \(level.pane?.title ?? "")",
                    click: { row in model.clickStrip(at: level.depth, on: row) }))
                .modifier(SheetCard(depth: level.depth))
        }
    }
}

// MARK: - Parts a sheet is built from

/// A sheet's title bar: the pane's name, centered, over a faint line.
struct SheetTitleBar: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            Divider().opacity(0.6)
        }
    }
}

/// A row in a sheet that opens a pane over it: a title over a smaller, grayer line, and a
/// chevron. The row whose pane is open stays marked while that pane covers it.
struct SheetRow: View {
    let id: PaneID
    let title: String
    let summary: String
    let isOpen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background { RowSelection(isSelected: isOpen) }
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .anchorPreference(key: SheetRowAnchors.self, value: .bounds) { [id: $0] }
    }
}

/// The mark on a selected row: a fill across the whole width of its sheet, edge to edge.
struct RowSelection: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Rectangle().fill(Color.accentColor.opacity(0.22))
        }
    }
}

/// Where each row of a sheet is, so a click on a covered strip can tell which row it hit.
struct SheetRowAnchors: PreferenceKey {
    static let defaultValue: [PaneID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [PaneID: Anchor<CGRect>], nextValue: () -> [PaneID: Anchor<CGRect>]) {
        value.merge(nextValue()) { first, _ in first }
    }
}

// MARK: - The stack's own parts

/// The line along a sheet's top and leading edges, round at the top leading corner.
struct SheetEdge: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// A raised sheet: a surface a little lighter than the one under it, round at the top leading
/// corner and square at the others, with a shadow on its leading edge. In dark mode a faint
/// light runs along its top and leading edge, as if lit from above.
struct SheetCard: ViewModifier {
    static let cornerRadius: CGFloat = 12

    let depth: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        // Each sheet lifts toward white, a little in dark mode and more in light mode, where
        // the window's gray is already light. It stops lifting after a few sheets.
        let lift = Double(min(depth, 4))
        let hairline = 1 / displayScale
        content
            .background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Color.white.opacity(dark ? 0.045 * lift : min(0.4 * lift, 0.85))
                }
            }
            .overlay {
                if dark {
                    // The lit edge: a hairline and a soft glow just inside it, both faint.
                    ZStack {
                        SheetEdge(radius: Self.cornerRadius)
                            .stroke(Color.white.opacity(0.05), lineWidth: 6)
                            .blur(radius: 3)
                        SheetEdge(radius: Self.cornerRadius)
                            .offset(x: hairline / 2, y: hairline / 2)
                            .stroke(Color.white.opacity(0.14), lineWidth: hairline)
                    }
                    .allowsHitTesting(false)
                } else {
                    SheetEdge(radius: Self.cornerRadius)
                        .offset(x: hairline / 2, y: hairline / 2)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: hairline)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(dark ? 0.45 : 0.14), radius: 10, x: -4, y: 0)
    }
}

/// The slight dimming over a covered sheet.
struct CoveredDimming: View {
    let isCovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isCovered {
            Rectangle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06))
                .transition(.opacity)
        }
    }
}

/// A sheet under another: dimmed, still, and hidden from accessibility apart from a "Back to"
/// button. A click on its strip goes back to it, or opens another of its rows instead.
struct CoveredSheet: ViewModifier {
    let isCovered: Bool
    let backLabel: String
    /// Called with the row the click landed on, if any.
    let click: (PaneID?) -> Void

    func body(content: Content) -> some View {
        content
            .scrollDisabled(isCovered)
            .allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
            .overlayPreferenceValue(SheetRowAnchors.self) { anchors in
                if isCovered {
                    GeometryReader { proxy in
                        CoveredDimming(isCovered: true)
                            .contentShape(.rect)
                            .gesture(SpatialTapGesture().onEnded { tap in
                                click(anchors.first { proxy[$0.value].contains(tap.location) }?.key)
                            })
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text(backLabel))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { click(nil) }
                }
            }
    }
}
