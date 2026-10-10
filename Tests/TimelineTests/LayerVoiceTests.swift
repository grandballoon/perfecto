import Testing
@testable import Perfecto

/// A layer's voice: each chord in its own sound, and a recorded slide
/// played back as it was made.
@Suite("LayerVoice")
@MainActor
struct LayerVoiceTests {

    private let clock = ManualClock()

    private func chord(_ notes: [Int], preset: SynthPreset = .initial, effects: NoteEffects = NoteEffects(),
                       changes: [SoundChange] = []) -> TimedChord {
        TimedChord(start: 0, end: 960, event: .block(notes), preset: preset, effects: effects, changes: changes)
    }

    private func bright(_ brightness: Float) -> NoteEffects {
        var effects = NoteEffects()
        effects.filter = FilterSettings(isOn: true, brightness: brightness)
        return effects
    }

    @Test func eachChordIsPlayedInItsOwnSound() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        let voice = LayerVoice(sink: player, sound: player, clock: clock)
        voice.play(chord([60], preset: .bell, effects: bright(0.4)))
        voice.play(chord([62], preset: .organ))
        #expect(sink.sounds.map(\.preset) == [.bell, .organ])
        #expect(sink.sounds[0].filter.brightness == 0.4)
        #expect(!sink.sounds[1].filter.isOn)
    }

    /// Effects edited under a chord glide its notes to them, and what was
    /// left of its recorded slide does not undo the edit.
    @Test func aChangeReachesTheNotesHeldAndEndsTheSlide() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        let voice = LayerVoice(sink: player, sound: player, clock: clock)
        voice.play(chord([60], effects: bright(0.2), changes: [SoundChange(offset: 480, effects: bright(0.9))]))
        voice.change(to: chord([60], effects: bright(0.6)))
        clock.advance(beats: 2)
        #expect(sink.started == [60])
        #expect(sink.changes.map(\.filter.brightness) == [0.6])
    }

    /// The effects change at the moments the slide was played, counted in
    /// beats from the chord's start, so they keep their place at any tempo.
    @Test func aRecordedSlideIsPlayedBackInTime() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        let voice = LayerVoice(sink: player, sound: player, clock: clock)
        voice.play(chord([60], effects: bright(0.2), changes: [
            SoundChange(offset: 240, effects: bright(0.5)),               // half a beat in
            SoundChange(offset: 480, effects: bright(0.9)),               // a beat in
        ]))
        #expect(sink.changes.isEmpty)
        clock.advance(beats: 0.5)
        #expect(sink.changes.map(\.filter.brightness) == [0.5])
        clock.advance(beats: 0.5)
        #expect(sink.changes.map(\.filter.brightness) == [0.5, 0.9])
    }

    /// What is left of a slide goes with its chord.
    @Test func aSlideEndsWithItsChord() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        let voice = LayerVoice(sink: player, sound: player, clock: clock)
        let slid = chord([60], effects: bright(0.2), changes: [SoundChange(offset: 480, effects: bright(0.9))])
        voice.play(slid)
        voice.stop()
        clock.advance(beats: 2)
        #expect(sink.changes.isEmpty)

        voice.play(slid)
        voice.play(chord([62], effects: bright(0.3)))                     // the next chord, before the slide's end
        clock.advance(beats: 2)
        #expect(sink.changes.isEmpty)
        #expect(sink.sounds.last?.filter.brightness == 0.3)
    }
}
