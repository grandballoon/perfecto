import SwiftUI
import UIKit

/// Which on-screen quick key-selector gesture is active.
/// Two candidates are shipped side by side so they can be compared on-device
/// (switch in Settings). Once one wins, the other is deleted.
enum KeyQuickStyle: String, CaseIterable, Hashable, Sendable {
    case wheel   // A1 — radial ring, blooms centered on the KEY button
    case swipe   // A2 — GBoard-style chromatic strip

    var label: String {
        switch self {
        case .wheel: return "Wheel (A1)"
        case .swipe: return "Swipe (A2)"
        }
    }
}

/// Shared geometry for the overlay view and the gesture math, so the picture
/// the user sees and the zone their finger is in never drift apart.
enum KeyQuickMetrics {
    static let wheelRadius:   CGFloat = 118   // outer (Minor) band
    static let ringRadius:    CGFloat = 82    // where the 12 root labels sit
    static let deadzone:      CGFloat = 26    // release here on the wheel = cancel
    static let majorMaxDist:  CGFloat = 92    // inner band = Major, beyond = Minor

    // swipe (A2): a 2×6 chromatic grid centered on the anchor.
    // Push past the top edge (top row) or bottom edge (bottom row) = minor.
    static let kbCellW: CGFloat = 36
    static let kbCellH: CGFloat = 46
    static let kbGapX:  CGFloat = 6
    static let kbGapY:  CGFloat = 12

    /// Distance from the anchor (grid centre) out to a row's outer edge — cross it to go minor.
    static var kbMinorThreshold: CGFloat { kbCellH + kbGapY / 2 }
    static var kbGridWidth:      CGFloat { 6 * kbCellW + 5 * kbGapX }
}

/// Transient state for the press-and-hold key selector. The gesture lives on the
/// KEY button (see `PerformanceView`); this only holds what's being selected and
/// the anchor point the overlay blooms from — all in the `"perf"` coordinate space.
@MainActor
@Observable
final class KeyQuickController {
    private(set) var isActive   = false
    private(set) var style: KeyQuickStyle = .wheel
    private(set) var anchor: CGPoint = .zero
    private(set) var root: PitchClass = .C
    private(set) var major = true
    private(set) var inDeadzone = true

    private let bump = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)

    func begin(at anchor: CGPoint, key: Key, style: KeyQuickStyle) {
        self.anchor     = anchor
        self.style      = style
        self.root       = key.root
        self.major      = Self.isMajorish(key.scale)
        self.inDeadzone = (style == .wheel)   // swipe has no cancel zone
        self.isActive   = true
        bump.prepare(); soft.prepare()
        soft.impactOccurred(intensity: 0.5)
    }

    func update(location: CGPoint) {
        switch style {
        case .wheel: updateWheel(location)
        case .swipe: updateSwipe(location)
        }
    }

    /// Commit; returns the new key, or nil when the gesture should be a no-op
    /// (wheel released in the dead centre).
    func end() -> Key? {
        isActive = false
        guard !inDeadzone else { return nil }
        soft.impactOccurred(intensity: 0.5)
        return Key(root: root, scale: major ? .major : .naturalMinor)
    }

    // MARK: – Zone math

    private func updateWheel(_ loc: CGPoint) {
        let dx = loc.x - anchor.x, dy = loc.y - anchor.y
        let dist = hypot(dx, dy)

        if dist < KeyQuickMetrics.deadzone {
            if !inDeadzone { inDeadzone = true; soft.impactOccurred(intensity: 0.4) }
            return
        }
        let leftDeadzone = inDeadzone
        inDeadzone = false

        // 0° at 12 o'clock, increasing clockwise → root index
        let deg = atan2(dy, dx) * 180 / .pi
        let a   = (deg + 90).truncatingRemainder(dividingBy: 360)
        let idx = Int((((a < 0 ? a + 360 : a) / 30).rounded())) % 12
        let newRoot  = PitchClass(rawValue: idx) ?? .C
        let newMajor = dist < KeyQuickMetrics.majorMaxDist

        if leftDeadzone || newRoot != root || newMajor != major {
            root = newRoot; major = newMajor
            bump.impactOccurred()
        }
    }

    private func updateSwipe(_ loc: CGPoint) {
        let gridW = KeyQuickMetrics.kbGridWidth
        let left  = anchor.x - gridW / 2
        let col   = min(5, max(0, Int((loc.x - left) / (KeyQuickMetrics.kbCellW + KeyQuickMetrics.kbGapX))))

        let dy = loc.y - anchor.y
        let threshold = KeyQuickMetrics.kbMinorThreshold
        let row: Int
        let minor: Bool
        if dy < -threshold      { row = 0; minor = true }    // pushed above the top row
        else if dy > threshold  { row = 1; minor = true }    // pushed below the bottom row
        else                    { row = dy < 0 ? 0 : 1; minor = false }

        let newRoot  = PitchClass(rawValue: row * 6 + col) ?? .C
        let newMajor = !minor
        if newRoot != root || newMajor != major {
            root = newRoot; major = newMajor
            bump.impactOccurred()
        }
    }

    static func isMajorish(_ scale: ScaleType) -> Bool {
        switch scale {
        case .naturalMinor, .harmonicMinor, .melodicMinor, .minorPentatonic:
            return false
        default:
            return true
        }
    }
}

