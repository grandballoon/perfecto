import Testing
@testable import Perfecto

/// A layer as it is played: what both playback and the export read.
@Suite("Timeline compile")
struct TimelineCompileTests {

    private static let step = TimelineTime.ticksPerStep
    private let live = LiveSettings(key: Key(root: .C, scale: .major), octave: 4,
                                    preset: .sinePad, effects: NoteEffects())

    private func timeline(_ notes: [TimelineNote], bars: Int = 1) -> (Timeline, Layer.ID) {
        var timeline = Timeline(barCount: bars)
        timeline.layers[0].notes = notes
        return (timeline, timeline.layers[0].id)
    }

    private func note(_ degree: Degree, step: Int, steps: Int = 1) -> TimelineNote {
        TimelineNote(start: step * Self.step, length: steps * Self.step,
                     chord: ChordSpec(degree: degree, color: .base))
    }

    @Test func aNoteWithNothingOfItsOwnFollowsTheLiveSettings() {
        let (timeline, layer) = timeline([note(.I, step: 0), note(.V, step: 4, steps: 2)])
        let chords = timeline.compile(layer: layer, live: live)

        #expect(chords.map(\.start) == [0, 480])
        #expect(chords.map(\.end) == [120, 720])
        #expect(chords[0].event.voicing.notes == [60, 64, 67])
        #expect(chords[1].event.voicing.notes == [67, 71, 74])
        #expect(chords.allSatisfy { $0.preset == .sinePad && $0.effects == NoteEffects() })

        var inG = live
        inG.key = Key(root: .G, scale: .major)
        #expect(timeline.compile(layer: layer, live: inG)[0].event.voicing.notes == [67, 71, 74])
    }

    /// The same chord number, in the note's own key and octave, whatever is
    /// chosen now.
    @Test func aNotesOwnSettingsWinOverTheLiveOnes() {
        var own = note(.I, step: 0)
        own.playing = NotePlaying(key: Key(root: .D, scale: .major), octave: 3, preset: .bell,
                                  effects: NoteEffects(reverb: ReverbSettings(isOn: true)))
        let (timeline, layer) = timeline([own])
        let chord = timeline.compile(layer: layer, live: live)[0]

        #expect(chord.event.voicing.notes == [50, 54, 57])
        #expect(chord.event.context.key == Key(root: .D, scale: .major))
        #expect(chord.event.context.spec.degree == .I)
        #expect(chord.preset == .bell)
        #expect(chord.effects.reverb.isOn)
    }

    @Test func aLeadNoteIsTheScaleDegreeAlone() {
        var lead = note(.V, step: 0)
        lead.pitch = .lead
        let (timeline, layer) = timeline([lead])
        let chord = timeline.compile(layer: layer, live: live)[0]
        #expect(chord.event.voicing.notes == [67])                 // G, the fifth degree of C
        #expect(chord.event.context.spec.degree == .V)
    }

    @Test func onlyTheStretchThatRepeatsIsPlayedAndANoteIsCutAtItsEnd() {
        var (timeline, layer) = timeline([note(.I, step: 0), note(.IV, step: 4, steps: 8), note(.V, step: 14)])
        timeline.setLoop(steps: Set(4..<8))
        let chords = timeline.compile(layer: layer, live: live)
        #expect(chords.count == 1)
        #expect(chords[0].start == 4 * Self.step)
        #expect(chords[0].end == 8 * Self.step)
    }

    @Test func aNoteRunningPastTheEndOfTheTimelineIsCutThere() {
        let (timeline, layer) = timeline([note(.I, step: 14, steps: 6)])
        #expect(timeline.compile(layer: layer, live: live)[0].end == timeline.length)
    }

    @Test func aStrumAndASlideAreCarriedThrough() {
        var played = note(.I, step: 0, steps: 4)
        played.articulation = .strum(interval: 0.06)
        var bright = NoteEffects()
        bright.filter = FilterSettings(isOn: true, brightness: 0.2)
        played.changes = [SoundChange(offset: 100, effects: bright), SoundChange(offset: 5000, effects: bright)]
        let (timeline, layer) = timeline([played])
        let chord = timeline.compile(layer: layer, live: live)[0]
        #expect(chord.event.articulation == .strum(interval: 0.06))
        #expect(chord.changes.map(\.offset) == [100])           // the one after the note ends is dropped
    }

    @Test func aLayerThatIsNotThereCompilesToNothing() {
        let (timeline, _) = timeline([note(.I, step: 0)])
        #expect(timeline.compile(layer: Layer().id, live: live).isEmpty)
    }
}
