import AVFoundation
import Testing
@testable import Perfecto

/// The kernel in an engine running in real time, as the app runs it: the
/// one place a note's moment is turned into a frame by the real clock.
@MainActor
struct KernelLiveTests {

    /// The loudest sample the engine's mixer has put out.
    private final class Peak: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Float = 0
        func take(_ buffer: AVAudioPCMBuffer) {
            guard let data = buffer.floatChannelData else { return }
            let peak = loudest(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
            lock.withLock { value = max(value, peak) }
        }
        var heard: Float { lock.withLock { value } }

        /// Listens to `node`. The tap is called off the main thread, so it
        /// is made here, where nothing is the main actor's.
        nonisolated func listen(to node: AVAudioNode) {
            node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [self] buffer, _ in take(buffer) }
        }
    }

    /// The rate the simulator's output runs at.
    private func hardwareRate(_ graph: AudioGraph) -> Double {
        graph.engine.outputNode.outputFormat(forBus: 0).sampleRate
    }

    @Test func aNoteStampedNowIsHeard() async throws {
        let graph = AudioGraph()
        let sink = KernelSink(unit: graph.unit)
        let peak = Peak()
        peak.listen(to: graph.engine.mainMixerNode)
        let rate = hardwareRate(graph)
        try graph.start(sampleRate: rate)
        defer { graph.stop() }

        // The unit has rendered, so it knows what moment its frames are for.
        #expect(try await waitUntil { graph.unit.frame(atUptime: ProcessInfo.processInfo.systemUptime) != nil })
        let now = ProcessInfo.processInfo.systemUptime
        let frame = try #require(graph.unit.frame(atUptime: now))
        // "Now" is the frame being rendered, give or take the output's delay.
        #expect(abs(Double(frame) - Double(graph.unit.time)) < rate / 2,
                "frame \(frame) for now, while the unit is at \(graph.unit.time)")

        sink.noteOn(NoteID.next(), note: 60, sound: NoteSound(), at: now)
        #expect(try await waitUntil(timeout: .seconds(2)) { peak.heard > 0.01 })
    }

    @Test func whatTheUnitHearsCanBeRecordedAndPlayed() async throws {
        let graph = AudioGraph()
        let rate = hardwareRate(graph)
        graph.unit.setSound(0, to: SynthPreset.micSample.patch)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let source = Tone(hz: 440, rate: rate).node(format)
        try graph.start(sampleRate: rate, listeningTo: source)
        defer { graph.stop() }

        graph.unit.startCapture(0)
        #expect(try await waitUntil { graph.unit.capturing == 0 })
        try await Task.sleep(for: .milliseconds(300))
        graph.unit.stopCapture()
        #expect(try await waitUntil { graph.unit.capturing == nil })
        #expect(graph.unit.captureDuration(0) > 0.25)

        // The tone that went in is what was recorded, at full level.
        let recording = graph.unit.captured(0)
        #expect(recording.sampleRate == rate)
        #expect(abs(strength(of: 440, in: recording) - 1) < 0.05)
    }
}
