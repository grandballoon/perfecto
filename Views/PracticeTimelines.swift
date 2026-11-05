import SwiftUI

/// The two timelines under the practice screen's piano, on one stretch of
/// the recording (`ScorePracticeState.shownWindow`): the recording's
/// outline above, with the runs shown, the nudge points, the playhead and a
/// guide at the chosen note; and below it the score's notes where the
/// recording has them, as a piano roll, the hand shown in its color and the
/// other dim.
///
/// A drag on either pans them, unless it starts on the chosen note in the
/// notes lane, which moves that note to where it is heard
/// (`moveSelected`); which of the two it is is decided once, as it starts.
/// A tap on the outline stands the recording there; a tap on a note
/// chooses its step, and on no note stands the recording there. A pinch
/// zooms about the point under the fingers.
struct PracticeTimelines: View {
    @Environment(PerformanceState.self) private var state

    /// What a drag in progress does, decided when it starts.
    private enum Drag {
        /// Moved too little yet to be anything but a tap.
        case undecided
        case pan(from: RecordingWindow)
        case move
    }

    @State private var drag: Drag?
    /// The window as a pinch began.
    @State private var pinchFrom: RecordingWindow?

    private static let waveHeight: CGFloat = 52
    private static let notesHeight: CGFloat = 84
    private static let gap: CGFloat = 4
    /// How far a finger goes before a drag is a drag and not a tap.
    private static let slop: CGFloat = 4
    /// How near the chosen note a drag must start to take hold of it, and
    /// a tap to choose a note, in points.
    private static let reach: CGFloat = 12

    static let tagColor = Color.orange
    static let doubtColor = Color.yellow.opacity(0.7)

    var body: some View {
        let practice = state.practice
        TimelineView(.animation(paused: practice.listening == nil)) { _ in
            let now = practice.currentTime
            if let window = practice.shownWindow(at: now) {
                GeometryReader { geo in
                    let width = geo.size.width
                    VStack(spacing: Self.gap) {
                        lane(window: window, width: width, isNotes: false) {
                            waveLane(window: window, size: CGSize(width: width, height: Self.waveHeight), now: now)
                        }
                        .frame(height: Self.waveHeight)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recording")
                        .accessibilityValue(PracticeTime.text(now))
                        .help("The recording: tap to stand the playhead there, drag to move along it, pinch to zoom")

                        lane(window: window, width: width, isNotes: true) {
                            notesLane(window: window, size: CGSize(width: width, height: Self.notesHeight), now: now)
                        }
                        .frame(height: Self.notesHeight)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Notes")
                        .help("The score's notes where the recording has them: tap a note to choose it, drag the chosen note to where it is heard, drag elsewhere to move along")
                    }
                }
                .frame(height: Self.waveHeight + Self.gap + Self.notesHeight)
                .simultaneousGesture(pinch(window: window))
            }
        }
    }

    // MARK: – Gestures

