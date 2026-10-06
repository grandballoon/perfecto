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

    @Test func aNoteStampedNowIsHeard() async throws {
        let engine = AVAudioEngine()
        let made = KernelAudioUnit.makeNode()
        let sink = KernelSink(unit: made.unit)
        engine.attach(made.node)
        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(made.node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2))
        let peak = Peak()
        peak.listen(to: engine.mainMixerNode)
        try engine.start()
        defer { engine.stop() }

        #expect(try await waitUntil(timeout: .seconds(2)) { made.unit.time > 0 }, "rendered \(made.unit.time) frames; engine running \(engine.isRunning); format \(format); max \(made.unit.maximumFramesToRender); allocated \(made.unit.renderResourcesAllocated)")
        // The unit has rendered, so it knows what moment its frames are for.
        #expect(try await waitUntil { made.unit.frame(atUptime: ProcessInfo.processInfo.systemUptime) != nil })
        let now = ProcessInfo.processInfo.systemUptime
        let frame = try #require(made.unit.frame(atUptime: now))
        // "Now" is the frame being rendered, give or take the output's delay.
        #expect(abs(Double(frame) - Double(made.unit.time)) < format.sampleRate / 2,
                "frame \(frame) for now, while the unit is at \(made.unit.time)")

        sink.noteOn(NoteID.next(), note: 60, sound: NoteSound(), at: now)
        #expect(try await waitUntil(timeout: .seconds(2)) { peak.heard > 0.01 })
    }
}
