import SwiftUI

/// The whole score as one bar: the runs shown laid along it where they
/// are in the score (the chosen ones brighter), runs that overlap in lanes
/// one above another, and a line where it is playing or the playhead
/// stands, with the time either side.
///
/// A tap or a drag on the bar brings the playhead there, the keys lit as
/// they are at each moment passed. Play stops while the bar is dragged and
/// goes on from where it is let go, if it was playing. While a run is being
/// edited, a drag that begins on it moves it along the score instead, a
/// step at a time, keeping its length.
struct PracticeOverview: View {
    @Environment(PerformanceState.self) private var state

    private static let height: CGFloat = 36

    /// What a drag on the bar is doing, from where it began.
    private enum Drag {
        /// Moving the playhead; whether it was playing.
        case seeking(wasPlaying: Bool)
        /// Moving the run being edited, held this many seconds after its start.
        case moving(grip: Double)
    }

    @State private var drag: Drag?

    /// How far beside the run being edited a drag still takes hold of it.
    private static let reach: CGFloat = 12

    var body: some View {
        let practice = state.practice
        let length = max(practice.length ?? 0, 0.1)
        TimelineView(.animation(paused: !practice.isPlaying)) { _ in
            let now = practice.currentTime
            HStack(spacing: 10) {
                time(now)
                GeometryReader { geo in
                    let width = geo.size.width
                    bar(length: length, now: now, size: geo.size)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { change in
                                let time = { (x: CGFloat) in Double(x / max(width, 1)) * length }
                                if drag == nil {
                                    drag = begin(at: change.startLocation.x, width: width, length: length)
                                }
                                switch drag {
                                case let .moving(grip):
                                    practice.moveDraft(toStartAt: time(change.location.x) - grip)
                                case .seeking:
                                    practice.seek(to: time(change.location.x))
                                case nil:
                                    break
                                }
                            }
                            .onEnded { _ in
                                if case .seeking(wasPlaying: true) = drag { practice.play() }
                                drag = nil
                            })
                }
                time(length)
            }
        }
        .frame(height: Self.height)
    }

    /// What a drag that begins at `x` does: takes hold of the run being
    /// edited if it begins on it, or else moves the playhead.
    private func begin(at x: CGFloat, width: CGFloat, length: Double) -> Drag {
        let practice = state.practice
        if let score = practice.score, let draft = practice.draft {
            let span = draft.span(in: score)
            let from = CGFloat(span.lowerBound / length) * width
            let to = CGFloat(span.upperBound / length) * width
            if x >= from - Self.reach, x <= to + Self.reach {
                return .moving(grip: Double(x / max(width, 1)) * length - span.lowerBound)
            }
        }
        let was = practice.isPlaying
        practice.stop()
        return .seeking(wasPlaying: was)
    }

    private func bar(length: Double, now: Double, size: CGSize) -> some View {
        let practice = state.practice
        let color = practice.hands.color
        let runs = practice.shownRuns.filter { $0.id != practice.editing }.compactMap { run in
            practice.span(of: run).map { (practice.selection.contains(run.id), $0) }
        }
        let lanes = Practice.lanes(of: runs.map(\.1))
        let laneCount = max(1, (lanes.max() ?? 0) + 1)
        let draft = practice.score.flatMap { score in practice.draft.map { $0.span(in: score) } }
        return Canvas { context, size in
            let x = { (t: Double) in CGFloat(min(max(t / length, 0), 1)) * size.width }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8),
                         with: .color(Color(white: 0.07)))
            let laneHeight = size.height / CGFloat(laneCount)
            for ((isChosen, span), lane) in zip(runs, lanes) {
                let rect = CGRect(x: x(span.lowerBound), y: CGFloat(lane) * laneHeight,
                                  width: max(2, x(span.upperBound) - x(span.lowerBound)), height: laneHeight)
                    .insetBy(dx: 0.5, dy: laneCount > 1 ? 0.5 : 0)
                // While a run is edited, the others wait in the background.
                let opacity = draft != nil ? 0.12 : (isChosen ? 0.55 : 0.2)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(opacity)))
            }
            if let draft {
                // The run being edited, with grips at its ends to say it moves.
                let rect = CGRect(x: x(draft.lowerBound), y: 0,
                                  width: max(6, x(draft.upperBound) - x(draft.lowerBound)), height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color.opacity(0.45)))
                context.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 3),
                               with: .color(color), lineWidth: 2)
                for edge in [rect.minX + 4, rect.maxX - 4] where rect.width > 14 {
                    context.fill(Path(roundedRect: CGRect(x: edge - 1, y: size.height * 0.3, width: 2,
                                                          height: size.height * 0.4), cornerRadius: 1),
                                 with: .color(.black.opacity(0.5)))
                }
            }
            context.fill(Path(CGRect(x: x(now) - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.white))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score position")
        .accessibilityValue("\(PracticeTime.text(now)) of \(PracticeTime.text(length))")
        .accessibilityAdjustableAction { direction in
            practice.skip(by: direction == .increment ? ScorePracticeState.skipSeconds : -ScorePracticeState.skipSeconds)
        }
        .help(practice.isEditing
              ? "Drag the run being edited along the score; tap or drag elsewhere to move the playhead"
              : "The whole score, with the runs shown along it: tap or drag to move the playhead")
    }

    private func time(_ seconds: Double) -> some View {
        Text(PracticeTime.text(seconds))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.7))
            .fixedSize()
    }
}
