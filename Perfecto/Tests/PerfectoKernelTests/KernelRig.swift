import Foundation
import PerfectoKernel

/// A kernel rendering into memory: events go in, and every frame it has
/// rendered can be read back.
///
/// The kernel's limiter makes everything `latency` frames late. The rig
/// takes that out: `output[f]` is what an event on frame `f` makes, so
/// tests say when things happen and not when they come out. To have those
/// frames it renders `latency` frames further than it is asked to, so the
/// kernel's own count (`time`) runs that far ahead of what was asked for.
final class KernelRig {

    static let sampleRate = 48_000.0

    /// Everything rendered so far, left and right, by the frame it belongs to.
    private(set) var output: [Float] = []
    private(set) var right: [Float] = []

    private let kernel = perfecto_kernel_create()!
    private var discarded = 0

    init() {
        perfecto_kernel_prepare(kernel, Self.sampleRate)
    }

    deinit {
        perfecto_kernel_destroy(kernel)
    }

    /// Frames rendered so far, as the kernel counts them.
    var time: Int { Int(perfecto_kernel_time(kernel)) }

    /// Frames between an event and its sound.
    var latency: Int { Int(perfecto_kernel_latency(kernel)) }

    @discardableResult
    func noteOn(_ id: UInt64, note: Int = 69, velocity: Float = 1, sound: Int = 0, brightness: Float = 1,
                pan: Float = 0, chorus: Float = 0, reverb: Float = 0, at frame: Int = 0) -> Bool {
        var event = PerfectoEvent(time: UInt64(frame), note_id: id, type: PerfectoEventNoteOn,
                                  note: Int32(note), velocity: velocity, sound: Int32(sound),
                                  brightness: brightness, pan: pan, chorus: chorus, reverb: reverb)
        return perfecto_kernel_send(kernel, &event)
    }

    /// Changes how a sounding note is played.
    @discardableResult
    func noteChange(_ id: UInt64, brightness: Float = 1, chorus: Float = 0, reverb: Float = 0,
                    at frame: Int = 0) -> Bool {
        var event = PerfectoEvent(time: UInt64(frame), note_id: id, type: PerfectoEventNoteChange,
                                  note: 0, velocity: 0, sound: 0,
                                  brightness: brightness, pan: 0, chorus: chorus, reverb: reverb)
        return perfecto_kernel_send(kernel, &event)
    }

    /// Makes `patch` sound number `sound`.
    func setSound(_ sound: Int, _ patch: PerfectoPatch) {
        var patch = patch
        perfecto_kernel_set_sound(kernel, Int32(sound), &patch)
    }

    func setChorusRate(_ hz: Float) { perfecto_kernel_set_chorus_rate(kernel, hz) }
    func setReverbTail(_ seconds: Float) { perfecto_kernel_set_reverb_tail(kernel, seconds) }

    @discardableResult
    func noteOff(_ id: UInt64, at frame: Int = 0) -> Bool {
        var event = PerfectoEvent(time: UInt64(frame), note_id: id, type: PerfectoEventNoteOff,
                                  note: 0, velocity: 0, sound: 0, brightness: 1, pan: 0, chorus: 0, reverb: 0)
        return perfecto_kernel_send(kernel, &event)
    }

    /// Renders `frames` more frames, `chunk` at a time, as an audio device
    /// with that buffer size would ask for them.
    func render(_ frames: Int, chunk: Int = 256) {
        render(chunks: stride(from: 0, to: frames, by: chunk).map { min(chunk, frames - $0) })
    }

    /// Renders one call per entry of `chunks`, each of that many frames
    /// (and, the first time, the limiter's delay more in a call of its own).
    func render(chunks: [Int]) {
        let chunks = time == 0 ? chunks + [latency] : chunks
        var left = [Float](repeating: 0, count: chunks.max() ?? 0)
        var right = left
        for frames in chunks {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    let channels: [UnsafeMutablePointer<Float>?] = [l.baseAddress, r.baseAddress]
                    channels.withUnsafeBufferPointer {
                        perfecto_kernel_render(kernel, nil, 0, $0.baseAddress, 2, Int32(frames))
                    }
                }
            }
            // The first `latency` frames out belong to no frame in.
            let skipped = min(latency - discarded, frames)
            discarded += skipped
            output += left[skipped..<frames]
            self.right += right[skipped..<frames]
        }
    }

    /// The loudest sample in `range`.
    func loudest(_ range: Range<Int>) -> Float {
        output[range].map(abs).max() ?? 0
    }

    /// The biggest step from one sample to the next in `range`: a click is
    /// a step far bigger than the sound's own slope.
    func biggestStep(_ range: Range<Int>) -> Float {
        zip(output[range], output[range].dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }
}

