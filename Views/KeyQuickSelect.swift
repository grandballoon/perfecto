import SwiftUI

// MARK: – Style selector (stored on PerformanceState)

enum KeyQuickStyle: String, CaseIterable {
    case wheel, swipe
    var label: String {
        switch self {
        case .wheel: return "Radial Wheel"
        case .swipe: return "Swipe Grid"
        }
    }
}

// MARK: – A1: Radial wheel

/// Full-screen overlay. Drag angle → root; push past the outer ring → minor.
/// Release commits. Tap inside the center circle cancels.
struct KeyWheelOverlay: View {
    @Environment(PerformanceState.self) private var state
    @Binding var isPresented: Bool

    @State private var dragRoot:  PitchClass? = nil
    @State private var dragMinor: Bool        = false
    @State private var dragActive: Bool       = false

    private let ringR:  CGFloat = 112  // distance from center to key labels
    private let minorR: CGFloat = 148  // threshold: past here = minor
    private let coreR:  CGFloat =  40  // inner core radius (cancel zone)

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            GeometryReader { geo in
                let cx = geo.size.width  / 2
                let cy = geo.size.height / 2
                ZStack {
                    decorations(cx: cx, cy: cy)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drag(cx: cx, cy: cy))
                }
            }
        }
    }

    // MARK: – Decals

    @ViewBuilder
    private func decorations(cx: CGFloat, cy: CGFloat) -> some View {
        // Outer minor band
        Circle()
            .stroke(
                dragMinor ? Color.orange.opacity(0.55) : Color(white: 0.18),
                style: StrokeStyle(lineWidth: 1, dash: dragMinor ? [] : [5, 5])
            )
            .frame(width: minorR * 2, height: minorR * 2)
            .position(x: cx, y: cy)
            .animation(.easeInOut(duration: 0.12), value: dragMinor)

        // 12 key nodes
        ForEach(Array(PitchClass.allCases.enumerated()), id: \.offset) { i, pc in
            keyNode(pc, index: i, cx: cx, cy: cy)
        }

        // Center core
        let displayRoot  = dragActive ? (dragRoot ?? state.key.root) : state.key.root
        let displayMinor = dragActive ? dragMinor : (state.key.scale == .naturalMinor)
        VStack(spacing: 2) {
            Text(displayRoot.name)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.orange)
            Text(displayMinor ? "minor" : "major")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .kerning(1)
        }
        .frame(width: coreR * 2, height: coreR * 2)
        .background(
            Circle().fill(Color(white: 0.08))
                .overlay(Circle().stroke(Color(white: 0.22), lineWidth: 1))
        )
        .position(x: cx, y: cy)

        // Hint
        Text("drag angle → root  ·  push out → minor  ·  release to set")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Color(white: 0.28))
            .multilineTextAlignment(.center)
            .frame(width: 260)
            .position(x: cx, y: cy + minorR + 36)
    }

    private func keyNode(_ pc: PitchClass, index: Int, cx: CGFloat, cy: CGFloat) -> some View {
        let angle      = Double(index) / 12.0 * 2.0 * .pi - .pi / 2.0
        let x          = cx + cos(angle) * ringR
        let y          = cy + sin(angle) * ringR
        let highlighted = dragActive ? (dragRoot == pc) : (state.key.root == pc)

        return Text(pc.name)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(highlighted ? Color.black : Color(white: 0.75))
            .frame(width: 40, height: 40)
            .background(Circle().fill(highlighted ? Color.orange : Color(white: 0.15)))
            .overlay(Circle().stroke(highlighted ? Color.orange : Color(white: 0.26), lineWidth: 1))
            .scaleEffect(highlighted ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: highlighted)
            .position(x: x, y: y)
    }

    // MARK: – Gesture

    private func drag(cx: CGFloat, cy: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let dx   = v.location.x - cx
                let dy   = v.location.y - cy
                let dist = sqrt(dx*dx + dy*dy)
                dragActive = true
                dragMinor  = dist > minorR * 0.85
                if dist > coreR {
                    var angle = atan2(dy, dx) + .pi / 2
                    if angle < 0 { angle += 2 * .pi }
                    let index = Int((angle / (2 * .pi) * 12).rounded()) % 12
                    dragRoot = PitchClass.allCases[index]
                }
            }
            .onEnded { v in
                let dx   = v.location.x - cx
                let dy   = v.location.y - cy
                let dist = sqrt(dx*dx + dy*dy)
                if dist <= coreR {
                    // tap/drag ended in center → cancel
                    isPresented = false
                } else if let root = dragRoot {
                    state.key = Key(root: root, scale: dragMinor ? .naturalMinor : .major)
                    isPresented = false
                }
                dragActive = false
                dragRoot   = nil
                dragMinor  = false
            }
    }
}

