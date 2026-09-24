import Foundation
import Testing
@testable import Perfecto

@Suite("SequencerMidiRenderer")
@MainActor
struct SequencerMidiRendererTests {

    /// One sounding note in the rendered file: pitch plus on/off ticks.
    private struct Span: Equatable {
        let note: Int
        let start: Int
        let end: Int
    }

    private let cMajor = Key(root: .C, scale: .major)
    private let stepTicks = 120   // 480 PPQN / 4 steps per beat

    private func step(_ degree: Degree, gate: Double = 0.5,
                      direction: JoystickDirection = .center) -> SequencerStep {
        SequencerStep(degree: degree, joystickDirection: direction, gate: gate)
    }

    private var rest: SequencerStep { SequencerStep(isRest: true) }

    private func render(_ steps: [SequencerStep], key: Key? = nil) -> MidiFile {
        SequencerMidiRenderer.render(SequencerPattern(steps: steps,
                                                      key: key ?? cMajor,
                                                      octave: 4,
                                                      bpm: 120,
                                                      stepsPerBeat: 4))
    }

    private func events(_ file: MidiFile) -> [MidiEvent] {
        file.tracks.flatMap(\.events)
    }

    private func spans(_ file: MidiFile) -> [Span] {
        var open: [Int: Int] = [:]
        var result: [Span] = []
        let ordered = events(file).enumerated().sorted {
            ($0.element.tick, $0.element.kind.orderWithinTick, $0.offset)
                < ($1.element.tick, $1.element.kind.orderWithinTick, $1.offset)
        }.map(\.element)
        for event in ordered {
            switch event.kind {
            case let .noteOn(_, note, _):
                open[note] = event.tick
            case let .noteOff(_, note):
                if let start = open.removeValue(forKey: note) {
                    result.append(Span(note: note, start: start, end: event.tick))
                }
            default: break
            }
        }
        #expect(open.isEmpty, "every note-on must be released")
        return result.sorted { ($0.start, $0.note) < ($1.start, $1.note) }
    }

    private func chord(_ notes: [Int], _ start: Int, _ end: Int) -> [Span] {
        notes.map { Span(note: $0, start: start, end: end) }
    }

    private func markers(_ file: MidiFile) -> [String] {
        events(file).compactMap { if case let .marker(text) = $0.kind { text } else { nil } }
    }

    // MARK: – Timing

