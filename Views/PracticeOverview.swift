import SwiftUI

/// The whole score as one bar: the runs shown laid along it where they
/// are in the score (the chosen ones brighter), and a line where it is
/// playing or the playhead stands, with the time either side.
///
/// A tap or a drag on the bar brings the playhead there, the keys lit as
/// they are at each moment passed. Play stops while the bar is dragged and
/// goes on from where it is let go, if it was playing.
struct PracticeOverview: View {
    @Environment(PerformanceState.self) private var state

    private static let height: CGFloat = 36

    /// While the bar is dragged, whether it was playing.
    @State private var wasPlaying: Bool?

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
                            .onChanged { drag in
                                if wasPlaying == nil {
                                    wasPlaying = practice.isPlaying
                                    practice.stop()
                                }
                                practice.seek(to: Double(drag.location.x / max(width, 1)) * length)
                            }
                            .onEnded { _ in
                                if wasPlaying == true { practice.play() }
                                wasPlaying = nil
                            })
                }
                time(length)
            }
        }
        .frame(height: Self.height)
    }

    private func bar(length: Double, now: Double, size: CGSize) -> some View {
        let practice = state.practice
        let color = practice.hand.color
        let runs = practice.shownRuns.enumerated().compactMap { i, run in
            practice.span(of: run.id).map { (i, practice.selection.contains(run.id), $0) }
        }
        return Canvas { context, size in
            let x = { (t: Double) in CGFloat(min(max(t / length, 0), 1)) * size.width }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8),
                         with: .color(Color(white: 0.07)))
            for (i, isChosen, span) in runs {
                let rect = CGRect(x: x(span.lowerBound), y: 0,
                                  width: max(2, x(span.upperBound) - x(span.lowerBound)), height: size.height)
                context.fill(Path(rect), with: .color(color.opacity(isChosen ? 0.45 : (i.isMultiple(of: 2) ? 0.15 : 0.25))))
                if i > 0 {
                    context.fill(Path(CGRect(x: rect.minX - 0.5, y: 0, width: 1, height: size.height)),
                                 with: .color(color.opacity(0.6)))
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
        .help("The whole score, with the runs shown along it: tap or drag to move the playhead")
    }

    private func time(_ seconds: Double) -> some View {
        Text(PracticeTime.text(seconds))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.7))
            .fixedSize()
    }
}
