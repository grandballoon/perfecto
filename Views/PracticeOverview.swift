import SwiftUI

/// The whole recording as one bar, with the stretch the timelines show
/// drawn as a box on it: the recording's outline, the run in focus shaded
/// where it is heard, the nudge points marked (tagged, orange; doubted by
/// the match, yellow), and a tick where the recording is playing or stands.
///
/// A tap or a drag on the bar moves the box there, which moves the
/// timelines but not the playhead. The zoom buttons beside it bring the
/// timelines closer or farther about the playhead.
struct PracticeOverview: View {
    @Environment(PerformanceState.self) private var state

    private static let height: CGFloat = 28
    /// How much closer or farther one press of a zoom button brings the
    /// timelines.
    private static let zoomStep = 2.0

    var body: some View {
        let practice = state.practice
        let length = max(practice.recordingLength ?? 0, RecordingWindow.shortest)
        TimelineView(.animation(paused: practice.listening == nil)) { _ in
            let now = practice.currentTime
            HStack(spacing: 8) {
                time(now)
                GeometryReader { geo in
                    let width = geo.size.width
                    bar(length: length, now: now, size: geo.size)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { drag in moveWindow(to: Double(drag.location.x / width) * length) })
                }
                time(length)
                zoomButton(out: true)
                zoomButton(out: false)
            }
        }
        .frame(height: Self.height)
    }

    private func bar(length: Double, now: Double, size: CGSize) -> some View {
        let practice = state.practice
        let window = practice.shownWindow(at: now)
        let peaks = practice.peaks
        let perSecond = Double(ScorePracticeState.peaksPerSecond)
        let focus = practice.focus.flatMap(practice.span(of:))
        let color = practice.hand.color
        let tagged = practice.practice?.nudges ?? []
        let doubted = practice.practice?.unsure ?? []
        return Canvas { context, size in
            let x = { (t: Double) in CGFloat(min(max(t / length, 0), 1)) * size.width }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                         with: .color(Color(white: 0.07)))
            if let focus {
                context.fill(Path(CGRect(x: x(focus.lowerBound), y: 0,
                                         width: max(2, x(focus.upperBound) - x(focus.lowerBound)),
                                         height: size.height)),
                             with: .color(color.opacity(0.25)))
            }
            if !peaks.isEmpty {
                var path = Path()
                let columns = Int(size.width)
                for column in 0..<columns {
                    let from = Double(column) / Double(columns) * length
                    let to = Double(column + 1) / Double(columns) * length
                    let low = max(0, Int(from * perSecond)), high = max(low + 1, Int(to * perSecond))
                    guard low < peaks.count else { break }
                    let peak = peaks[low..<min(high, peaks.count)].max() ?? 0
                    let half = max(0.5, CGFloat(min(peak, 1)) * (size.height / 2 - 3))
                    path.addRect(CGRect(x: CGFloat(column), y: size.height / 2 - half, width: 1, height: half * 2))
                }
                context.fill(path, with: .color(Color(white: 0.4)))
            }
            for t in doubted {
                context.fill(Path(CGRect(x: x(t) - 0.5, y: size.height - 8, width: 1, height: 8)),
                             with: .color(PracticeTimelines.doubtColor))
            }
            for t in tagged {
                context.fill(Path(CGRect(x: x(t) - 0.75, y: 0, width: 1.5, height: size.height)),
                             with: .color(PracticeTimelines.tagColor))
            }
            if let window {
                let box = CGRect(x: x(window.start), y: 0.75,
                                 width: max(4, x(window.end) - x(window.start)), height: size.height - 1.5)
                context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.white.opacity(0.08)))
                context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
            }
            context.fill(Path(CGRect(x: x(now) - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.white))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Whole recording")
        .accessibilityValue("\(PracticeTime.text(now)) of \(PracticeTime.text(length))")
        .help("The whole recording, with the stretch shown above boxed: tap or drag to show another stretch")
    }

    /// The timelines' box centred on `time`.
    private func moveWindow(to time: Double) {
        let practice = state.practice
        guard let length = practice.recordingLength,
              let window = practice.shownWindow(at: practice.currentTime) else { return }
        practice.showWindow(window.centred(on: time, in: length))
    }

    private func zoomButton(out: Bool) -> some View {
        Button { state.practice.zoom(by: out ? 1 / Self.zoomStep : Self.zoomStep) } label: {
            Image(systemName: out ? "minus.magnifyingglass" : "plus.magnifyingglass").practiceChit()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(out ? "Zoom out" : "Zoom in")
        .help(out ? "Show more of the recording above" : "Bring the recording above closer")
    }

    private func time(_ seconds: Double) -> some View {
        Text(PracticeTime.text(seconds))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.7))
            .fixedSize()
    }
}
