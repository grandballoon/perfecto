import Testing
@testable import Perfecto

/// The rules both clocks time and order their calls by.
@Suite("ClockSchedule")
@MainActor
struct ClockScheduleTests {

    /// 120 BPM: a beat is half a second, a tick an eighth of one.
    private let schedule = ClockSchedule(bpm: 120)

    @Test func callsAreMadeInTheOrderTheyFallDue() {
        var made: [String] = []
        _ = schedule.after(seconds: 0.3) { made.append("third") }
        _ = schedule.after(seconds: 0.1) { made.append("first") }
        _ = schedule.after(beats: 0.4, first: false) { made.append("second") }   // 0.2 s

        schedule.run(until: 0.25)
        #expect(made == ["first", "second"])
        schedule.run(until: 1)
        #expect(made == ["first", "second", "third"])
        #expect(schedule.pendingCount == 0)
    }

    @Test func callsDueTogetherAreMadeInTheOrderTheyWereAskedFor() {
        var made: [Int] = []
        for i in 0..<5 { _ = schedule.after(seconds: 0.1) { made.append(i) } }
        schedule.run(until: 0.1)
        #expect(made == [0, 1, 2, 3, 4])
    }

    /// Whatever a tick starts can cancel a call before it acts on what the
    /// tick replaced, even if the call was asked for first.
    @Test func aTickComesBeforeACallDueAtTheSameMoment() {
        var made: [String] = []
        let call = schedule.every(beats: 0.25) { made.append("call") }
        schedule.onTick { made.append("tick") }
        schedule.startTicks()

        schedule.run(until: 0.125)
        #expect(made == ["tick", "call"])

        made = []
        schedule.onTick { call.cancel() }
        schedule.run(until: 0.25)
        #expect(made.isEmpty)
    }

    /// What starts a chord goes ahead of what continues one, however late
    /// it was asked for.
    @Test func aCallAskedForAsFirstComesBeforeTheOthersDueWithIt() {
        var made: [String] = []
        _ = schedule.every(beats: 1) { made.append("continues") }
        _ = schedule.after(beats: 1, first: true) { made.append("starts") }
        schedule.run(until: 0.5)
        #expect(made == ["starts", "continues"])
    }

    /// Inside a call "now" is the call's own time, so a chain of calls each
    /// asking for the next lands exactly on its times however late the
    /// schedule is run.
    @Test func aCallAskedForInsideACallIsTimedFromThatCall() {
        var times: [Double] = []
        func chain() {
            times.append(schedule.now)
            if times.count < 4 { _ = schedule.after(seconds: 0.1) { chain() } }
        }
        _ = schedule.after(seconds: 0.1) { chain() }

        schedule.run(until: 5)
        #expect(times.count == 4)
        for (i, time) in times.enumerated() {
            #expect(abs(time - 0.1 * Double(i + 1)) < 1e-9)
        }
        #expect(schedule.now == 5)
    }

    @Test func aRepeatKeepsToItsSpacing() {
        var times: [Double] = []
        _ = schedule.every(beats: 1 / 3) { times.append(schedule.now) }
        schedule.run(until: 1)
        #expect(times.count == 6)
        #expect(abs(times[5] - 1) < 1e-9)
    }

    @Test func aCancelledCallIsNotMadeAndCancellingTwiceIsHarmless() {
        var made = 0
        let once = schedule.after(seconds: 0.1) { made += 1 }
        let repeating = schedule.every(beats: 1) { made += 1 }
        once.cancel(); once.cancel()
        repeating.cancel()
        #expect(schedule.pendingCount == 0)
        schedule.run(until: 10)
        #expect(made == 0)
    }

    /// A call so many beats away stays that many beats away; a call so many
    /// seconds away does not move.
    @Test func aTempoChangeMovesWhatIsTimedInBeatsOnly() {
        var made: [String] = []
        _ = schedule.after(beats: 1, first: false) { made.append("beat") }       // 0.5 s at 120
        _ = schedule.after(seconds: 0.5) { made.append("second") }
        schedule.run(until: 0.25)                                   // half a beat gone
        schedule.bpm = 60                                           // the other half now takes 0.5 s

        schedule.run(until: 0.5)
        #expect(made == ["second"])
        schedule.run(until: 0.74)
        #expect(made == ["second"])
        schedule.run(until: 0.75)
        #expect(made == ["second", "beat"])
    }

    @Test func ticksRunOnlyWhileStarted() {
        var ticks = 0
        schedule.onTick { ticks += 1 }
        schedule.run(until: 1)
        #expect(ticks == 0)

        schedule.startTicks()
        schedule.startTicks()                // already ticking: no second set of ticks
        schedule.run(until: 2)
        #expect(ticks == 8)                  // four to a beat, two beats to a second

        schedule.stopTicks()
        schedule.run(until: 3)
        #expect(ticks == 8)
        #expect(schedule.nextDue == nil)
    }

    /// The real clock after the app was held up: one late call, then back
    /// in step, not a burst of everything that was missed.
    @Test func aRepeatThatFellFarBehindIsMadeOnceAndPicksUpFromNow() {
        var made = 0
        _ = schedule.every(beats: 1) { made += 1 }                  // every 0.5 s
        schedule.run(until: 10, skippingMissed: true)
        #expect(made == 1)
        #expect(schedule.nextDue == 10.5)
    }

    @Test func aRepeatOnlySlightlyLateKeepsItsPlace() {
        var made = 0
        _ = schedule.every(beats: 1) { made += 1 }
        schedule.run(until: 0.52, skippingMissed: true)
        #expect(made == 1)
        #expect(schedule.nextDue == 1.0)
    }

    /// A call asked for from outside is timed from when it was asked for.
    @Test func settlingMovesNowWithoutMakingCalls() {
        var made = 0
        _ = schedule.after(seconds: 0.1) { made += 1 }
        schedule.settle(at: 0.3)
        #expect(made == 0)
        #expect(schedule.now == 0.3)

        var second = 0.0
        _ = schedule.after(seconds: 0.1) { second = schedule.now }
        schedule.run(until: 1)
        #expect(made == 1)
        #expect(abs(second - 0.4) < 1e-9)
    }

    /// Where a playhead is: time as the tempo has counted it.
    @Test func theMusicalPositionMovesAtTheTempo() {
        schedule.run(until: 1)                                      // 120 BPM: two beats
        #expect(abs(schedule.beats - 2) < 1e-9)
        schedule.bpm = 60
        schedule.run(until: 3)                                      // two more seconds, two more beats
        #expect(abs(schedule.beats - 4) < 1e-9)
    }

    /// Inside a call the position is the call's own, like the time.
    @Test func insideACallThePositionIsTheCallsOwn() {
        var position = 0.0
        _ = schedule.after(beats: 1.5, first: false) { position = schedule.beats }
        schedule.run(until: 10)
        #expect(abs(position - 1.5) < 1e-9)
    }
}
