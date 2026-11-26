import SheetsCore
import SwiftUI

// The stack of sheets: the sidebar at the bottom, and each open pane as a sheet over its
// parent, 10 pt lower, round at its top leading corner, with a shadow on its leading edge.
//
// A covered sheet keeps its layout. It is only covered, dimmed a little, and still: a strip of
// its leading edge shows, and a click on the strip goes back to it, or opens the row the click
// landed on. Where each sheet sits comes from `SheetStackLayout` in SheetsCore.
//
// Opening a sheet slides it in from the trailing edge, and going back slides it out. Picking
// a sibling of an open pane, another row from the same list, is a swap: the sheet stays, and
// only what is on it changes. Its title bar stays too, and the title fades in place, while the
// content under the bar crossfades with a short move up or down. Which change is which comes
// from `SheetStackChange`, and every duration and distance from `SheetMotion`.
//
// A sheet, a dimming, or a sheet's content that is leaving stops taking clicks as soon as it
// starts to leave. SwiftUI keeps a leaving view in place, on top, until its animation ends,
// so without that a click on a row just after its sheet closed would land on the leaving
// view and do nothing.

/// One sheet of the stack, as the stack asks for its content.
struct SheetLevel: Identifiable {
    /// 0 for the sidebar.
    let depth: Int
    /// The pane this sheet shows, or nil for the sidebar.
    let pane: Pane?
    /// The pane open from this sheet, which its row marks.
    let openedID: PaneID?
    let isCovered: Bool
    /// The panes of the sheets under this one, above the sidebar, joined by `/`.
    let under: String