/// The dimmed overlay that renders whichever selector is active, positioned so it
/// blooms centered on the anchor (the KEY button). Purely visual — the driving
/// gesture is captured by the KEY button, so this never needs to hit-test.
struct KeyQuickSelectOverlay: View {
    let controller: KeyQuickController

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            content
                .position(controller.anchor)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.style {
        case .wheel: wheel
        case .swipe: swipe
        }
    }

    // MARK: – A1 · radial wheel

    private var wheel: some View {
        let R    = KeyQuickMetrics.wheelRadius
        let ring = KeyQuickMetrics.ringRadius

        return ZStack {
            Circle()                                   // outer (Minor) band
                .stroke(Color(white: 0.22), lineWidth: 1)
                .frame(width: R * 2, height: R * 2)
            Circle()                                   // inner (Major) disc
                .fill(Color(white: 0.06))
                .overlay(Circle().stroke(Color(white: 0.16), lineWidth: 1))
                .frame(width: KeyQuickMetrics.majorMaxDist * 2,
                       height: KeyQuickMetrics.majorMaxDist * 2)

            if !controller.inDeadzone {                // selection highlight
                Circle()
                    .fill(Color.orange)
                    .frame(width: 36, height: 36)
                    .shadow(color: .orange.opacity(0.5), radius: 6)
                    .position(labelPoint(controller.root.rawValue, R: R, ring: ring))
            }

            ForEach(PitchClass.allCases) { pc in       // 12 root labels
                Text(pc.name)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(!controller.inDeadzone && pc == controller.root
                                     ? Color.black : Color(white: 0.6))
                    .position(labelPoint(pc.rawValue, R: R, ring: ring))
            }

            VStack(spacing: 6) {                       // core readout
                Text(controller.root.name)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(controller.inDeadzone ? "—" : (controller.major ? "MAJOR" : "MINOR"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
                    .kerning(1)
            }
            .frame(width: 112, height: 112)
            .background(Circle().fill(Color(white: 0.03)))
        }
        .frame(width: R * 2, height: R * 2)
    }

    private func labelPoint(_ i: Int, R: CGFloat, ring: CGFloat) -> CGPoint {
        let ang = Double(-90 + i * 30) * .pi / 180
        return CGPoint(x: R + ring * CGFloat(cos(ang)),
                       y: R + ring * CGFloat(sin(ang)))
    }

    // MARK: – A2 · swipe strip

    private var swipe: some View {
        let minorTop = !controller.major && controller.root.rawValue < 6
        let minorBot = !controller.major && controller.root.rawValue >= 6

        return VStack(spacing: KeyQuickMetrics.kbGapY) {
            overshootHint("▲ push up = minor", active: minorTop)   // symmetric so the grid
            gridRow(0)                                             // stays centered on the finger
            gridRow(1)
            overshootHint("▼ push down = minor", active: minorBot)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16)
            .fill(Color(white: 0.04))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.18), lineWidth: 1)))
    }

    private func gridRow(_ row: Int) -> some View {
        HStack(spacing: KeyQuickMetrics.kbGapX) {
            ForEach(0..<6, id: \.self) { col in
                let pc = PitchClass(rawValue: row * 6 + col) ?? .C
                let isSel = pc == controller.root
                Text(pc.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSel ? (controller.major ? .black : Color.orange)
                                           : Color(white: 0.6))
                    .frame(width: KeyQuickMetrics.kbCellW, height: KeyQuickMetrics.kbCellH)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(isSel && controller.major ? Color.orange : Color(white: 0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.orange, lineWidth: isSel && !controller.major ? 2 : 0))
            }
        }
    }

    private func overshootHint(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(active ? Color.orange : Color(white: 0.28))
            .kerning(1)
            .frame(height: 16)
    }
}
