import AVFoundation
import PerfectoKernel
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

        /// `sounds` are loaded before the engine starts, numbered from 0.
        init(bufferSize: AVAudioFrameCount, sounds: [SynthPatch] = []) throws {
            let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2)!
            let made = KernelAudioUnit.makeNode()
            unit = made.unit
            for (number, patch) in sounds.enumerated() { unit.setSound(number, to: patch) }
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

    // MARK: – Sounds

    /// Every sound the app ships plays through the kernel: it is heard, it
    /// stays well under full scale on its own, and it dies away at its
    /// release's pace once its note ends.
    @Test(arguments: SynthPreset.allCases)
    func everyPresetPlaysAsAKernelSound(_ preset: SynthPreset) throws {
        #expect(SynthPreset.allCases.count <= KernelAudioUnit.soundCount)
        // On its own, so no other sound's tail is in what is measured.
        let rig = try Rig(bufferSize: 256, sounds: [preset.patch])
        defer { rig.engine.stop() }

        // A note held for 0.4 s and given 2 s more.
        let (held, whole, after) = (19_200, 115_200, 2.0)
        rig.unit.noteOn(1, note: 60, velocity: 1, sound: 0)
        rig.unit.noteOff(1, at: UInt64(held))
        try rig.render(whole)

        let sounding = loudest(rig.output[..<held])
        #expect(sounding > 0.02, "it is heard")
        // A filter rings a little past its input, so a patch can peak over
        // its level; none comes near full scale alone.
        #expect(sounding < 0.6, "it leaves room: \(sounding)")
        #expect(rig.output.allSatisfy { $0.isFinite })
        // A release time is the time to fall to 37%: after 2 s the sound is
        // down by at least that many times over.
        let left = loudest(rig.output[(whole - 2400)...])
        let fallen = Float(exp(-(after - 0.05) / Double(preset.patch.envelope.release)))
        #expect(left <= max(sounding * fallen * 1.5, 0.0005), "it dies away: \(left)")
    }

    /// An FM pair becomes a carrier bent by a modulator that is not heard;
    /// oscillators become operators that are mixed.
    @Test func aPatchBecomesTwoOperators() {
        let piano = SynthPreset.electricPiano.patch.kernelPatch
        #expect(piano.modulates)
        #expect(piano.operators.0.wave == PerfectoWaveSine && piano.operators.0.ratio == 1)
        #expect(piano.operators.1.ratio == 1 && piano.index.from == 2.2 && piano.index.to == 0.5)
        #expect(!piano.filtered)

        let bass = SynthPreset.synthBass.patch.kernelPatch
        #expect(!bass.modulates && bass.filtered)
        #expect(bass.operators.0.wave == PerfectoWaveSawtooth && bass.operators.0.ratio == 1)
        #expect(bass.operators.1.wave == PerfectoWaveSquare && bass.operators.1.ratio == 0.5)   // an octave down
        #expect(bass.operators.1.level == 0.7)
        #expect(bass.cutoff.from == 10 && bass.cutoff.to == 3 && bass.resonance == 0.4)

        let pad = SynthPreset.warmPad.patch.kernelPatch
        #expect(abs(pad.operators.0.ratio - pow(2, -5.0 / 1200)) < 1e-6)
        #expect(abs(pad.operators.1.ratio - pow(2, 5.0 / 1200)) < 1e-6)

        let organ = SynthPreset.organ.patch.kernelPatch
        #expect(organ.operators.0.wave == PerfectoWavePartials)
        #expect(organ.operators.0.partials.0 == 1 && organ.operators.0.partials.1 == 0.8)
        #expect(organ.operators.1.level == 0)                                // unused

        let clav = SynthPreset.clav.patch.kernelPatch
        #expect(clav.operators.0.wave == PerfectoWavePulse && clav.operators.0.pulse_width == 0.2)
    }

    /// No sound the app ships is both oscillators and an FM pair, which the
    /// kernel's two operators could not be.
    @Test func everyPresetFitsInTwoOperators() {
        for preset in SynthPreset.allCases {
            let patch = preset.patch
            #expect(patch.fm == nil || patch.oscillators.isEmpty, "\(preset.name)")
            #expect(patch.oscillators.count <= SynthPatch.oscillatorCount, "\(preset.name)")
        }
    }

    // MARK: – Time

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