extension KernelRig {
    /// How strong the sine at `hz` is in `range`: its amplitude, found by
    /// laying a sine and a cosine of that pitch over the sound.
    func strength(of hz: Double, in range: Range<Int>) -> Double {
        var (sine, cosine) = (0.0, 0.0)
        for frame in range {
            let angle = 2 * Double.pi * hz * Double(frame) / Self.sampleRate
            sine += Double(output[frame]) * sin(angle)
            cosine += Double(output[frame]) * cos(angle)
        }
        return 2 * (sine * sine + cosine * cosine).squareRoot() / Double(range.count)
    }

    /// The root mean square of `range`.
    func power(_ range: Range<Int>) -> Double {
        (output[range].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(range.count)).squareRoot()
    }

    /// What is left of `range`, as a root mean square, once every sine in
    /// `pitches` has been taken out of it: for a wave of one pitch, whatever
    /// is not one of its partials.
    func remainder(without pitches: [Double], in range: Range<Int>) -> Double {
        var rest = range.map { Double(output[$0]) }
        for hz in pitches {
            var (sine, cosine) = (0.0, 0.0)
            for (index, frame) in range.enumerated() {
                let angle = 2 * Double.pi * hz * Double(frame) / Self.sampleRate
                sine += rest[index] * sin(angle)
                cosine += rest[index] * cos(angle)
            }
            sine *= 2 / Double(range.count)
            cosine *= 2 / Double(range.count)
            for (index, frame) in range.enumerated() {
                let angle = 2 * Double.pi * hz * Double(frame) / Self.sampleRate
                rest[index] -= sine * sin(angle) + cosine * cos(angle)
            }
        }
        return (rest.reduce(0) { $0 + $1 * $1 } / Double(rest.count)).squareRoot()
    }
}

/// The frequency of a MIDI note.
func hz(_ note: Int) -> Double {
    440 * pow(2, Double(note - 69) / 12)
}

/// Patches for tests: one operator held at full level unless said otherwise.
extension PerfectoPatch {
    static func wave(_ wave: PerfectoWave, pulseWidth: Float = 0.5, partials: [Float] = [],
                     level: Float = 0.5) -> PerfectoPatch {
        var patch = PerfectoPatch()
        patch.operators.0.wave = wave
        patch.operators.0.pulse_width = pulseWidth
        withUnsafeMutableBytes(of: &patch.operators.0.partials) { bytes in
            let slots = bytes.bindMemory(to: Float.self)
            for (index, partial) in partials.enumerated() where index < slots.count { slots[index] = partial }
        }
        patch.operators.0.ratio = 1
        patch.operators.0.level = 1
        patch.attack = 0.003
        patch.decay = 0.05
        patch.sustain = 1
        patch.release = 0.006
        patch.level = level
        return patch
    }

    /// A sine bent by a second sine at `ratio` times its pitch.
    static func modulated(ratio: Float, index: PerfectoSweep) -> PerfectoPatch {
        var patch = wave(PerfectoWaveSine)
        patch.operators.1.wave = PerfectoWaveSine
        patch.operators.1.ratio = ratio
        patch.operators.1.level = 1
        patch.modulates = true
        patch.index = index
        return patch
    }

    func filtered(cutoff: PerfectoSweep, resonance: Float = 0) -> PerfectoPatch {
        var patch = self
        patch.filtered = true
        patch.cutoff = cutoff
        patch.resonance = resonance
        return patch
    }

    func envelope(attack: Float, decay: Float, sustain: Float, release: Float) -> PerfectoPatch {
        var patch = self
        (patch.attack, patch.decay, patch.sustain, patch.release) = (attack, decay, sustain, release)
        return patch
    }
}

extension PerfectoSweep {
    static func steady(_ value: Float) -> PerfectoSweep {
        PerfectoSweep(from: value, to: value, time: 0)
    }
}

/// Frames in `seconds`.
func frames(_ seconds: Double) -> Int {
    Int(seconds * KernelRig.sampleRate)
}