    @Test func gateSetsHowLongEachChordSounds() {
        let file = render([step(.I, gate: 0.75), rest, step(.I, gate: 0.25)])
        #expect(spans(file) == chord([60, 64, 67], 0, 90)
                             + chord([60, 64, 67], 240, 270))
    }

    @Test func trailingRestsKeepTheFullPatternLength() {
        let file = render([step(.I)] + Array(repeating: rest, count: 15))
        #expect(file.tracks.map(\.length) == [16 * stepTicks])
        #expect(file.ticksPerQuarter == 480)
    }

    @Test func tiedIdenticalChordsMergeIntoOneNote() {
        let file = render([step(.I, gate: 1), step(.I, gate: 1), step(.I, gate: 0.5)])
        #expect(spans(file) == chord([60, 64, 67], 0, 2 * stepTicks + 60))
    }

    @Test func untiedIdenticalChordsRetrigger() {
        let file = render([step(.I, gate: 0.9), step(.I, gate: 0.9)])
        #expect(spans(file).count == 6)
    }

    @Test func tiedStepRingsUntilTheNextChordOrRest() {
        let file = render([step(.I, gate: 1), step(.V), step(.IV, gate: 1), rest])
        let v = performanceVoicing(key: cMajor, octave: 4, degree: .V, joystickMode: .default,
                                   joystickDirection: .center, previousVoicing: nil).notes
        let iv = performanceVoicing(key: cMajor, octave: 4, degree: .IV, joystickMode: .default,
                                    joystickDirection: .center, previousVoicing: nil).notes
        let expected = chord([60, 64, 67], 0, stepTicks)
                     + chord(v, stepTicks, stepTicks + 60)
                     + chord(iv, 2 * stepTicks, 3 * stepTicks)
        #expect(spans(file) == expected.sorted { ($0.start, $0.note) < ($1.start, $1.note) })
    }

    @Test func tiedLastStepEndsWithThePattern() {
        let file = render([rest, step(.I, gate: 1)])
        #expect(spans(file) == chord([60, 64, 67], stepTicks, 2 * stepTicks))
    }

    @Test func allRestsProduceNoNotes() {
        #expect(spans(render([rest, rest])).isEmpty)
    }

    // MARK: – Fidelity to playback

    /// The exported onsets must be exactly the voicings SequencerMode sends to
    /// the sinks — same notes, same order — for a pattern that exercises
    /// joystick transformations, rests and several degrees.
    @Test func exportedChordsMatchWhatPlaybackSounds() {
        let steps = [step(.I, direction: .right), step(.vi, direction: .up), rest,
                     step(.IV, direction: .downLeft), step(.V, direction: .left),
                     step(.ii), rest, step(.iii, direction: .upRight)]
            + Array(repeating: rest, count: 8)
        let key = Key(root: .E, scale: .dorian)

        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps = steps
        let sink = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: sink, clock: clock)
        state.key = key
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        for _ in steps { clock.tick() }

        let file = render(steps, key: key)
        var onsets: [Int: [Int]] = [:]
        for span in spans(file) { onsets[span.start, default: []].append(span.note) }
        let exported = onsets.keys.sorted().map { onsets[$0]!.sorted() }
        #expect(exported == sink.playCalls.map(\.notes))
        withExtendedLifetime(state) {}
    }

    // MARK: – Metadata

    @Test func headerEventsDescribeTempoMeterAndKey() {
        let file = SequencerMidiRenderer.render(SequencerPattern(
            steps: [step(.I)], key: Key(root: .D, scale: .naturalMinor),
            octave: 4, bpm: 96, stepsPerBeat: 4))
        let meta = events(file).filter { $0.tick == 0 }.map(\.kind)
        #expect(meta.contains(.tempo(bpm: 96)))
        #expect(meta.contains(.timeSignature(numerator: 4, denominator: 4)))
        #expect(meta.contains(.keySignature(MidiKeySignature(sharps: -1, isMinor: true))))
        #expect(meta.contains(.trackName("Perfecto")))
    }

    @Test func markersNameEachChordChangeOnce() {
        let file = render([step(.I, gate: 0.5), step(.I, gate: 0.5), rest,
                           step(.I), step(.V, direction: .right)])
        #expect(markers(file) == [
            chordLabel(key: cMajor, degree: .I, joystickMode: .default, joystickDirection: .center),
            chordLabel(key: cMajor, degree: .V, joystickMode: .default, joystickDirection: .right),
        ])
    }

    // MARK: – Wiring

    @Test func exportUsesThePlayedStepsAndCurrentSettings() {
        let state = PerformanceState(sink: RecordingSink(), clock: ManualClock())
        state.key = Key(root: .A, scale: .naturalMinor)
        state.octave = 3
        state.setBPM(90)

        let export = state.sequencerMidiExport
        #expect(export.pattern.steps.map(\.label) == state.sequencerState.playedSteps.map(\.label))
        #expect(export.pattern.key == state.key)
        #expect(export.pattern.octave == 3)
        #expect(export.pattern.bpm == 90)
        #expect(export.pattern.stepsPerBeat == state.ticksPerBeat)
        #expect(export.fileName == "Perfecto A Natural Minor 90 BPM.mid")
    }

    @Test func completingAnExportIsLogged() {
        let logger = RecordingLogger()
        let state = PerformanceState(sink: RecordingSink(), clock: ManualClock(), logger: logger)
        state.sequencerMidiExport.onExport(12, 345)
        guard case let .sequencer_midi_exported(stepCount, noteCount, byteCount) = logger.events.last else {
            Issue.record("expected a sequencer_midi_exported event")
            return
        }
        #expect(stepCount == state.sequencerState.playedSteps.count)
        #expect(noteCount == 12)
        #expect(byteCount == 345)
    }
}
