import Accelerate

/// What a recording sounds like for matching it to its score: how strong
/// each of the twelve pitch classes is, a hundred times a second.
///
/// Each frame is a short-time spectrum (a Hann window of about 170 ms,
/// centred on the frame's moment) with every bin from A0 to about C8 added
/// into the pitch class of the note nearest it, and the sums compressed,
/// so a quiet note still counts beside a loud one. The window is long
/// enough to tell the semitones of the bass apart; the moment a note is
/// struck is found from how the classes rise frame to frame through a
/// short window as well (`rise`), which a strike reaches at once.
///
/// It is a pure function of the samples, done once when a recording is
/// added; matching it to the score (`AutoMatch`) is done again whenever
/// the pins change.
struct RecordingFeatures: Equatable, Sendable {
    static let rate = 100.0

    /// Twelve values a frame, C first, frame after frame, through the
    /// long window.
    let chroma: [Float]
    /// The same through a window of about 45 ms, which a note's strike
    /// reaches all at once: what `rise` reads.
    let strikes: [Float]
    let frames: Int

    var duration: Double { Double(frames) / Self.rate }

    /// The twelve values of frame `k`.
    func frame(_ k: Int) -> ArraySlice<Float> {
        chroma[(k * 12)..<(k * 12 + 12)]
    }

    /// How much pitch class `pc` rises into frame `k`: where a note of it
    /// is struck, this peaks.
    /// The rise is over the most it was in the frames just before
    /// (`riseLook`), not over the frame before alone: a note that only
    /// wavers as it dies away never rises above what it just was, so it
    /// is not taken for one struck.
    func rise(_ k: Int, _ pc: Int) -> Float {
        guard k > 0, k < frames, strikes.count == chroma.count else { return 0 }
        var before: Float = 0
        for back in 1...Self.riseLook where k - back >= 0 {
            before = max(before, strikes[(k - back) * 12 + pc])
        }
        return max(0, strikes[k * 12 + pc] - before)
    }

    /// How many frames before a rise it is measured against: 60 ms.
    static let riseLook = 6

    init(chroma: [Float], strikes: [Float]) {
        self.chroma = chroma
        self.strikes = strikes
        frames = chroma.count / 12
    }

    /// The features of `samples` (one channel) at `sampleRate`.
    static func analyze(_ samples: [Float], sampleRate: Double) -> RecordingFeatures {
        guard !samples.isEmpty, sampleRate > 0 else { return RecordingFeatures(chroma: [], strikes: []) }
        return RecordingFeatures(chroma: classes(of: samples, sampleRate: sampleRate, window: 0.17),
                                 strikes: classes(of: samples, sampleRate: sampleRate, window: 0.045))
    }

    /// The compressed pitch classes of `samples`, a frame each hundredth
    /// of a second, through a window of about `window` seconds.
    private static func classes(of samples: [Float], sampleRate: Double, window seconds: Double) -> [Float] {
        let peak = max(samples.map(abs).max() ?? 0, 1e-9)
        var size = 256
        while Double(size) < sampleRate * seconds { size *= 2 }
        let half = size / 2
        let log2n = vDSP_Length(size.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        // Which pitch class each bin is added into, or none.
        let classOf: [Int] = (0..<half).map { bin in
            let f = Double(bin) * sampleRate / Double(size)
            guard f > 26, f < 4500 else { return -1 }
            let midi = 69 + 12 * log2(f / 440)
            return ((Int(midi.rounded()) % 12) + 12) % 12
        }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size,
                                 isHalfWindow: false)
        let hop = sampleRate / rate
        let frames = Int(Double(samples.count) / hop) + 1
        var chroma = [Float](repeating: 0, count: frames * 12)
        var segment = [Float](repeating: 0, count: size)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        let scale = 1 / Float(peak)
        let gain = Float(2000) / Float(size)

        for k in 0..<frames {
            let start = Int((Double(k) * hop).rounded()) - half
            for i in 0..<size {
                let s = start + i
                segment[i] = s >= 0 && s < samples.count ? samples[s] * scale * window[i] : 0
            }
            real.withUnsafeMutableBufferPointer { re in
                imag.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    segment.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1,
                                  vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    power.withUnsafeMutableBufferPointer { p in
                        vDSP_zvmags(&split, 1, p.baseAddress!, 1, vDSP_Length(half))
                    }
                }
            }
            var sums = [Float](repeating: 0, count: 12)
            for bin in 1..<half where classOf[bin] >= 0 {
                sums[classOf[bin]] += power[bin].squareRoot()
            }
            for pc in 0..<12 {
                chroma[k * 12 + pc] = log1p(gain * sums[pc])
            }
        }
        return chroma
    }
}

/// What the score should sound like at a moment, in the same twelve
/// classes: each note sounding then, strongest as it is struck and dying
/// away as a piano's does, and fading for a moment after it ends, with a little of its fifth above (its third
/// harmonic, which a piano's tone has plenty of).
enum ScoreChroma {
    /// How long a struck note takes to fall to a third of its strength,
    /// in score seconds.
    static let decay = 1.5
    /// How long a note fades for after it ends, as a damper falls.
    static let release = 0.25

    /// The classes struck from score moment `from` until `to`; all zero
    /// where nothing is.
    static func struck(_ from: Double, _ to: Double, _ notes: [ScoreNote]) -> [Float] {
        var v = [Float](repeating: 0, count: 12)
        for note in notes where note.onset >= from && note.onset < to {
            v[note.pitch % 12] += 1
        }
        return v
    }

    /// The classes at score moment `t`; all zero where nothing sounds.
    static func at(_ t: Double, _ sounding: [ScoreNote]) -> [Float] {
        var v = [Float](repeating: 0, count: 12)
        for note in sounding where note.onset <= t + Score.sameTime && t < note.end + release {
            let fading = t > note.end ? 1 - (t - note.end) / release : 1
            let w = Float(exp(-(t - note.onset) / decay) * fading)
            let pc = note.pitch % 12
            v[pc] += w
            v[(pc + 7) % 12] += 0.3 * w
        }
        return v
    }
}
