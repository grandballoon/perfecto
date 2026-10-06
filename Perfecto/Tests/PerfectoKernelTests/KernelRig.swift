import PerfectoKernel

/// A kernel rendering into memory: events go in, and every frame it has
/// rendered can be read back.
final class KernelRig {

    static let sampleRate = 48_000.0

    /// Everything rendered so far, first channel.
    private(set) var output: [Float] = []

    private let kernel = perfecto_kernel_create()!

    init() {
        perfecto_kernel_prepare(kernel, Self.sampleRate)
    }

    deinit {
        perfecto_kernel_destroy(kernel)
    }

    /// Frames rendered so far, as the kernel counts them.
    var time: Int { Int(perfecto_kernel_time(kernel)) }

    @discardableResult
    func noteOn(_ id: UInt64, note: Int = 69, velocity: Float = 1, at frame: Int = 0) -> Bool {
        var event = PerfectoEvent(time: UInt64(frame), note_id: id, type: PerfectoEventNoteOn,
                                  note: Int32(note), velocity: velocity)
        return perfecto_kernel_send(kernel, &event)
    }

    @discardableResult
    func noteOff(_ id: UInt64, at frame: Int = 0) -> Bool {
        var event = PerfectoEvent(time: UInt64(frame), note_id: id, type: PerfectoEventNoteOff,
                                  note: 0, velocity: 0)
        return perfecto_kernel_send(kernel, &event)
    }

    /// Renders `frames` more frames, `chunk` at a time, as an audio device
    /// with that buffer size would ask for them.
    func render(_ frames: Int, chunk: Int = 256) {
        render(chunks: stride(from: 0, to: frames, by: chunk).map { min(chunk, frames - $0) })
    }

    /// Renders one call per entry of `chunks`, each of that many frames.
    func render(chunks: [Int]) {
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
            precondition(left.prefix(frames).elementsEqual(right.prefix(frames)), "the channels differ")
            output += left.prefix(frames)
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

/// Frames in `seconds`.
func frames(_ seconds: Double) -> Int {
    Int(seconds * KernelRig.sampleRate)
}