// MARK: – A2: Swipe grid

/// Full-screen overlay. Slide to a key in the 2×6 grid; push past the top or
/// bottom edge of the grid for minor. Release commits.
struct KeySwipeOverlay: View {
    @Environment(PerformanceState.self) private var state
    @Binding var isPresented: Bool

    @State private var dragRoot:   PitchClass? = nil
    @State private var dragMinor:  Bool        = false
    @State private var dragActive: Bool        = false

    // Chromatic order, two rows of six
    private static let grid: [[PitchClass]] = [
        [.C, .Cs, .D, .Ds, .E, .F],
        [.Fs, .G, .Gs, .A, .As, .B],
    ]
    private let cellW:     CGFloat = 50
    private let cellH:     CGFloat = 54
    private let cellGap:   CGFloat =  8
    private let vPad:      CGFloat = 16  // padding inside the grid container
    private let minorPush: CGFloat = 28  // px beyond grid edge to trigger minor

    private var gridW: CGFloat { CGFloat(Self.grid[0].count) * cellW + CGFloat(Self.grid[0].count - 1) * cellGap }
    private var gridH: CGFloat { CGFloat(Self.grid.count)    * cellH + CGFloat(Self.grid.count    - 1) * cellGap }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                Spacer()
                minorEdge(label: "▲  MINOR")
                gridContainer
                minorEdge(label: "▼  MINOR")
                Spacer().frame(height: 120)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: – Subviews

    private var gridContainer: some View {
        VStack(spacing: cellGap) {
            ForEach(0..<Self.grid.count, id: \.self) { row in
                HStack(spacing: cellGap) {
                    ForEach(Self.grid[row], id: \.self) { pc in
                        cell(pc)
                    }
                }
            }
        }
        .padding(vPad)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.07))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(white: 0.18), lineWidth: 1))
        )
        .gesture(swipe)
    }

    private func cell(_ pc: PitchClass) -> some View {
        let highlighted = dragActive ? (dragRoot == pc) : (state.key.root == pc)
        return Text(pc.name)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(highlighted ? Color.black : Color(white: 0.72))
            .frame(width: cellW, height: cellH)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(highlighted ? Color.orange : Color(white: 0.13))
            )
            .scaleEffect(highlighted ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.07), value: highlighted)
    }

    private func minorEdge(label: String) -> some View {
        let active = dragActive && dragMinor
        return Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(active ? Color.orange : Color(white: 0.28))
            .kerning(1.5)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .animation(.easeInOut(duration: 0.1), value: active)
    }

    // MARK: – Gesture

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                dragActive = true
                let x = v.location.x - vPad
                let y = v.location.y - vPad
                dragMinor = y < -minorPush || y > (gridH + minorPush)
                let col = Int((max(0, min(x, gridW - 1)) / (cellW + cellGap)))
                let row = Int((max(0, min(y, gridH - 1)) / (cellH + cellGap)))
                let r = max(0, min(row, Self.grid.count - 1))
                let c = max(0, min(col, Self.grid[r].count - 1))
                dragRoot = Self.grid[r][c]
            }
            .onEnded { _ in
                if let root = dragRoot {
                    state.key = Key(root: root, scale: dragMinor ? .naturalMinor : .major)
                }
                dragActive = false
                dragRoot   = nil
                dragMinor  = false
                isPresented = false
            }
    }
}
