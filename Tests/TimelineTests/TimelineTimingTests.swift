import AVFoundation
import Testing
@testable import Perfecto

/// The timeline's notes in time: stamped by the clock, sounded by the
/// kernel on their exact frames, with a clock that is always late.
@Suite("Timeline timing", .serialized)
@MainActor
struct TimelineTimingTests {

    private static let lead = 0.05

    /// A timeline of `chords` (start step, length in steps), played by a
    /// player whose layers sound through `sink` with a lead.
    private func makePlayer(_ chords: [(step: Int, steps: Int)], bars: Int = 1, clock: ManualClock,
                            sink: any NoteSink) -> TimelinePlayer {
        var timeline = Timeline(barCount: bars)
        timeline.layers[0].notes = chords.map {
            TimelineNote(start: $0.step * TimelineTime.ticksPerStep, length: $0.steps * TimelineTime.ticksPerStep,
                         chord: ChordSpec(degree: .I, color: .base), pitch: .lead)
        }
        let live = LiveSettings(key: Key(root: .C, scale: .major), octave: 4, preset: .sinePad, effects: NoteEffects())
        let player = TimelinePlayer(live: live, clock: clock) { _ in
            let notes = NotePlayer([sink], clock: clock, lead: Self.lead)
            return LayerVoice(sink: notes, sound: notes, clock: clock)
        }
        player.timeline = timeline
        return player
    }

    /// The clock gets round to things late and unevenly: it is moved on in
    /// steps of these lengths, in seconds, over and over.
    private func runLate(_ clock: ManualClock, seconds: Double) {
        let steps = [0.013, 0.031, 0.007, 0.044, 0.019]
        var (gone, index) = (0.0, 0)
        while gone < seconds {
            let step = min(steps[index % steps.count], seconds - gone)
            clock.advance(seconds: step)
            gone += step
            index += 1
        }
    }

    /// At 120 a step is an eighth of a second.
    private let step = 0.125

    @Test func everyNoteIsStampedWithItsOwnMomentHoweverLateTheClock() {
        let (clock, sink) = (ManualClock(), RecordingNoteSink())
        let player = makePlayer([(0, 2), (4, 1), (7, 3), (12, 4)], clock: clock, sink: sink)
        player.start()
        runLate(clock, seconds: 1.99)
        let starts = [0, 4, 7, 12].map { Double($0) * step + Self.lead }
        let ends = [2, 5, 10].map { Double($0) * step + Self.lead }
        #expect(sink.startTimes.count == starts.count && sink.endTimes.count == ends.count)
        for (stamped, wanted) in zip(sink.startTimes + sink.endTimes, starts + ends) {
            #expect(abs(stamped - wanted) < 1e-9)
        }
    }

    /// Ten minutes of a one-bar loop: the last time round is as exactly in
    /// place as the first. Nothing adds up.
    @Test func aLoopDoesNotDriftOverTenMinutes() {
        let (clock, sink) = (ManualClock(), RecordingNoteSink())
        let player = makePlayer([(0, 2), (8, 2)], clock: clock, sink: sink)
        player.start()
        runLate(clock, seconds: 600.01)
        #expect(sink.startTimes.count == 601)                             // two a bar, a bar every two seconds
        for (index, stamped) in sink.startTimes.enumerated() {
            let wanted = Double(index) * 1.0 + Self.lead
            #expect(abs(stamped - wanted) < 1e-6)
            if abs(stamped - wanted) >= 1e-6 { break }
        }
    }

    /// Through the kernel, each note begins on exactly the frame of its
    /// moment, though the clock that sent it was late every time.
    @Test func theKernelSoundsEachNoteOnItsExactFrame() throws {
        let clock = ManualClock()
        var kernel: KernelSink?
        let rig = try KernelOfflineRig { unit in
            kernel = KernelSink(unit: unit) { UInt64(($0 * KernelOfflineRig.rate).rounded()) }
        }
        defer { rig.engine.stop() }
        // Short notes with silence between, so each start can be seen.
        let chords = [(step: 0, steps: 1), (step: 5, steps: 1), (step: 11, steps: 1)]
        let player = makePlayer(chords, clock: clock, sink: try #require(kernel))
        player.start()

        // The engine renders as the clock goes, a late step at a time.
        var rendered = 0.0
        for late in [0.013, 0.031, 0.044, 0.019, 0.007] + Array(repeating: 0.037, count: 50) {
            clock.advance(seconds: late)
            rendered += late
            try rig.render(Int(rendered * KernelOfflineRig.rate))
        }

        let release = Int(0.35 * 9.3 * KernelOfflineRig.rate)             // the sine pad's, to silence
        for chord in chords {
            let frame = Int(((Double(chord.step) * step + Self.lead) * KernelOfflineRig.rate).rounded())
            // Silent up to its frame (the note before has died away), and sounding from the next.
            if chord.step > 0 {
                #expect(frame - release > 0 ? loudest(rig.output[(frame - 200)...frame]) < 0.0002 : true)
            } else {
                #expect(loudest(rig.output[...frame]) == 0)
            }
            #expect(abs(rig.output[frame + 1]) > 0)
            #expect(loudest(rig.output[frame + 1..<frame + 2400]) > 0.01)
        }
    }
}
