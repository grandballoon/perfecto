import AudioKit
import AVFoundation
import SoundpipeAudioKit

/// Records mic input and plays it back pitch-shifted via AudioPlayer → TimePitch.
/// Uses AudioKit's shared AVAudioEngine rather than a second engine instance — two
/// simultaneous AVAudioEngine instances corrupt the iOS audio session.
///
/// The tap callback runs on the audio thread; `recordingFile` is written there and
/// only ever accessed from MainActor after removeTap() guarantees no further writes.
@MainActor
final class MicSampler {

    let outputMixer = Mixer()

    private weak var sharedEngine: AudioEngine?
    private(set) var isRecording = false
    private(set) var sampleURL:   URL?
    var hasContent: Bool { sampleURL != nil }

    private let player:       AudioPlayer
    private let pitchShifter: TimePitch

    nonisolated(unsafe) private var recordingFile: AVAudioFile?
    private var pendingURL: URL?

    init(engine: AudioEngine) {
        self.sharedEngine = engine
        let p        = AudioPlayer()
        player       = p
        pitchShifter = TimePitch(p)
        outputMixer.addInput(pitchShifter)
    }

    // MARK: – Recording

    // Permission must be granted before calling — MicSampleMode checks via PermissionGate.
    func startRecording() {
        guard !isRecording, let engine = sharedEngine else { return }
        isRecording = true
        let inputNode = engine.avEngine.inputNode
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mic_\(Int(Date().timeIntervalSince1970)).caf")
        pendingURL = url

        player.stop()
        recordingFile = nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buf, _ in
            guard let self else { return }
            if self.recordingFile == nil {
                let settings: [String: Any] = [
                    AVFormatIDKey:               Int(kAudioFormatLinearPCM),
                    AVSampleRateKey:             buf.format.sampleRate,
                    AVNumberOfChannelsKey:       Int(buf.format.channelCount),
                    AVLinearPCMBitDepthKey:      32,
                    AVLinearPCMIsFloatKey:       true,
                    AVLinearPCMIsBigEndianKey:   false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
                do {
                    self.recordingFile = try AVAudioFile(forWriting: url, settings: settings)
                } catch {
                    print("[MicSampler] file create error: \(error)")
                }
            }
            do {
                try self.recordingFile?.write(from: buf)
            } catch {
                print("[MicSampler] write error: \(error)")
            }
        }
        print("[MicSampler] recording started")
    }

    func stopRecording() {
        guard isRecording, let engine = sharedEngine else { return }
        engine.avEngine.inputNode.removeTap(onBus: 0)
        isRecording   = false
        recordingFile = nil

        guard let url = pendingURL else { return }
        pendingURL = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[MicSampler] recording file missing at \(url.path)")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("[MicSampler] file size: \(size) bytes")

        do {
            try player.load(url: url, buffered: false)
            sampleURL = url
            print("[MicSampler] sample ready: \(url.lastPathComponent)")
        } catch {
            print("[MicSampler] load error: \(error)")
        }
    }

    // MARK: – Playback

    func play(semitones: Int) {
        guard hasContent else { return }
        player.stop()
        pitchShifter.pitch = AUValue(semitones * 100)
        player.play()
    }

    func stop() { player.stop() }

    func clear() {
        player.stop()
        sampleURL = nil
    }
}
