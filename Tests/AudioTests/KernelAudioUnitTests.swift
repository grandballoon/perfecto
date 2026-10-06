import AVFoundation
import Testing
@testable import Perfecto

/// The kernel hosted as an Audio Unit in an engine that renders offline:
/// what the app will hear from it. The kernel's own behaviour is tested
/// without an engine, in the Perfecto package (`PerfectoKernelTests`).
@Suite("KernelAudioUnit", .serialized)
@MainActor
struct KernelAudioUnitTests {

    /// An offline engine whose only source is the kernel's unit.
    @MainActor
    private final class Rig {
        static let rate = 48_000.0

        let engine = AVAudioEngine()
        let unit: KernelAudioUnit
        private(set) var output: [Float] = []
        private let buffer: AVAudioPCMBuffer

        init(bufferSize: AVAudioFrameCount) throws {
            let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2)!
            let made = KernelAudioUnit.makeNode()
            unit = made.unit
            engine.attach(made.node)
            engine.connect(made.node, to: engine.outputNode, format: format)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: bufferSize)
            try engine.start()
            buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: bufferSize)!
        }

        func render(_ frames: Int) throws {
            while output.count < frames {
                let wanted = min(buffer.frameCapacity, AVAudioFrameCount(frames - output.count))
                let status = try engine.renderOffline(wanted, to: buffer)
                #expect(status == .success)
                output += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            }
        }
    }

    /// Nothing is connected to the unit's input; it renders all the same.
    @Test(arguments: [64, 256, 1024] as [AVAudioFrameCount])
    func aNoteStartsOnTheFrameItNamesAtEveryBufferSize(bufferSize: AVAudioFrameCount) throws {
        let rig = try Rig(bufferSize: bufferSize)
        defer { rig.engine.stop() }

        rig.unit.noteOn(1, note: 69, velocity: 1, at: 1000)
        try rig.render(4800)

        #expect(loudest(rig.output[0...1000]) == 0)
        #expect(rig.output[1001] != 0)
        #expect(loudest(rig.output[2400...]) > 0.19)
        #expect(rig.unit.time >= 4800)
    }

    @Test func aNoteEndedDiesAway() throws {
        let rig = try Rig(bufferSize: 256)
        defer { rig.engine.stop() }

        rig.unit.noteOn(1, note: 69, velocity: 1)
        rig.unit.noteOff(1, at: 2400)
        try rig.render(9600)

        #expect(loudest(rig.output[1200..<2400]) > 0.19)
        #expect(loudest(rig.output[7200...]) == 0)
    }

    /// The engine's time and the kernel's are the same count of frames.
    @Test func theUnitsTimeIsTheFramesRendered() throws {
        let rig = try Rig(bufferSize: 256)
        defer { rig.engine.stop() }
        #expect(rig.unit.time == 0)
        try rig.render(2560)
        #expect(rig.unit.time == 2560)
    }
}
