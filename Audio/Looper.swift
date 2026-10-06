import AudioKit
import AVFoundation

/// A layered audio looper.
///
/// The first take recorded sets the loop's length. Every later take is folded
/// onto that length at the point in the loop where it was played, and all
/// tracks start on the same sample grid, so layers stay in time with each
/// other for as long as they play. The length lasts until every track is
/// empty again.
///
/// A loop keeps the effects it was closed with. Each track plays through its
/// own `EffectsChain`, set from `liveEffects` when its take ends and left
/// alone after that, so a loop keeps its chorus and its share of the reverb
/// whatever is chosen later, whether it plays on or is stopped and started
/// again. The reverb's size is not a loop's own: there is one `SharedReverb`.
///
/// All timing is in sample times on the capture point's clock (`LoopCapture`
/// stamps takes with it): loop cycles begin at `anchor`, every `period`
/// frames. Players and their effects are pre-wired into `outputMixer` and
/// `reverbSend` at init, so the audio graph never changes at runtime.
@MainActor
final class Looper: LoopTracks {

    /// Every track's sound, less what goes to the reverb.
    let outputMixer = Mixer()
    /// What every track sends to the reverb.
    let reverbSend = Mixer()
    let trackCount: Int

    /// The effects on what is being played now: what the next take to end
    /// will keep.
    var liveEffects = SoundEffects()

    /// The shortest first take that becomes a loop. Anything shorter is an
    /// accidental double tap, and too short to hand over to playback cleanly.
    static let minimumSeconds: Double = 0.5

    /// Frames faded at a take's two ends, so a take that starts or stops
    /// mid-note doesn't click.
    private static let fadeFrames = 256

    private struct Track {
        /// The loop, exactly one period long; nil while empty or still being recorded.
        var samples: [[Float]]?
        /// True from the moment a take is kept, before its samples arrive.
        var hasTake = false
        /// Whether the track should be sounding once it has samples.
        var isPlaying = false
        var volume: Float = 1
        var isMuted = false
        /// Bumped whenever the track is cleared or re-recorded, so a take
        /// that finishes afterwards is dropped.
        var generation = 0
        /// Set while the first take's opening frames are already playing and
        /// the rest of it is still arriving: how many frames were scheduled.
        var headFrames: Int?
    }

    private let capture: LoopCapture
    private let players: [LoopPlayer]
    /// Each track's own effects, after its player.
    private let effects: [EffectsChain]
    private let logger: (any Logger)?
    private let scheduleLead: () -> TimeInterval

    private var tracks: [Track]
    private var recordingTrack: Int?
    private var period: Int?
    private var anchor: AVAudioFramePosition = 0

    /// - Parameter scheduleLead: how far ahead of the clock's last reading a
    ///   start must be scheduled to land on time. The reading can be one
    ///   render cycle old, and the start has to be queued before the cycle
    ///   that contains it begins.
    init(capture: LoopCapture,
         trackCount: Int,
         logger: (any Logger)? = nil,
         scheduleLead: @escaping () -> TimeInterval = {
             max(0.01, 3 * AVAudioSession.sharedInstance().ioBufferDuration)
         }) {
        self.capture = capture
        self.trackCount = trackCount
        self.logger = logger
        self.scheduleLead = scheduleLead
        tracks = Array(repeating: Track(), count: trackCount)
        players = (0..<trackCount).map { _ in LoopPlayer() }
        effects = players.map { EffectsChain($0) }
        for chain in effects {
            outputMixer.addInput(chain.dry)
            reverbSend.addInput(chain.reverbSend)
        }
    }

    // MARK: – Recording

    func startRecording(_ track: Int) throws {
        guard tracks.indices.contains(track), recordingTrack == nil else { return }
        try capture.begin()
        resetTrack(track)
        recordingTrack = track
        logger?.log(.loop_record_started(track: track))
    }

