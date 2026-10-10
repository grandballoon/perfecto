import SwiftUI

/// The Tonnetz from above: the net of notes, every triangle of it a triad.
/// A triangle is played by pressing it and sounds while it is held; sliding
/// from one into the next plays that one, so a slide across a side is a
/// move (P, L or R). A note is played by itself by pressing its disc, and
/// sliding from note to note plays a run. It is one pointer for now, as a
/// mouse is; the computer keyboard makes the moves too.
///
/// The net has no end and repeats, so every triad is on screen several
/// times; the one lit is the triangle the Tonnetz is at. A note sounding by
/// itself is lit at every place it has.
struct TonnetzNetView: View {
    @Environment(PerformanceState.self) private var state
    /// Whether the pointer is down, and so moving rather than pressing.
    @State private var isDown = false

    var body: some View {
        let tonnetz = state.tonnetz
        GeometryReader { geo in
            let net = TonnetzNet(size: geo.size, center: tonnetz.netCenter, edge: tonnetz.netEdge)
            ZStack {
                // Drawn again only when the net itself changes, not for
                // every triangle played on it.
                TonnetzNetDrawing(net: net)
                    .equatable()
                TonnetzCurrentCell(net: net)
                TonnetzSoundingNotes(net: net)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        // A pointer that has left the net keeps what it plays.
                        guard CGRect(origin: .zero, size: geo.size).contains(drag.location) else { return }
                        let target = net.target(at: drag.location, noteDiameter: net.noteDiameter)
                        if isDown {
                            tonnetz.pointerMoved(to: target)
                        } else {
                            isDown = true
                            tonnetz.pointerDown(on: target)
                        }
                    }
                    .onEnded { _ in
                        isDown = false
                        tonnetz.pointerUp()
                    }
            )
            .onChange(of: tonnetz.cell) { _, cell in follow(cell, on: net) }
        }
        .clipped()
    }

    /// A move made from the keyboard can lead off the edge of the net, which
    /// is then drawn around where it led.
    private func follow(_ cell: TonnetzCell, on net: TonnetzNet) {
        let bounds = CGRect(origin: .zero, size: net.size)
        if !bounds.contains(net.frame(of: cell)) { state.tonnetz.centerNet() }
    }
}

extension TonnetzNet {
    /// How wide a note's disc is on the net.
    var noteDiameter: CGFloat { (edge * 0.32).clamped(to: 22...36) }
    /// Whether the triangles are large enough to be named.
    var namesTriads: Bool { edge >= 88 }
}

/// The net as it is whatever is played on it: its triangles, the lines
/// between its notes, and their names.
private struct TonnetzNetDrawing: View, Equatable {
    let net: TonnetzNet

    nonisolated static func == (a: TonnetzNetDrawing, b: TonnetzNetDrawing) -> Bool { a.net == b.net }

    var body: some View {
        let cells = net.cells
        let major = cells.filter(\.pointsUp)
        ZStack {
            net.outline(of: cells.filter { !$0.pointsUp }).fill(TonnetzStyle.minor)
            net.outline(of: major).fill(TonnetzStyle.major)
            // Every line is a side of one triangle that points up.
            net.outline(of: major).stroke(TonnetzStyle.line, lineWidth: 1)
            if net.namesTriads {
                ForEach(cells, id: \.self) { cell in
                    Text(cell.triad.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.4))
                        .position(net.middle(of: cell))
                }
            }
            ForEach(net.points, id: \.self) { point in
                TonnetzNote(pitchClass: point.pitchClass, diameter: net.noteDiameter)
                    .position(net.place(of: point))
            }
        }
    }
}

/// The triangle the Tonnetz is at, drawn over the net: tinted, lit while
/// it sounds, with its notes marked.
private struct TonnetzCurrentCell: View {
    let net: TonnetzNet
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let cell = state.tonnetz.cell
        let isSounding = state.tonnetz.isSounding
        ZStack {
            net.outline(of: [cell]).fill(Color.black)
            net.outline(of: [cell]).fill(TonnetzStyle.current(isSounding: isSounding))
            net.outline(of: [cell]).stroke(Color.orange, lineWidth: 1)
            if net.namesTriads {
                Text(cell.triad.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TonnetzStyle.currentText(isSounding: isSounding))
                    .position(net.middle(of: cell))
            }
            ForEach(cell.points, id: \.self) { point in
                TonnetzNote(pitchClass: point.pitchClass, diameter: net.noteDiameter,
                            isCurrent: true, isRoot: point == cell.root)
                    .position(net.place(of: point))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The notes sounding by themselves, drawn over the net: lit at every place
/// each has on it.
private struct TonnetzSoundingNotes: View {
    let net: TonnetzNet
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let tonnetz = state.tonnetz
        ZStack {
            if !tonnetz.notes.isEmpty {
                ForEach(net.points.filter { tonnetz.sounds($0.pitchClass) }, id: \.self) { point in
                    TonnetzNote(pitchClass: point.pitchClass, diameter: net.noteDiameter, isSounding: true)
                        .position(net.place(of: point))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
