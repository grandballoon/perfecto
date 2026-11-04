import SwiftUI

/// The whole recording as one bar, to go anywhere in it: the time it
/// stands at and its length either side, the run in focus shaded where it
/// is heard, the nudge points marked (tagged, orange; doubted by the
/// match, yellow), and a knob where it is playing or stands.
///
/// A finger anywhere on the bar drags the recording (`scrub`), the keys
/// lit as they are at each moment passed, and it plays on from where it is
/// let go if it was being listened to.
struct PracticeScrubber: View {
    @Environment(PerformanceState.self) private var state

    private static let height: CGFloat = 28
    private static let track: CGFloat = 4
    private static let knob: CGFloat = 14
    /// How far one swipe of VoiceOver moves the recording, in seconds.
    private static let step = 5.0

    var body: some View {
        let practice = state.practice
        let length = max(practice.recordingLength ?? 0, 0.1)
        TimelineView(.animation(paused: practice.listening == nil)) { _ in
            let now = practice.currentTime
            HStack(spacing: 10) {
                time(now)
                GeometryReader { geo in
                    let width = geo.size.width
                    let x = { (t: Double) -> CGFloat in CGFloat(min(max(t / length, 0), 1)) * width }
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.2)).frame(height: Self.track)
                        if let focus = practice.focus, let span = practice.span(of: focus) {
                            Capsule().fill(practice.hand.color.opacity(0.6))
                                .frame(width: max(Self.track, x(span.upperBound) - x(span.lowerBound)),
                                       height: Self.track)
                                .offset(x: x(span.lowerBound))
                        }
                        Capsule().fill(Color(white: 0.75)).frame(width: x(now), height: Self.track)
                        ForEach(practice.practice?.unsure ?? [], id: \.self) { t in
                            Capsule().fill(PracticeRecordingStrip.doubtColor)
                                .frame(width: 2, height: 10).offset(x: x(t) - 1)
                        }
                        ForEach(practice.practice?.nudges ?? [], id: \.self) { t in
                            Capsule().fill(PracticeRecordingStrip.tagColor)
                                .frame(width: 2, height: 12).offset(x: x(t) - 1)
                        }
                        Circle().fill(Color.white)
                            .frame(width: Self.knob, height: Self.knob)
                            .scaleEffect(practice.isScrubbing ? 1.3 : 1)
                            .offset(x: x(now) - Self.knob / 2)
                    }
                    .frame(width: width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            practice.scrub(to: Double(drag.location.x / width) * length, isDone: false)
                        }
                        .onEnded { drag in
                            practice.scrub(to: Double(drag.location.x / width) * length, isDone: true)
                        })
                }
                time(length)
            }
            .animation(.easeOut(duration: 0.12), value: practice.isScrubbing)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording position")
        .accessibilityValue("\(PracticeTime.text(practice.currentTime)) of \(PracticeTime.text(length))")
        .accessibilityAdjustableAction { direction in
            let by = direction == .increment ? Self.step : -Self.step
            practice.scrub(to: practice.currentTime + by, isDone: true)
        }
    }

    private func time(_ seconds: Double) -> some View {
        Text(PracticeTime.text(seconds))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.7))
            .fixedSize()
    }
}