    /// Ends the take on `track` now and starts it looping. Returns false if
    /// the take was dropped (nothing recorded, or too short to be a loop).
    @discardableResult
    func stopRecording(_ track: Int) -> Bool {
        guard recordingTrack == track else { return false }
        recordingTrack = nil
        guard let stop = capture.now?.sampleTime, let partial = capture.snapshot() else {
            return discard(track, reason: "nothing recorded")
        }
        guard players[track].playerNode.outputFormat(forBus: 0).sampleRate == partial.sampleRate else {
            return discard(track, reason: "sample rate mismatch")
        }
        effects[track].apply(liveEffects)
        tracks[track].hasTake = true
        tracks[track].isPlaying = true
        let generation = tracks[track].generation

        if period == nil {
            let length = Int(stop - partial.start)
            guard length >= Int(Self.minimumSeconds * partial.sampleRate) else {
                return discard(track, reason: "too short")
            }
            period = length
            // The loop comes round as soon as a start can be scheduled, and
            // plays what has arrived so far; the last few frames of the take
            // are still in flight and are queued behind it when they land.
            let start = stop + leadFrames(partial.sampleRate)
            anchor = start
            // The loop's last frames are faded out, and the opening frames
            // must sound exactly as the finished loop will: so they stop
            // short of that fade unless the whole take is already here, in
            // which case they are the finished loop.
            let isWhole = partial.frameCount >= length
            let headFrames = isWhole ? length : min(partial.frameCount, max(0, length - Self.fadeFrames))
            var head = LoopMath.fitted(partial.channels, to: headFrames)
            LoopMath.fadeIn(&head, frames: Self.fadeFrames)
            if isWhole { LoopMath.fadeOut(&head, frames: Self.fadeFrames) }
            if players[track].start([head], loop: nil, at: playerTime(start, for: players[track])) {
                tracks[track].headFrames = head.first?.count ?? 0
            }
            capture.end(at: stop) { [weak self] take in
                self?.finishFirstTake(take, track: track, generation: generation)
            }
        } else {
            capture.end(at: stop) { [weak self] take in
                self?.finishOverdub(take, track: track, generation: generation)
            }
        }
        return true
    }

    // MARK: – Playback

    /// Starts `track` in time with the loop. Does nothing if it is already playing.
    func startPlayback(_ track: Int) {
        guard tracks.indices.contains(track), !tracks[track].isPlaying else { return }
        tracks[track].isPlaying = true
        playInPhase(track)
    }

    func stopPlayback(_ track: Int) {
        guard tracks.indices.contains(track) else { return }
        tracks[track].isPlaying = false
        tracks[track].headFrames = nil
        players[track].stop()
    }

    // MARK: – Track management

    func clearTrack(_ track: Int) {
        guard tracks.indices.contains(track) else { return }
        if recordingTrack == track {
            capture.cancel()
            recordingTrack = nil
        }
        resetTrack(track)
        logger?.log(.loop_cleared(track: track))
        if recordingTrack == nil, !tracks.contains(where: \.hasTake) {
            period = nil
        }
    }

    func setVolume(_ track: Int, _ volume: Float) {
        guard tracks.indices.contains(track) else { return }
        tracks[track].volume = volume
        applyVolume(track)
    }

    func setMute(_ track: Int, _ muted: Bool) {
        guard tracks.indices.contains(track) else { return }
        tracks[track].isMuted = muted
        applyVolume(track)
    }

    /// Call after the audio engine has stopped and started again. Stopping it
    /// stops every player, drops the take in progress and restarts the sample
    /// clock, so the loop is given a new starting point and the tracks that
    /// were playing are started on it together.
    func engineDidRestart() {
        capture.cancel()
        if let track = recordingTrack {
            recordingTrack = nil
            discard(track, reason: "engine restarted")
        }
        for track in tracks.indices { tracks[track].headFrames = nil }
        guard period != nil, let now = capture.now else { return }
        anchor = now.sampleTime + leadFrames(now.sampleRate)
        for track in tracks.indices where tracks[track].isPlaying {
            playInPhase(track)
        }
    }

    // MARK: – Private: finishing takes

    private func finishFirstTake(_ take: LoopTake, track: Int, generation: Int) {
        guard tracks[track].generation == generation, let period else { return }
        var loop = LoopMath.fitted(take.channels, to: period)
        LoopMath.fadeIn(&loop, frames: Self.fadeFrames)
        LoopMath.fadeOut(&loop, frames: Self.fadeFrames)
        tracks[track].samples = loop
        logger?.log(.loop_recorded(track: track,
                                   seconds: Double(period) / take.sampleRate,
                                   setsLength: true))

        guard tracks[track].isPlaying else { return }
        // Queue the rest of the take behind the opening frames that are
        // already playing, unless those have run out (or never started), in
        // which case join the loop where it should be by now.
        if let head = tracks[track].headFrames,
           let now = capture.now?.sampleTime,
           now + leadFrames(take.sampleRate) < anchor + AVAudioFramePosition(head) {
            let rest = head < period ? [loop.map { Array($0[head...]) }] : []
            players[track].enqueue(rest, loop: loop)
        } else {
            playInPhase(track)
        }
        tracks[track].headFrames = nil
    }

