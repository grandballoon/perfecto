// Sound taken in from the input and kept, to be played by notes: a
// recording a voice reads at the speed of its pitch.
//
// The memory is set aside when the kernel is made. Recording writes into
// it on the render thread, frame for frame; nothing is allocated, and no
// other thread is waited for.

#ifndef PERFECTO_CAPTURE_HPP
#define PERFECTO_CAPTURE_HPP

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>

namespace perfecto {

class Capture {
public:
    /// The most frames a capture holds: half a minute at 48 kHz.
    static constexpr int32_t capacity = 30 * 48000;

    Capture() : samples(new float[capacity]()) {}

    // MARK: Recording (the render thread's)

    /// Starts again from nothing. What was there cannot be played from
    /// this frame on.
    void begin(double sampleRate) {
        end.store(0, std::memory_order_release);
        rate.store(sampleRate, std::memory_order_relaxed);
        written = 0;
        first = last = -1;
        peak = 0;
        before = blocked = 0;
        // Steady pressure on a mic is not sound: it is taken out, or it
        // would be a thump at each end of every note.
        keep = static_cast<float>(1 - 6.283185307179586 * steadyHz / sampleRate);
    }

    /// Takes one more frame. False once it is full.
    bool record(float in) {
        if (written >= capacity) return false;
        blocked = in - before + keep * blocked;
        before = in;
        samples[written] = blocked;
        const float size = std::abs(blocked);
        if (size > peak) peak = size;
        if (size >= audible) {
            if (first < 0) first = written;
            last = written;
        }
        ++written;
        return true;
    }

    /// Ends the recording and makes it playable: from just before its
    /// first sound to a little after its last, at full level. A recording
    /// of nothing audible has nothing to play.
    void finish() {
        if (first < 0) return;
        const double sampleRate = rate.load(std::memory_order_relaxed);
        start.store(std::max(0, first - static_cast<int32_t>(leadIn * sampleRate)), std::memory_order_relaxed);
        gain.store(std::min(1 / peak, mostGain), std::memory_order_relaxed);
        end.store(std::min(written, last + static_cast<int32_t>(tail * sampleRate)), std::memory_order_release);
    }

    // MARK: Whole recordings (while nothing is rendering)

    /// Makes `frames` frames of `from`, recorded at `sampleRate`, the
    /// recording, to be played as they are.
    void load(const float *from, int32_t frames, double sampleRate) {
        frames = std::clamp(frames, 0, capacity);
        std::copy(from, from + frames, samples.get());
        rate.store(sampleRate, std::memory_order_relaxed);
        start.store(0, std::memory_order_relaxed);
        gain.store(1, std::memory_order_relaxed);
        end.store(frames, std::memory_order_release);
    }

    /// Copies what is played, at the level it is played at, into `to`
    /// (room for `room` frames), and returns how many frames that was.
    int32_t read(float *to, int32_t room) const {
        const int32_t from = start.load(std::memory_order_relaxed);
        const int32_t frames = std::clamp(end.load(std::memory_order_acquire) - from, 0, std::max(room, 0));
        const float level = gain.load(std::memory_order_relaxed);
        for (int32_t i = 0; i < frames; ++i) to[i] = samples[from + i] * level;
        return frames;
    }

    // MARK: Playing

    /// Frames that can be played: 0 while it is empty or being recorded.
    int32_t length() const {
        return std::max(0, end.load(std::memory_order_acquire) - start.load(std::memory_order_relaxed));
    }

    const float *data() const { return samples.get(); }

    /// Where playing starts and ends in `data`, the level it is played
    /// at, and the rate it was recorded at.
    std::atomic<int32_t> start{0};
    std::atomic<int32_t> end{0};
    std::atomic<float> gain{1};
    std::atomic<double> rate{48000};

private:
    /// The level that counts as sound, 40 dB under full: what is quieter at
    /// either end of a recording is the room, and is left off.
    static constexpr float audible = 0.01f;
    /// Seconds kept before the first sound and after the last, so neither
    /// its start nor its dying away is cut into.
    static constexpr double leadIn = 0.005;
    static constexpr double tail = 0.15;
    /// A quiet recording is brought up to full level, but by no more than
    /// this (30 dB), or a recording of a quiet room would be a roar.
    static constexpr float mostGain = 31.6f;
    /// Below this pitch, in Hz, is taken out as steady pressure.
    static constexpr double steadyHz = 20;

    std::unique_ptr<float[]> samples;
    int32_t written = 0;
    int32_t first = -1;
    int32_t last = -1;
    float peak = 0;
    float before = 0;
    float blocked = 0;
    float keep = 0;
};

}

#endif