    /// A sheet is known by its depth and the sheets under it, not by its own pane. A sibling
    /// swapped in at the same depth keeps the sheet and changes what is on it. A sheet over a
    /// different parent is a new sheet, which slides in.
    var id: String { "\(depth)|\(under)" }
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
                openedID: stack.opened(from: depth), isCovered: depth < stack.depth,
                under: stack.prefix(depth - 1).description)
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
                        .transition(level.depth == 0 ? .identity : sheetTransition(width: proxy.size.width))
                        .zIndex(Double(level.depth))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .clipped()
        .background {
            // Escape closes the top sheet. With only the sidebar there is nothing to close, so
            // there is no button and Escape means what it meant before. While a title is being
            // renamed, Escape belongs to the rename, and while a terminal on top runs its shell,
            // to the terminal: shells and programs such as vim need it. Command-[ (Go > Back)
            // closes the top sheet in every case.
            if !stack.isAtSidebar && model.renaming == nil && !model.escapeGoesToTerminal {
                Button("Back") { model.goBack() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A sheet slides in from the trailing edge, or fades in with Reduce Motion on. It leaves
    /// by sliding back out, or by fading when a sheet under it swapped, so the swap reads as
    /// one change.
    private func sheetTransition(width: CGFloat) -> AnyTransition {
        func leaving(_ isActive: Bool) -> SheetLeaving {
            SheetLeaving(model: model, width: width, reduceMotion: reduceMotion, isActive: isActive)
        }
        return .asymmetric(
            insertion: reduceMotion ? .opacity : .move(edge: .trailing),
            removal: .modifier(active: leaving(true), identity: leaving(false)))
    }

    /// A sheet's content coming and going inside the sheet, which only a swap does.
    private func swapTransition(depth: Int) -> AnyTransition {
        func swapping(_ phase: SheetSwapping.Phase) -> SheetSwapping {
            SheetSwapping(model: model, depth: depth, reduceMotion: reduceMotion, phase: phase)
        }
        return .asymmetric(
            insertion: .modifier(active: swapping(.entering), identity: swapping(.identity)),
            removal: .modifier(active: swapping(.leaving), identity: swapping(.identity)))
    }

    @ViewBuilder
    private func sheetView(_ level: SheetLevel) -> some View {
        if level.depth == 0 {
            sheet(level)
                .overlay { CoveredDimming(isCovered: level.isCovered).allowsHitTesting(false) }
        } else {
            // The title bar belongs to the sheet, not to its content, so a swap leaves it where
            // it is and only its words fade. The content under it is known by its pane, so a
            // swap replaces it inside the sheet, which stays.
            VStack(spacing: 0) {
                if let pane = level.pane {
                    PaneTitleBar(model: model, pane: pane)
                }
                ZStack(alignment: .topLeading) {
                    sheet(level)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(level.pane?.id)
                        .transition(swapTransition(depth: level.depth))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Content moving up as it leaves goes under the bar's edge, not over the bar.
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(CoveredSheet(
                isCovered: level.isCovered,
                // Read only while covered, and inside the modifier, so a shell's new title
                // redraws the strip's label and not the whole stack.
                backLabel: { "Back to \(level.pane.map { model.label(for: $0).title } ?? "")" },
                click: { row in model.clickStrip(at: level.depth, on: row) }))
            .modifier(SheetCard(depth: level.depth))
        }
    }
}

// MARK: - Parts a sheet is built from

/// The title bar of a pane's sheet, with what it says worked out from the pane: the same title
/// its row shows. A terminal's shell can set a title while the sheet shows, so it is read here,
/// where only the bar redraws for it. A right click on a group's bar adds a pane to the group,
/// as a right click on the rest of its sheet does.
struct PaneTitleBar: View {
    let model: SheetsModel
    let pane: Pane

    var body: some View {
        let bar = SheetTitleBar(title: SheetTitle(title: model.label(for: pane).title), paneID: pane.id)
        if pane.kind == .group {
            bar.contextMenu { NewPaneMenuItems(model: model, near: pane.id) }
        } else {
            bar
        }
    }
}

/// A sheet's title bar: the pane's title, centered, over a faint line. A long title is cut
/// short in the middle.
///
/// The bar is one height for every pane, `SheetTitle.barHeight`, and it never moves while a
/// swap changes the sheet's content. Its words are known by their pane, so when a swap puts
/// another pane on the sheet, the old words fade out and the new ones fade in, in place, with
/// the swap's own animation. A new title from the same pane, such as one a shell set, simply
/// replaces the old.
struct SheetTitleBar: View {
    let title: SheetTitle
    let paneID: PaneID

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                words
                    .id(paneID)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: SheetTitle.barHeight)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Divider().opacity(0.6)
        }
    }

    private var words: some View {
        Text(title.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// A row in a sheet that opens a pane over it: a title over a smaller, grayer line, and a
/// chevron. The row whose pane is open stays marked while that pane covers it.
struct SheetRow: View {
    let id: PaneID
    let label: PaneLabel
    let isOpen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    PaneSubtitle(label: label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

/// The second line of a pane's row, on one line. A terminal's folder is cut short at its head,
/// so its last folder stays readable, and the count after it always shows whole.
struct PaneSubtitle: View {
    let label: PaneLabel

    var body: some View {
        if let folder = label.folder {
            HStack(spacing: 0) {
                Text(folder)
                    .truncationMode(.head)
                if let detail = label.folderDetail {
                    Text(" · " + detail)
                        .fixedSize()
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        } else {
            Text(label.subtitle)
                .lineLimit(1)
        }
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
    /// The label of the "Back to" button, such as "Back to dev server".
    let backLabel: () -> String
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
                    .accessibilityLabel(Text(backLabel()))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { click(nil) }
                    .transition(.opacity.ignoringClicksWhileLeaving)
                }
            }
    }
}

/// A sheet leaving the stack. Going back slides it out past the trailing edge. When it closes
/// because a sheet under it swapped, or with Reduce Motion on, it fades. Either way it stops
/// taking clicks as soon as it starts to leave.
///
/// The kind of change is read from the model when the sheet leaves, not when it was last
/// drawn, since a sheet cannot know beforehand which change will close it.
private struct SheetLeaving: ViewModifier {
    let model: SheetsModel
    /// The stack's width, which takes the sheet fully past the trailing edge.
    let width: CGFloat
    let reduceMotion: Bool
    let isActive: Bool

    func body(content: Content) -> some View {
        let fades = reduceMotion || model.change.swapDepth != nil
        content
            .opacity(isActive && fades ? 0 : 1)
            .offset(x: isActive && !fades ? width : 0)
            .allowsHitTesting(!isActive)
    }
}

/// A sheet's content, under its title bar, swapping for a sibling's: a crossfade with a short
/// move up or down, by the two panes' order in their list. Only a fade with Reduce Motion on,
/// or when the order is not known. The content leaving stops taking clicks at once.
private struct SheetSwapping: ViewModifier {
    enum Phase { case identity, entering, leaving }

    let model: SheetsModel
    let depth: Int
    let reduceMotion: Bool
    let phase: Phase

    func body(content: Content) -> some View {
        content
            .opacity(phase == .identity ? 1 : 0)
            .offset(y: offset)
            .allowsHitTesting(phase != .leaving)
    }

    private var offset: CGFloat {
        let change = model.change
        guard phase != .identity, !reduceMotion, change.swapDepth == depth,
              let direction = change.swapDirection else { return 0 }
        return direction.offset(entering: phase == .entering)
    }
}

extension AnyTransition {
    /// The same transition, except that a leaving view stops taking clicks as soon as it starts
    /// to leave, rather than when its animation ends.
    var ignoringClicksWhileLeaving: AnyTransition {
        .asymmetric(
            insertion: self,
            removal: combined(with: .modifier(active: IgnoringClicks(isOn: true), identity: IgnoringClicks(isOn: false))))
    }
}

/// Turns hit testing off. As a transition's active state it takes effect as soon as the view
/// starts to leave, since it does not animate.
private struct IgnoringClicks: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content.allowsHitTesting(!isOn)
    }
}
