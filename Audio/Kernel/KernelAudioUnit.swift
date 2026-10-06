import AVFoundation
import PerfectoKernel
import PerfectoKernelHost

/// The audio kernel as an Audio Unit, so the engine can host it, render it
/// offline, and one day ship it as an extension.
///
/// It is a music effect: it has an audio input (for the mic, when capture
/// and the vocoder arrive) as well as its output. With nothing connected to
/// the input it renders as an instrument does.
///
/// Notes are not sent as MIDI. They go to the kernel as its own timed
/// events, which carry what MIDI cannot: an id for each note, and later its
/// sound. Time is the kernel's count of frames rendered (`time`); an event
/// takes effect on exactly the frame it names.
final class KernelAudioUnit: AUAudioUnit {

    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_MusicEffect,
        componentSubType: fourCharCode("pfkn"),
        componentManufacturer: fourCharCode("Pfct"),
        componentFlags: 0,
        componentFlagsMask: 0)

    /// Makes the unit as a node for an `AVAudioEngine`, with the unit
    /// itself for sending events to.
    @MainActor
    static func makeNode() -> (node: AVAudioUnit, unit: KernelAudioUnit) {
        if !isRegistered {
            AUAudioUnit.registerSubclass(KernelAudioUnit.self, as: componentDescription,
                                         name: "Perfecto: Kernel", version: 1)
            isRegistered = true
        }
        let node = AVAudioUnitEffect(audioComponentDescription: componentDescription)
        guard let unit = node.auAudioUnit as? KernelAudioUnit else {
            preconditionFailure("the kernel's Audio Unit was registered, so the engine makes that one")
        }
        return (node, unit)
    }

    @MainActor private static var isRegistered = false

    /// The most frames one render call may ask for.
    private static let maximumFrames: AUAudioFrameCount = 4096

    private let host = PerfectoKernelHost()
    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        // The engine sets the real format when it connects the unit.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = Self.maximumFrames
    }

    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    override var outputBusses: AUAudioUnitBusArray { outputBusArray }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        host.prepare(withSampleRate: outputBus.format.sampleRate,
                     channels: Int(outputBus.format.channelCount),
                     maximumFrames: maximumFramesToRender)
    }

    override var internalRenderBlock: AUInternalRenderBlock { host.renderBlock }

    // MARK: – Events

    /// Frames rendered since the unit was last readied to render.
    var time: UInt64 { perfecto_kernel_time(host.kernel) }

    /// The frame the unit renders for the moment `uptime` (seconds of the
    /// device's uptime), going by when its last render was for. A moment
    /// before the unit began gives frame 0. nil until it has rendered in
    /// real time: an engine rendering offline has no such moments.
    func frame(atUptime uptime: TimeInterval) -> UInt64? {
        let start = host.uptimeAtFrameZero
        guard start.isFinite else { return nil }
        return UInt64(max(0, ((uptime - start) * outputBus.format.sampleRate).rounded()))
    }

    /// The most sounds the kernel holds.
    static var soundCount: Int { Int(perfecto_kernel_sound_count()) }

    /// Makes `patch` sound number `number`, for notes to name. It builds
    /// the patch's waves, so it is for loading sounds before the engine
    /// starts, never while the unit is rendering.
    func setSound(_ number: Int, to patch: SynthPatch) {
        var patch = patch.kernelPatch
        perfecto_kernel_set_sound(host.kernel, Int32(number), &patch)
    }

    /// How a note is played, beyond its pitch and strength. A note keeps
    /// what it started with until it is changed (`noteChange`).
    struct Playing: Equatable, Sendable {
        /// From 0 (dark) to 1 (open: the sound as its patch makes it).
        var brightness: Float = 1
        /// How much chorus, from 0 (none) to 1.
        var chorus: Float = 0
        /// How much of the note goes into the reverb and not straight out,
        /// from 0 (dry) to 1 (the room alone).
        var reverb: Float = 0
    }

    /// Starts `note` (a MIDI note) under `id` on frame `time`, in sound
    /// number `sound`, between left (-1) and right (1) at `pan`; a frame
    /// already rendered means as soon as possible. Returns false if the
    /// kernel has too many events waiting and dropped this one.
    @discardableResult
    func noteOn(_ id: UInt64, note: Int, velocity: Float, sound: Int = 0, pan: Float = 0,
                playing: Playing = Playing(), at time: UInt64 = 0) -> Bool {
        send(PerfectoEvent(time: time, note_id: id, type: PerfectoEventNoteOn,
                           note: Int32(note), velocity: velocity, sound: Int32(sound),
                           brightness: playing.brightness, pan: pan,
                           chorus: playing.chorus, reverb: playing.reverb))
    }

    /// Ends the note `id` on frame `time`.
    @discardableResult
    func noteOff(_ id: UInt64, at time: UInt64 = 0) -> Bool {
        send(PerfectoEvent(time: time, note_id: id, type: PerfectoEventNoteOff, note: 0, velocity: 0,
                           sound: 0, brightness: 1, pan: 0, chorus: 0, reverb: 0))
    }

    /// Glides the sounding note `id` to `playing` from frame `time`.
    @discardableResult
    func noteChange(_ id: UInt64, to playing: Playing, at time: UInt64 = 0) -> Bool {
        send(PerfectoEvent(time: time, note_id: id, type: PerfectoEventNoteChange, note: 0, velocity: 0,
                           sound: 0, brightness: playing.brightness, pan: 0,
                           chorus: playing.chorus, reverb: playing.reverb))
    }

    // MARK: – The mix

    /// How fast the chorus wavers, in Hz: one speed for every note.
    func setChorusRate(_ hz: Float) {
        perfecto_kernel_set_chorus_rate(host.kernel, hz)
    }

    /// The seconds the reverb's tail takes to fall 60 dB: one room for every note.
    func setReverbTail(_ seconds: Float) {
        perfecto_kernel_set_reverb_tail(host.kernel, seconds)
    }

    /// Frames between an event's frame and its sound leaving the unit: the
    /// kernel's limiter looks that far ahead.
    var latencyFrames: Int { Int(perfecto_kernel_latency(host.kernel)) }

    override var latency: TimeInterval {
        Double(latencyFrames) / outputBus.format.sampleRate
    }

    private func send(_ event: PerfectoEvent) -> Bool {
        var event = event
        return perfecto_kernel_send(host.kernel, &event)
    }
}

/// The four-character code `text` spells, as Audio Unit identifiers are written.
private func fourCharCode(_ text: String) -> FourCharCode {
    precondition(text.utf8.count == 4, "a four-character code has four characters")
    return text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
}
