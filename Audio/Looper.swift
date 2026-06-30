import AudioKit
import AVFoundation

/// Two-track audio looper.
/// AudioPlayer nodes are pre-wired into outputMixer at init so the audio graph
/// is fully connected before engine.start() — no dynamic graph changes at runtime.
@MainActor
final class Looper {

    let outputMixer = Mixer()

    private let synthSource: Node
    private var recorders:   [NodeRecorder?]
    private var players:     [AudioPlayer]
    private var trackVolumes: [Float]

    init(synthSource: Node, trackCount: Int = 2) {
        self.synthSource  = synthSource
        recorders         = Array(repeating: nil, count: trackCount)
        trackVolumes      = Array(repeating: 1,   count: trackCount)
        players           = (0..<trackCount).map { _ in AudioPlayer() }
        for p in players { outputMixer.addInput(p) }
    }

    // MARK: – Recording

    func startRecording(_ track: Int) throws {
        guard track < players.count else { return }
        recorders[track]?.stop()
        recorders[track] = nil

        // Read the sample rate from the node's live output format — the most
        // reliable source of the engine's actual running rate. NodeRecorder
        // creates its file using Settings.sampleRate; if that stays at AudioKit's
        // 44100 default while the iPhone hardware runs at 48000, the file is
        // mislabeled and loops play back ~1.5 semitones flat.
        Settings.sampleRate = synthSource.avAudioNode.outputFormat(forBus: 0).sampleRate

        let rec = try NodeRecorder(node: synthSource)
        recorders[track] = rec
        try rec.record()
        print("[Looper] track \(track) recording started")
    }

    func stopRecording(_ track: Int) {
        guard track < players.count, let rec = recorders[track], rec.isRecording else { return }
        rec.stop()
        print("[Looper] track \(track) recording stopped")
    }

    // MARK: – Playback

    func startPlayback(_ track: Int) {
        guard track < players.count, let url = recorders[track]?.audioFile?.url else { return }
        players[track].stop()
        do {
            // Build the PCM buffer directly from the file so we can call
            // AudioPlayer.load(buffer:) instead of load(url:buffered:).
            // load(url:buffered:) only reconnects the playerNode to the graph when
            // the file format *changes from a previously loaded file*; on the first
            // load the node stays wired at AVAudioPlayerNode's default 44100 Hz
            // (set when the empty player was added to the mixer at init time).
            // load(buffer:) always checks playerNode.outputFormat vs buffer.format
            // and reconnects if they differ — fixing the 44100/48000 mismatch that
            // pitches the loop down ~1.5 semitones.
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                print("[Looper] track \(track) buffer alloc failed")
                return
            }
            try file.read(into: buffer)
            applyLoopFades(to: buffer)
            // AudioKit's load(buffer:) only calls makeInternalConnections() when the buffer
            // format differs from the player's current output format.  On the first load the
            // format changes from 44.1 → 48 kHz, so makeInternalConnections() fires and the
            // player node is (re)connected at the correct rate.  On every subsequent load both
            // sides are already 48 kHz, so makeInternalConnections() is skipped — but we still
            // need to temporarily break the connection so it is re-established at the buffer's
            // actual format rather than the stale default.  After load() we therefore check
            // whether the connection was restored; if not, we reconnect explicitly.
            if let engine = players[track].mixerNode.engine {
                engine.disconnectNodeOutput(players[track].playerNode)
            }
            players[track].load(buffer: buffer)
            // Restore the playerNode → mixerNode connection if makeInternalConnections()
            // did not run (same-format reload case).
            if let engine = players[track].mixerNode.engine,
               engine.outputConnectionPoints(for: players[track].playerNode, outputBus: 0).isEmpty {
                engine.connect(players[track].playerNode,
                               to: players[track].mixerNode,
                               format: buffer.format)
            }
            players[track].isLooping = true
            players[track].volume    = trackVolumes[track]
            players[track].play()
            print("[Looper] track \(track) playback started from \(url.lastPathComponent)")
        } catch {
            print("[Looper] track \(track) load error: \(error)")
        }
    }

    func stopPlayback(_ track: Int) {
        guard track < players.count else { return }
        players[track].stop()
    }

    // MARK: – Track management

    func clearTrack(_ track: Int) {
        guard track < players.count else { return }
        recorders[track]?.stop()
        recorders[track]  = nil
        players[track].stop()
        trackVolumes[track]   = 1
        players[track].volume = 1
    }

    func setVolume(_ track: Int, _ volume: Float) {
        guard track < players.count else { return }
        trackVolumes[track]   = volume
        players[track].volume = AUValue(volume)
    }

    func setMute(_ track: Int, _ muted: Bool) {
        guard track < players.count else { return }
        players[track].volume = muted ? 0 : AUValue(trackVolumes[track])
    }

    // MARK: – Private helpers

    // Applies 256-frame raised-cosine fade-in/out to eliminate the click at loop boundaries.
    // The buffer is modified in place; the source file is untouched.
    private func applyLoopFades(to buffer: AVAudioPCMBuffer, fadeFrames: Int = 256) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > fadeFrames * 2 else { return }
        let channelCount = Int(buffer.format.channelCount)
        for ch in 0..<channelCount {
            let samples = channelData[ch]
            for i in 0..<fadeFrames {
                let t = Float(i) / Float(fadeFrames)
                samples[i] *= 0.5 * (1.0 - cosf(.pi * t))
            }
            for i in 0..<fadeFrames {
                let t = Float(i) / Float(fadeFrames)
                samples[frameLength - 1 - i] *= 0.5 * (1.0 - cosf(.pi * t))
            }
        }
    }
}