    /// A lane's face with its drag and tap.
    private func lane<Content: View>(window: RecordingWindow, width: CGFloat, isNotes: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.07))
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in dragged(value, window: window, width: width, isNotes: isNotes) }
            .onEnded { value in ended(value, window: window, width: width, isNotes: isNotes) })
    }

    private func dragged(_ value: DragGesture.Value, window: RecordingWindow, width: CGFloat, isNotes: Bool) {
        let practice = state.practice
        if drag == nil { drag = .undecided }
        if case .undecided = drag {
            guard abs(value.translation.width) >= Self.slop || abs(value.translation.height) >= Self.slop else { return }
            let onChosen = isNotes && practice.selectedTime.map {
                abs(x(of: $0, in: window, width: width) - value.startLocation.x) <= Self.reach
            } == true
            drag = onChosen ? .move : .pan(from: window)
        }
        switch drag {
        case .pan(let from)?:
            guard let length = practice.recordingLength else { return }
            let seconds = -Double(value.translation.width / width) * from.length
            practice.showWindow(from.panned(by: seconds, in: length))
        case .move?:
            practice.moveSelected(to: time(at: value.location.x, in: window, width: width), isDone: false)
        default:
            break
        }
    }

    private func ended(_ value: DragGesture.Value, window: RecordingWindow, width: CGFloat, isNotes: Bool) {
        let practice = state.practice
        defer { drag = nil }
        switch drag {
        case .move?:
            practice.moveSelected(to: time(at: value.location.x, in: window, width: width), isDone: true)
        case .pan?:
            break
        default:
            let t = time(at: value.location.x, in: window, width: width)
            if isNotes {
                practice.tapNotes(at: t, within: Double(Self.reach / width) * window.length)
            } else {
                practice.seek(to: t)
            }
        }
    }

    private func pinch(window: RecordingWindow) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let practice = state.practice
                guard let length = practice.recordingLength else { return }
                let from = pinchFrom ?? window
                if pinchFrom == nil { pinchFrom = window }
                let about = from.time(at: Double(value.startAnchor.x))
                practice.showWindow(from.zoomed(by: value.magnification, around: about, in: length))
            }
            .onEnded { _ in pinchFrom = nil }
    }

    private func x(of time: Double, in window: RecordingWindow, width: CGFloat) -> CGFloat {
        CGFloat(window.share(of: time)) * width
    }

    private func time(at x: CGFloat, in window: RecordingWindow, width: CGFloat) -> Double {
        window.time(at: Double(x / max(width, 1)))
    }

    // MARK: – The recording

    private func waveLane(window: RecordingWindow, size: CGSize, now: Double) -> some View {
        let practice = state.practice
        let color = practice.hand.color
        let tagged = practice.practice?.nudges ?? []
        let doubted = practice.practice?.unsure ?? []
        let runs = practice.shownRuns.enumerated().compactMap { i, run in
            practice.span(of: run.id).map { (i, run, $0) }
        }
        let peaks = practice.peaks
        let perSecond = Double(ScorePracticeState.peaksPerSecond)
        let chosen = practice.selectedTime
        return Canvas { context, size in
            let x = { (t: Double) in CGFloat(window.share(of: t)) * size.width }
            // The runs shown, as faint bands.
            for (i, run, span) in runs {
                let isChosen = practice.selection.contains(run.id)
                let rect = CGRect(x: x(span.lowerBound), y: 0,
                                  width: max(0, x(span.upperBound) - x(span.lowerBound)), height: size.height)
                context.fill(Path(rect), with: .color(color.opacity(isChosen ? 0.3 : (i.isMultiple(of: 2) ? 0.08 : 0.15))))
            }
            // The outline, a bar to each point.
            if !peaks.isEmpty {
                var path = Path()
                let columns = Int(size.width)
                for column in 0..<columns {
                    let from = window.time(at: Double(column) / Double(columns))
                    let to = window.time(at: Double(column + 1) / Double(columns))
                    let low = max(0, Int(from * perSecond)), high = max(low + 1, Int(to * perSecond))
                    guard low < peaks.count else { break }
                    let peak = peaks[low..<min(high, peaks.count)].max() ?? 0
                    let half = max(0.5, CGFloat(min(peak, 1)) * (size.height / 2 - 4))
                    path.addRect(CGRect(x: CGFloat(column), y: size.height / 2 - half, width: 1, height: half * 2))
                }
                context.fill(path, with: .color(Color(white: 0.55)))
            }
            // Where the match doubts itself, dashed; the tagged nudge points, flagged.
            for t in doubted where window.contains(t) {
                context.stroke(line(at: x(t), height: size.height), with: .color(Self.doubtColor),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            for t in tagged where window.contains(t) {
                context.stroke(line(at: x(t), height: size.height), with: .color(Self.tagColor), lineWidth: 1.5)
                context.draw(Text(Image(systemName: "flag.fill")).font(.system(size: 9)).foregroundStyle(Self.tagColor),
                             at: CGPoint(x: x(t) + 2, y: 2), anchor: .topLeading)
            }
            // A guide at the chosen note, and the playhead.
            if let chosen, window.contains(chosen) {
                context.stroke(line(at: x(chosen), height: size.height), with: .color(.white.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            if window.contains(now) {
                context.stroke(line(at: x(now), height: size.height), with: .color(.white), lineWidth: 1.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: – The notes

    private func notesLane(window: RecordingWindow, size: CGSize, now: Double) -> some View {
        let practice = state.practice
        let hand = practice.hand
        let notes = practice.timelineNotes
        let range = practice.pitchRange ?? 60...72
        let chosen = practice.selectedStep
        let pins = practice.pinTimes
        return Canvas { context, size in
            let x = { (t: Double) in CGFloat(window.share(of: t)) * size.width }
            let inset: CGFloat = 6
            let rows = CGFloat(range.upperBound - range.lowerBound + 1)
            let row = (size.height - 2 * inset) / rows
            let thickness = min(max(row, 2), 6)
            let y = { (pitch: Int) in
                inset + CGFloat(range.upperBound - pitch) * row + (row - thickness) / 2
            }
            // The other hand first, so the hand shown lies over it.
            for isShown in [false, true] {
                for note in notes where (note.hand == hand) == isShown
                    && note.off >= window.start && note.on <= window.end {
                    let isChosen = isShown && note.step == chosen
                    let rect = CGRect(x: x(note.on), y: y(note.pitch),
                                      width: max(2, x(note.off) - x(note.on)), height: thickness)
                    let fill: Color = isChosen ? .white : isShown ? note.hand.color : Color(white: 0.3)
                    context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2), with: .color(fill))
                }
            }
            // The moments pinned by hand, as a diamond at the top.
            for t in pins where window.contains(t) {
                let at = x(t)
                var diamond = Path()
                diamond.move(to: CGPoint(x: at, y: 0))
                diamond.addLine(to: CGPoint(x: at + 4, y: 4))
                diamond.addLine(to: CGPoint(x: at, y: 8))
                diamond.addLine(to: CGPoint(x: at - 4, y: 4))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(.white))
            }
            if window.contains(now) {
                context.stroke(line(at: x(now), height: size.height), with: .color(.white), lineWidth: 1.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func line(at x: CGFloat, height: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: height))
        }
    }
}
