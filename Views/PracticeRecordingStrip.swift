import SwiftUI

/// The recording around the run in focus: its outline, the runs shown laid
/// along it where they are heard, and a line where it is playing or
/// stands.
///
/// An edge between runs is dragged to where it is heard, which moves the
/// runs on either side of it (`ScorePracticeState.move`). While an edge is
/// dragged the strip keeps the stretch of the recording it showed, so the
/// edge stays under the finger. Each step of the hand shown is a tick at
/// its foot, which is dragged the same way, to nudge one step to where it
/// is heard; the nudge points are flags. A finger anywhere else drags the
/// recording to the moment under it (`ScorePracticeState.scrub`), and a
/// tap stands it there.
struct PracticeRecordingStrip: View {
    @Environment(PerformanceState.self) private var state

    /// The stretch of the recording shown while an edge is dragged.
    @State private var heldWindow: ClosedRange<Double>?

    private static let height: CGFloat = 72
    private static let handleWidth: CGFloat = 24
    /// Room either side of the run in focus, as a share of its length.
    private static let padding = 0.08
    /// The closest two edges can be dragged, in seconds.
    private static let closest = 0.05
    private static let space = "recording strip"

    var body: some View {
        let practice = state.practice
        let window = heldWindow ?? practice.zoom ?? shownWindow
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: Double) -> CGFloat in CGFloat((t - window.lowerBound) / window.length) * width }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.07))
                runBlocks(x: x)
                waveform(window: window, size: geo.size)
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            practice.scrub(to: window.lowerBound + Double(drag.location.x / width) * window.length,
                                           isDone: false)
                        }
                        .onEnded { drag in
                            practice.scrub(to: window.lowerBound + Double(drag.location.x / width) * window.length,
                                           isDone: true)
                        })
                nudgeMarks(window: window, height: geo.size.height, x: x)
                stepMarks(window: window, width: width, x: x)
                edges(window: window, width: width, x: x)
                if practice.zoom != nil { backToRun }
                TimelineView(.animation(paused: practice.listening == nil)) { _ in
                    let at = x(practice.currentTime)
                    if at >= 0 && at <= width {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 1.5, height: geo.size.height)
                            .offset(x: at - 0.75)
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityValue(PracticeTime.text(practice.currentTime))
    }

    /// Takes the strip from the nudge point it was brought to back to the
    /// run in focus.
    private var backToRun: some View {
        Button { state.practice.zoom = nil } label: {
            Label("Run", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(white: 0.18)))
        }
        .buttonStyle(.plain)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityLabel("Show the run in focus")
    }

    /// The nudge points in view: those tagged as a flag, those the match
    /// doubts as a dashed line.
    private func nudgeMarks(window: ClosedRange<Double>, height: CGFloat,
                            x: @escaping (Double) -> CGFloat) -> some View {
        let practice = state.practice
        let tagged = practice.practice?.nudges ?? []
        let doubted = practice.practice?.unsure ?? []
        return ZStack(alignment: .topLeading) {
            ForEach(doubted.filter(window.contains), id: \.self) { t in
                Path { p in
                    p.move(to: CGPoint(x: x(t), y: 0))
                    p.addLine(to: CGPoint(x: x(t), y: height))
                }
                .stroke(Self.doubtColor, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(tagged.filter(window.contains), id: \.self) { t in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Self.tagColor).frame(width: 1.5, height: height)
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Self.tagColor)
                        .offset(x: 2, y: 2)
                }
                .offset(x: x(t) - 0.75)
            }
        }
        .allowsHitTesting(false)
    }

    static let tagColor = Color.orange
    static let doubtColor = Color.yellow.opacity(0.7)

    /// Every step of the hand shown, where it is heard: a short tick at
    /// the strip's foot, white where it is pinned. A tick is dragged to
    /// where its step is heard, when there is room to take hold of it.
    private func stepMarks(window: ClosedRange<Double>, width: CGFloat,
                           x: @escaping (Double) -> CGFloat) -> some View {
        let practice = state.practice
        let marks = practice.stepMarks
        let color = practice.hand.color
        let shown = marks.indices.filter { window.contains(marks[$0].recording) }
        return ForEach(shown, id: \.self) { i in
            let mark = marks[i]
            let at = x(mark.recording)
            let room = min(i > 0 ? at - x(marks[i - 1].recording) : .infinity,
                           i < marks.count - 1 ? x(marks[i + 1].recording) - at : .infinity)
            let canHold = room >= Self.tickRoom
            ZStack(alignment: .bottom) {
                Color.clear
                VStack(spacing: 0) {
                    if mark.isPinned {
                        Rectangle().fill(Color.white).frame(width: 6, height: 6).rotationEffect(.degrees(45))
                    }
                    Rectangle().fill(mark.isPinned ? Color.white : color.opacity(0.8))
                        .frame(width: 1.5, height: Self.tickHeight)
                }
            }
            .frame(width: canHold ? min(room, Self.handleWidth) : 2, height: Self.height)
            .contentShape(Rectangle())
            .offset(x: at - (canHold ? min(room, Self.handleWidth) : 2) / 2)
            .allowsHitTesting(canHold)
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                .onChanged { drag in
                    if heldWindow == nil { heldWindow = window }
                    practice.move(edgeAt: mark.score, to: tickTime(at: drag.location.x, i, marks, window, width),
                                  isDone: false)
                }
                .onEnded { drag in
                    practice.move(edgeAt: mark.score, to: tickTime(at: drag.location.x, i, marks, window, width),
                                  isDone: true)
                    heldWindow = nil
                })
            .accessibilityLabel("Step \(i + 1)")
        }
    }

    private static let tickHeight: CGFloat = 14
    /// The least room either side of a tick for it to be taken hold of.
    private static let tickRoom: CGFloat = 10

    /// The moment under `x`, kept between the steps either side of step
    /// `i`, so a drag never passes another step.
    private func tickTime(at x: CGFloat, _ i: Int, _ marks: [ScorePracticeState.StepMark],
                          _ window: ClosedRange<Double>, _ width: CGFloat) -> Double {
        let t = window.lowerBound + Double(x / width) * window.length
        let low = i > 0 ? marks[i - 1].recording + Self.closest : 0
        let high = i < marks.count - 1 ? marks[i + 1].recording - Self.closest
                                        : (state.practice.recordingLength ?? t)
        return low < high ? t.clamped(to: low...high) : t
    }

    /// The run in focus and a little either side, within the recording.
    private var shownWindow: ClosedRange<Double> {
        let practice = state.practice
        let length = max(practice.recordingLength ?? 1, 0.1)
        guard let focus = practice.focus, let span = practice.span(of: focus) else { return 0...length }
        let pad = max(0.5, span.length * Self.padding)
        let low = max(0, span.lowerBound - pad)
        let high = min(length, span.upperBound + pad)
        return high - low > 0.1 ? low...high : 0...length
    }

    /// Each run shown, shaded where it is heard, and named at its start.
    private func runBlocks(x: @escaping (Double) -> CGFloat) -> some View {
        let practice = state.practice
        let color = practice.hand.color
        return ForEach(Array(practice.shownRuns.enumerated()), id: \.element.id) { i, run in
            if let span = practice.span(of: run.id) {
                let isChosen = practice.selection.contains(run.id)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(color.opacity(isChosen ? 0.35 : (i.isMultiple(of: 2) ? 0.12 : 0.2)))
                    Text(run.id == practice.focus ? "" : practice.label(of: run.id))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.leading, 4)
                        .padding(.top, 3)
                        .fixedSize()
                }
                .frame(width: max(0, x(span.upperBound) - x(span.lowerBound)), height: Self.height)
                .offset(x: x(span.lowerBound))
                .allowsHitTesting(false)
            }
        }
    }

    /// The recording's outline across the strip, a bar to each point.
    private func waveform(window: ClosedRange<Double>, size: CGSize) -> some View {
        let peaks = state.practice.peaks
        let perSecond = Double(ScorePracticeState.peaksPerSecond)
        return Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let columns = Int(size.width)
            var path = Path()
            for column in 0..<columns {
                let from = window.lowerBound + Double(column) / Double(columns) * window.length
                let to = window.lowerBound + Double(column + 1) / Double(columns) * window.length
                let low = Int(from * perSecond), high = max(low + 1, Int(to * perSecond))
                guard low < peaks.count else { break }
                let peak = peaks[max(0, low)..<min(high, peaks.count)].max() ?? 0
                let half = max(0.5, CGFloat(min(peak, 1)) * (size.height / 2 - 4))
                path.addRect(CGRect(x: CGFloat(column), y: size.height / 2 - half, width: 1, height: half * 2))
            }
            context.fill(path, with: .color(Color(white: 0.55)))
        }
        .frame(width: size.width, height: size.height)
    }

    /// A handle on each edge of the runs shown, dragged along the recording.
    private func edges(window: ClosedRange<Double>, width: CGFloat, x: @escaping (Double) -> CGFloat) -> some View {
        let practice = state.practice
        let edges = practice.shownEdges
        let times = edges.map(practice.recordingTime(ofScore:))
        let color = practice.hand.color
        return ForEach(edges.indices, id: \.self) { i in
            let at = x(times[i])
            if at >= -Self.handleWidth && at <= width + Self.handleWidth {
                ZStack {
                    Color.clear
                    Capsule().fill(color).frame(width: 2)
                    Capsule().fill(color).frame(width: 8, height: 22)
                }
                .frame(width: Self.handleWidth, height: Self.height)
                .contentShape(Rectangle())
                .offset(x: at - Self.handleWidth / 2)
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                    .onChanged { drag in
                        if heldWindow == nil { heldWindow = window }
                        practice.move(edgeAt: edges[i], to: time(at: drag.location.x, i, times, window, width),
                                      isDone: false)
                    }
                    .onEnded { drag in
                        practice.move(edgeAt: edges[i], to: time(at: drag.location.x, i, times, window, width),
                                      isDone: true)
                        heldWindow = nil
                    })
                .accessibilityLabel("Edge \(i + 1)")
            }
        }
    }

    /// The moment under `x` on the strip, kept between the edges either
    /// side of edge `i`, so a drag never passes another edge.
    private func time(at x: CGFloat, _ i: Int, _ times: [Double], _ window: ClosedRange<Double>,
                      _ width: CGFloat) -> Double {
        let t = window.lowerBound + Double(x / width) * window.length
        let low = i > 0 ? times[i - 1] + Self.closest : 0
        let high = i < times.count - 1 ? times[i + 1] - Self.closest : (state.practice.recordingLength ?? t)
        return low < high ? t.clamped(to: low...high) : t
    }
}

private extension ClosedRange where Bound == Double {
    var length: Double { upperBound - lowerBound }
}