    private func finishOverdub(_ take: LoopTake, track: Int, generation: Int) {
        guard tracks[track].generation == generation, let period else { return }
        var channels = take.channels
        LoopMath.fadeIn(&channels, frames: Self.fadeFrames)
        LoopMath.fadeOut(&channels, frames: Self.fadeFrames)
        let offset = LoopMath.phase(of: take.start, anchor: anchor, period: period)
        tracks[track].samples = LoopMath.fold(channels, offset: offset, period: period)
        logger?.log(.loop_recorded(track: track,
                                   seconds: Double(take.frameCount) / take.sampleRate,
                                   setsLength: false))
        if tracks[track].isPlaying { playInPhase(track) }
    }

    @discardableResult
    private func discard(_ track: Int, reason: String) -> Bool {
        capture.cancel()
        resetTrack(track)
        logger?.log(.loop_take_discarded(track: track, reason: reason))
        return false
    }

    private func resetTrack(_ track: Int) {
        players[track].stop()
        tracks[track] = Track(generation: tracks[track].generation + 1)
        applyVolume(track)
    }

    // MARK: – Private: playback

    /// Starts `track` a moment from now at the point the loop will have
    /// reached, so it lines up with every other track.
    private func playInPhase(_ track: Int) {
        guard let loop = tracks[track].samples, let period, let now = capture.now else { return }
        let start = now.sampleTime + leadFrames(now.sampleRate)
        let phase = LoopMath.phase(of: start, anchor: anchor, period: period)
        let rest = phase > 0 ? [loop.map { Array($0[phase...]) }] : []
        applyVolume(track)
        players[track].start(rest, loop: loop, at: playerTime(start, for: players[track]))
    }

    private func applyVolume(_ track: Int) {
        players[track].volume = tracks[track].isMuted ? 0 : tracks[track].volume
    }

    private func leadFrames(_ sampleRate: Double) -> AVAudioFramePosition {
        AVAudioFramePosition((scheduleLead() * sampleRate).rounded(.up))
    }

    /// `sampleTime` on the capture clock, as a time on `player`'s own clock.
    /// Nodes of one engine count samples alike, but two readings may be taken
    /// a render cycle apart; the host times that come with them say by how much.
    private func playerTime(_ sampleTime: AVAudioFramePosition, for player: LoopPlayer) -> AVAudioTime? {
        guard let source = capture.now,
              let target = player.playerNode.lastRenderTime, target.isSampleTimeValid else { return nil }
        var offset = target.sampleTime - source.sampleTime
        if source.isHostTimeValid, target.isHostTimeValid {
            let apart = AVAudioTime.seconds(forHostTime: target.hostTime)
                - AVAudioTime.seconds(forHostTime: source.hostTime)
            offset -= AVAudioFramePosition((apart * target.sampleRate).rounded())
        }
        return AVAudioTime(sampleTime: sampleTime + offset, atRate: target.sampleRate)
    }
}

/// One looper track's player: an `AVAudioPlayerNode` that plays sample arrays
/// back to back, the last one looping.
private final class LoopPlayer: Node {

    let playerNode = AVAudioPlayerNode()

    var connections: [Node] { [] }
    var avAudioNode: AVAudioNode { playerNode }

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    /// Replaces whatever is playing: `pieces` play once, in order, then `loop`
    /// repeats. Playback begins at `time` on this node's clock, or right away
    /// when `time` is nil. Returns false if nothing could be started.
    @discardableResult
    func start(_ pieces: [[[Float]]], loop: [[Float]]?, at time: AVAudioTime?) -> Bool {
        guard playerNode.engine?.isRunning == true else { return false }
        playerNode.stop()
        guard enqueue(pieces, loop: loop) else { return false }
        playerNode.play(at: time)
        return true
    }

    /// Adds `pieces`, then the repeating `loop`, behind what is already
    /// scheduled, with no gap.
    @discardableResult
    func enqueue(_ pieces: [[[Float]]], loop: [[Float]]?) -> Bool {
        let buffers = pieces.map(buffer)
        let loopBuffer = loop.map(buffer)
        guard !buffers.contains(where: { $0 == nil }), loopBuffer != .some(nil) else { return false }
        for case let piece? in buffers {
            playerNode.scheduleBuffer(piece, at: nil, options: [])
        }
        if case let loopBuffer?? = loopBuffer {
            playerNode.scheduleBuffer(loopBuffer, at: nil, options: .loops)
        }
        return true
    }

    func stop() {
        playerNode.stop()
    }

    /// `channels` as a buffer in this node's output format. A take with fewer
    /// channels than the node repeats its last one.
    private func buffer(_ channels: [[Float]]) -> AVAudioPCMBuffer? {
        let format = playerNode.outputFormat(forBus: 0)
        let frames = channels.first?.count ?? 0
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let data = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for c in 0..<Int(format.channelCount) {
            channels[min(c, channels.count - 1)].withUnsafeBufferPointer {
                data[c].update(from: $0.baseAddress!, count: frames)
            }
        }
        return buffer
    }
}
