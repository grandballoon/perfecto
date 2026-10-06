import Testing
@testable import Perfecto

@Suite("VoiceAllocator")
@MainActor
struct VoiceAllocatorTests {

    /// Starts `count` notes, returning their ids and voices.
    private func start(_ count: Int, on allocator: inout VoiceAllocator) -> [(id: NoteID, voice: Int)] {
        (0..<count).map { _ in
            let id = NoteID.next()
            return (id, allocator.start(id).voice)
        }
    }

    @Test func notesHeldTogetherEachGetAVoiceOfTheirOwn() {
        var allocator = VoiceAllocator(voices: 8)
        let chord = start(4, on: &allocator)
        #expect(Set(chord.map(\.voice)).count == 4)
    }

    /// The point of it: the chord just released rings out while the next
    /// one starts on other voices.
    @Test func aNewChordLeavesTheChordJustReleasedToRingOut() {
        var allocator = VoiceAllocator(voices: 8)
        let first = start(4, on: &allocator)
        for note in first { _ = allocator.end(note.id) }
        let second = start(4, on: &allocator)
        #expect(Set(first.map(\.voice)).isDisjoint(with: second.map(\.voice)))
    }

    /// When released voices must be reused, the one released longest ago
    /// has died away most.
    @Test func theVoiceReleasedLongestAgoIsReusedFirst() {
        var allocator = VoiceAllocator(voices: 3)
        let notes = start(3, on: &allocator)
        _ = allocator.end(notes[1].id)
        _ = allocator.end(notes[0].id)
        _ = allocator.end(notes[2].id)
        let reused = start(3, on: &allocator).map(\.voice)
        #expect(reused == [notes[1].voice, notes[0].voice, notes[2].voice])
    }

    @Test func endingANoteNamesItsVoiceOnce() {
        var allocator = VoiceAllocator(voices: 2)
        let note = start(1, on: &allocator)[0]
        #expect(allocator.end(note.id) == note.voice)
        #expect(allocator.end(note.id) == nil)
        #expect(allocator.end(.next()) == nil)
    }

    @Test func withEveryVoiceHeldANoteTakesOverTheOneHeldLongest() {
        var allocator = VoiceAllocator(voices: 2)
        let held = start(2, on: &allocator)
        let extra = NoteID.next()
        let taken = allocator.start(extra)
        #expect(taken.stolen)
        #expect(taken.voice == held[0].voice)
        // The note that lost its voice is forgotten: ending it must not
        // release the voice the new note is on.
        #expect(allocator.end(held[0].id) == nil)
        #expect(allocator.end(extra) == held[0].voice)
    }

    @Test func aNoteIsNotStolenWhileAVoiceIsFree() {
        var allocator = VoiceAllocator(voices: 2)
        #expect(!allocator.start(.next()).stolen)
        #expect(!allocator.start(.next()).stolen)
    }

    @Test func endingEverythingReleasesTheHeldVoicesOnly() {
        var allocator = VoiceAllocator(voices: 4)
        let notes = start(3, on: &allocator)
        _ = allocator.end(notes[0].id)
        #expect(allocator.endAll().sorted() == [notes[1].voice, notes[2].voice].sorted())
        #expect(allocator.endAll().isEmpty)
    }
}
