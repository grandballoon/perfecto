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
        SequencerStep(degree: degree, color: .joystick(.default, direction), gate: gate)
    }

    private var rest: SequencerStep { SequencerStep(isRest: true) }

    private func live(_ key: Key) -> LiveSettings {
        LiveSettings(key: key, octave: 4, preset: .initial, effects: NoteEffects())
    }

    /// A one-bar timeline with `steps` entered on its first steps.
    private func timeline(_ steps: [SequencerStep]) -> Timeline {
        var timeline = Timeline()
        timeline.layers = [Layer(steps: steps)]
        return timeline
    }

    private func render(_ steps: [SequencerStep], key: Key? = nil, bpm: Double = 120) -> MidiFile {
        SequencerMidiRenderer.render(SequencerPattern(timeline: timeline(steps), live: live(key ?? cMajor), bpm: bpm))
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

    // MARK: – Notes played from the net

    /// Notes that came and went one at a time are each one note in the
    /// file, from where it was pressed to where it was let go.
    @Test func aNoteATiedChordHoldsOverIsOneNoteInTheFile() {
        let chord = ChordSpec(degree: .I, color: .base)
        func tied(_ notes: [Int], _ start: Int, _ length: Int) -> TimelineNote {
            TimelineNote(start: start, length: length, chord: chord, pitch: .notes(notes), articulation: .tied)
        }
        var timeline = Timeline()
        timeline.layers = [Layer(notes: [
            tied([60], 0, 480), tied([60, 67], 480, 480), tied([67], 960, 480),
            // After a gap it is struck again.
            tied([67], 1560, 120),
        ])]
        let file = SequencerMidiRenderer.render(SequencerPattern(timeline: timeline, live: live(cMajor), bpm: 120))
        #expect(spans(file) == [Span(note: 60, start: 0, end: 960), Span(note: 67, start: 480, end: 1440),
                                Span(note: 67, start: 1560, end: 1680)])
    }

    // MARK: – Timing

    @Test func gateSetsHowLongEachChordSounds() {
        let file = render([step(.I, gate: 0.75), rest, step(.I, gate: 0.25)])
        #expect(spans(file) == chord([60, 64, 67], 0, 90)
                             + chord([60, 64, 67], 240, 270))
    }

    @Test func theFileIsAsLongAsTheSequenceHoweverFewNotesItHas() {
        let file = render([step(.I)])
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
        let v = performanceVoicing(key: cMajor, octave: 4, spec: ChordSpec(degree: .V, color: .joystick(.default, .center)), previousVoicing: nil).notes
        let iv = performanceVoicing(key: cMajor, octave: 4, spec: ChordSpec(degree: .IV, color: .joystick(.default, .center)), previousVoicing: nil).notes
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
        clock.advance(beats: 3.9)                       // once through the bar

        let file = render(steps, key: key)
        var onsets: [Int: [Int]] = [:]
        for span in spans(file) { onsets[span.start, default: []].append(span.note) }
        let exported = onsets.keys.sorted().map { onsets[$0]!.sorted() }
        #expect(exported == sink.playCalls.map(\.notes))
        withExtendedLifetime(state) {}
    }

    // MARK: – Metadata

    @Test func headerEventsDescribeTempoMeterAndKey() {
        let file = render([step(.I)], key: Key(root: .D, scale: .naturalMinor), bpm: 96)
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
            chordLabel(key: cMajor, spec: ChordSpec(degree: .I, color: .joystick(.default, .center))),
            chordLabel(key: cMajor, spec: ChordSpec(degree: .V, color: .joystick(.default, .right))),
        ])
    }

    @Test func theTimeSignatureIsTheTimelines() {
        var waltz = timeline([step(.I)])
        waltz.setSignature(TimeSignature(beats: 6, unit: .eighth))
        let file = SequencerMidiRenderer.render(SequencerPattern(timeline: waltz, live: live(cMajor), bpm: 120))
        #expect(events(file).map(\.kind).contains(.timeSignature(numerator: 6, denominator: 8)))
        #expect(file.tracks.map(\.length) == [waltz.length])
    }

    // MARK: – What is exported

    /// Only the stretch that repeats, starting from its own beginning.
    @Test func aLoopedStretchIsExportedAlone() {
        var looped = timeline([step(.I), step(.I), step(.V), step(.V)])
        looped.setLoop(steps: [2, 3])
        let file = SequencerMidiRenderer.render(SequencerPattern(timeline: looped, live: live(cMajor), bpm: 120))
        #expect(file.tracks.map(\.length) == [2 * stepTicks])
        #expect(Set(spans(file).map(\.start)) == [0, stepTicks])
        #expect(Set(spans(file).map(\.note)) == [67, 71, 74])
    }

    /// Each layer is a track of its own; a muted one is left out.
    @Test func everyLayerThatIsNotMutedIsATrack() {
        var layered = timeline([step(.I)])
        layered.layers.append(Layer(steps: [rest, step(.V)]))
        layered.layers.append(Layer(steps: [step(.IV)]))
        layered.layers[2].isMuted = true
        let file = SequencerMidiRenderer.render(SequencerPattern(timeline: layered, live: live(cMajor), bpm: 120))
        #expect(file.tracks.count == 2)
        #expect(Set(spans(file).map(\.note)) == [60, 64, 67, 71, 74])
    }

    /// A note with a key of its own is written in that key.
    @Test func aNotesOwnKeyIsExported() {
        var own = timeline([step(.I)])
        own.layers[0].edit(notesOn: [0]) { $0.playing.key = Key(root: .D, scale: .major) }
        let file = SequencerMidiRenderer.render(SequencerPattern(timeline: own, live: live(cMajor), bpm: 120))
        #expect(spans(file).map(\.note) == [62, 66, 69])
    }

    // MARK: – Wiring

    @Test func exportUsesTheSequenceAndCurrentSettings() {
        let state = PerformanceState(sink: RecordingSink(), clock: ManualClock())
        state.key = Key(root: .A, scale: .naturalMinor)
        state.octave = 3
        state.setBPM(90)

        let export = state.sequencerMidiExport
        #expect(export.pattern.timeline == state.sequencerState.timeline)
        #expect(export.pattern.live.key == state.key)
        #expect(export.pattern.live.octave == 3)
        #expect(export.pattern.bpm == 90)
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
        #expect(stepCount == 16)
        #expect(noteCount == 12)
        #expect(byteCount == 345)
    }
}
