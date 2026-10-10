import SwiftUI

/// The Tonnetz one triad at a time: the triangle it is at in the middle,
/// and across each of its sides the triangle a move flips it into, named by
/// the move (P, L, R) and the triad it makes. Pressing one of those makes
/// the move and sounds its triad while held; pressing the middle sounds the
/// triad it is at, and pressing a note's disc sounds that note by itself.
///
/// It is the net seen close (`TonnetzNet.around`): a move brings the next
/// triangle to the middle, the two notes the move keeps stay on the side
/// flipped over, and the third gives way to the new one.
struct TonnetzTriadView: View {
    @Environment(PerformanceState.self) private var state
    /// Whether the pointer is down: its press has been made, and where it
    /// goes until it lifts plays nothing more (a move brings another
    /// triangle under it).
    @State private var isDown = false

    var body: some View {
        let tonnetz = state.tonnetz
        let cell = tonnetz.cell
        let shown = [TonnetzFace(cell: cell, move: nil)]
            + TonnetzMove.allCases.map { TonnetzFace(cell: cell.flipped($0), move: $0) }
        GeometryReader { geo in
            let net = TonnetzNet.around(cell, in: geo.size)
            ZStack {
                ForEach(shown) { face in
                    let frame = net.frame(of: face.cell)
                    TonnetzTriangleFace(face: face, isSounding: tonnetz.isSounding,
                                        middle: net.middle(of: face.cell).y - frame.midY)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .zIndex(face.move == nil ? 1 : 0)
                }
                ForEach(Array(Set(shown.flatMap(\.cell.points))), id: \.self) { point in
                    TonnetzNote(pitchClass: point.pitchClass, diameter: net.triadNoteDiameter,
                                isCurrent: cell.points.contains(point), isRoot: point == cell.root,
                                isSounding: tonnetz.sounds(point.pitchClass))
                        .position(net.place(of: point))
                        .zIndex(2)
                }
            }
            .animation(.easeOut(duration: 0.18), value: cell)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !isDown else { return }
                        isDown = true
                        let target = net.target(at: drag.startLocation, noteDiameter: net.triadNoteDiameter)
                        // Only the triangles shown are there to be pressed.
                        if case .cell(let pressed) = target, !shown.contains(where: { $0.cell == pressed }) { return }
                        tonnetz.pointerDown(on: target)
                    }
                    .onEnded { _ in
                        isDown = false
                        tonnetz.pointerUp()
                    }
            )
        }
    }
}

extension TonnetzNet {
    /// How wide a note's disc is where one triad is shown.
    var triadNoteDiameter: CGFloat { (edge * 0.2).clamped(to: 32...64) }
}

/// One of the triangles the triad view shows: the one the Tonnetz is at
/// (`move` nil), or the one `move` flips it into.
private struct TonnetzFace: Identifiable {
    let cell: TonnetzCell
    let move: TonnetzMove?

    /// A triangle is the same one when a move brings it to the middle, so
    /// it is seen to go there.
    var id: TonnetzCell { cell }
}

/// A triangle of the triad view, in a frame that is the rectangle around
/// it, with its name `middle` below the frame's centre.
private struct TonnetzTriangleFace: View {
    let face: TonnetzFace
    let isSounding: Bool
    let middle: CGFloat

    var body: some View {
        let triangle = TonnetzTriangle(pointsUp: face.cell.pointsUp)
        ZStack {
            if face.move == nil {
                triangle.fill(Color.black)
                triangle.fill(TonnetzStyle.current(isSounding: isSounding))
                triangle.stroke(Color.orange, lineWidth: 1.5)
            } else {
                triangle.fill(TonnetzStyle.fill(of: face.cell))
                triangle.stroke(TonnetzStyle.line, lineWidth: 1)
            }
            label.offset(y: middle)
        }
    }

    @ViewBuilder
    private var label: some View {
        let name = face.cell.triad.name
        if let move = face.move {
            VStack(spacing: 4) {
                Text(move.symbol)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.orange)
                Text(name)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.7))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(move.displayName): \(name)")
        } else {
            Text(name)
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .foregroundStyle(TonnetzStyle.currentText(isSounding: isSounding))
        }
    }
}

/// A triangle with all sides alike, filling its frame's width, point up or down.
private struct TonnetzTriangle: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines([
                CGPoint(x: rect.midX, y: pointsUp ? rect.minY : rect.maxY),
                CGPoint(x: rect.maxX, y: pointsUp ? rect.maxY : rect.minY),
                CGPoint(x: rect.minX, y: pointsUp ? rect.maxY : rect.minY),
            ])
            path.closeSubpath()
        }
    }
}
