// What every voice's sound passes through on its way out: the chorus and
// the reverb, which notes send into, and the limiter on the sum.
//
// Each is one frame in, one frame out, with all its memory set aside in
// `prepare`, so what it makes of a sound does not depend on how rendering
// is divided into calls.

#ifndef PERFECTO_MIX_BUS_HPP
#define PERFECTO_MIX_BUS_HPP

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace perfecto {

/// A copy of the sound a few milliseconds late, by an amount that wavers:
/// beside the sound itself it is heard as several players. Left and right
/// waver a quarter-cycle apart, which spreads it across the two.
class Chorus {
public:
    void prepare(double rate) {
        sampleRate = rate;
        std::size_t size = 1;
        while (size < static_cast<std::size_t>((delaySeconds + deepestSeconds) * rate) + 4) size *= 2;
        left.assign(size, 0.0f);
        right.assign(size, 0.0f);
        write = 0;
        phase = 0;
    }

    /// How fast the copy wavers, in Hz. The waver is made shallower as it
    /// is made faster, so the pitch bends by the same amount at any speed
    /// and a fast chorus shimmers without going out of tune.
    void setRate(double hz) {
        phaseStep = hz / sampleRate;
        depth = std::min(bend / (twoPi * hz), deepestSeconds) * sampleRate;
    }

    void run(float inLeft, float inRight, float &outLeft, float &outRight) {
        const std::size_t mask = left.size() - 1;
        left[write] = inLeft;
        right[write] = inRight;
        const double centre = delaySeconds * sampleRate;
        outLeft = read(left, centre + depth * std::sin(twoPi * phase), mask);
        outRight = read(right, centre + depth * std::sin(twoPi * (phase + 0.25)), mask);
        write = (write + 1) & mask;
        phase += phaseStep;
        if (phase >= 1) phase -= 1;
    }

private:
    static constexpr double twoPi = 6.283185307179586;
    /// The copy's lateness, the furthest it wavers from that, and the share
    /// of its pitch the waver bends it by (about a seventh of a semitone).
    static constexpr double delaySeconds = 0.012;
    static constexpr double deepestSeconds = 0.006;
    static constexpr double bend = 0.008;

    float read(const std::vector<float> &buffer, double framesAgo, std::size_t mask) const {
        const double at = static_cast<double>(write) - framesAgo + static_cast<double>(buffer.size());
        const std::size_t index = static_cast<std::size_t>(at);
        const float between = static_cast<float>(at - static_cast<double>(index));
        const float first = buffer[index & mask];
        return first + between * (buffer[(index + 1) & mask] - first);
    }

    double sampleRate = 48000;
    std::vector<float> left;
    std::vector<float> right;
    std::size_t write = 0;
    double phase = 0;
    double phaseStep = 0;
    double depth = 0;
};

/// A room: eight delay lines that feed one another, so a sound sent in
/// comes back as a dense tail that dies away evenly. Its output is the room
/// alone, none of what was sent.
class Reverb {
public:
    void prepare(double rate) {
        sampleRate = rate;
        for (int i = 0; i < lines; ++i) {
            line[i].assign(static_cast<std::size_t>(lineSeconds[i] * rate), 0.0f);
            at[i] = 0;
            dull[i] = 0;
        }
        for (int i = 0; i < smears; ++i) {
            smear[i].assign(static_cast<std::size_t>(smearSeconds[i] * rate), 0.0f);
            smearAt[i] = 0;
        }
        // The top of the tail dies sooner than the rest, as in a real room.
        dulling = static_cast<float>(1 - std::exp(-twoPi * dullAbove / rate));
        setTail(tail);
    }

    /// The seconds the room's tail takes to fall 60 dB.
    void setTail(double seconds) {
        tail = seconds;
        for (int i = 0; i < lines; ++i) {
            keep[i] = static_cast<float>(std::pow(10.0, -3.0 * static_cast<double>(line[i].size()) / (seconds * sampleRate)));
        }
    }

    void run(float inLeft, float inRight, float &outLeft, float &outRight) {
        // Each side is smeared first, so the tail starts dense and not as
        // separate echoes.
        inLeft = smeared(smeared(inLeft, 0), 1);
        inRight = smeared(smeared(inRight, 2), 3);

        std::array<float, lines> heard;
        std::array<float, lines> back;
        for (int i = 0; i < lines; ++i) {
            heard[i] = line[i][at[i]];
            dull[i] += (heard[i] - dull[i]) * dulling;
            back[i] = dull[i] * keep[i];
        }
        // Every line feeds every line, by a pattern that neither adds nor
        // loses energy, so the lines' own losses alone set the tail.
        for (int span = 1; span < lines; span *= 2) {
            for (int i = 0; i < lines; i += span * 2) {
                for (int j = i; j < i + span; ++j) {
                    const float a = back[j];
                    const float b = back[j + span];
                    back[j] = a + b;
                    back[j + span] = a - b;
                }
            }
        }
        for (int i = 0; i < lines; ++i) {
            line[i][at[i]] = back[i] * mixing + (i % 2 == 0 ? inLeft : inRight);
            if (++at[i] == line[i].size()) at[i] = 0;
        }
        outLeft = (heard[0] - heard[2] + heard[4] - heard[6]) * level;
        outRight = (heard[1] - heard[3] + heard[5] - heard[7]) * level;
    }

private:
    static constexpr int lines = 8;
    static constexpr int smears = 4;
    static constexpr double twoPi = 6.283185307179586;
    /// The lines' lengths: none a simple multiple of another, so their
    /// echoes do not pile up on one pitch.
    static constexpr double lineSeconds[lines] = {0.0317, 0.0371, 0.0419, 0.0473, 0.0539, 0.0613, 0.0679, 0.0731};
    static constexpr double smearSeconds[smears] = {0.0051, 0.0077, 0.0063, 0.0091};
    static constexpr float smearing = 0.6f;
    static constexpr double dullAbove = 5000;
    /// 1 / sqrt(8): what keeps the lines' feeding one another from adding energy.
    static constexpr float mixing = 0.35355339f;
    static constexpr float level = 0.35f;

    /// Passes `in` through smear `which`: every pitch as loud as it went
    /// in, each a different moment late.
    float smeared(float in, int which) {
        auto &buffer = smear[which];
        const float late = buffer[smearAt[which]];
        const float through = in - smearing * late;
        buffer[smearAt[which]] = through;
        if (++smearAt[which] == buffer.size()) smearAt[which] = 0;
        return late + smearing * through;
    }

    double sampleRate = 48000;
    double tail = 2;
    std::array<std::vector<float>, lines> line;
    std::array<std::size_t, lines> at{};
    std::array<float, lines> dull{};
    std::array<float, lines> keep{};
    std::array<std::vector<float>, smears> smear;
    std::array<std::size_t, smears> smearAt{};
    float dulling = 0;
};

/// Holds the mix under full scale. Notes simply add, so a dense chord over
/// a few layers can ask for more than the output can carry; the limiter
/// turns the whole mix down for as long as it would, and leaves everything
/// quieter untouched.
///
/// To turn a peak down before it arrives it has to see it coming, so
/// everything is heard `latency()` frames late. No frame ever leaves it
/// over the ceiling.
class Limiter {
public:
    void prepare(double rate) {
        ahead = std::max<std::size_t>(1, static_cast<std::size_t>(std::lround(aheadSeconds * rate)));
        left.assign(ahead, 0.0f);
        right.assign(ahead, 0.0f);
        recent.assign(ahead, 1.0f);
        lows.assign(2 * ahead + 1, Low{});
        first = count = 0;
        frame = 0;
        at = 0;
        held = 1;
        sum = static_cast<float>(ahead);
        letGo = static_cast<float>(1 - std::exp(-1 / (releaseSeconds * rate)));
    }

    /// Frames between a sound going in and coming out.
    std::size_t latency() const { return ahead; }

    void run(float &inOutLeft, float &inOutRight) {
        const float peak = std::max(std::abs(inOutLeft), std::abs(inOutRight));
        const float wanted = peak > ceiling ? ceiling / peak : 1.0f;

        // The lowest gain any frame of the last `2 * ahead` wanted: found
        // by keeping only the frames that could still be the lowest.
        while (count > 0 && lows[(first + count - 1) % lows.size()].gain >= wanted) --count;
        lows[(first + count) % lows.size()] = {wanted, frame};
        ++count;
        if (lows[first].frame + 2 * ahead <= frame) {
            first = (first + 1) % lows.size();
            --count;
        }
        const float lowest = lows[first].gain;

        // Down at once, back up slowly: letting go fast would be heard as
        // the low notes of the mix roughening.
        held = std::min(lowest, held + (1 - held) * letGo);

        // The gain is the average of the last `ahead` of those, which
        // makes turning down a ramp that finishes exactly as the peak
        // comes out of the delay.
        sum += held - recent[at];
        recent[at] = held;
        const float gain = sum / static_cast<float>(ahead);

        // The gain is already low enough for the frame coming out; the
        // clamp only takes off what rounding may have left over.
        const float outLeft = std::clamp(left[at] * gain, -ceiling, ceiling);
        const float outRight = std::clamp(right[at] * gain, -ceiling, ceiling);
        left[at] = inOutLeft;
        right[at] = inOutRight;
        inOutLeft = outLeft;
        inOutRight = outRight;

        ++frame;
        if (++at == ahead) {
            at = 0;
            // Adding and taking away rounds a little each time; the sum
            // is counted afresh each time round so that never builds up.
            sum = 0;
            for (float gain : recent) sum += gain;
        }
    }

private:
    struct Low {
        float gain = 1;
        uint64_t frame = 0;
    };

    /// Just under full scale, and the seconds it looks ahead and takes to
    /// let go by 63%.
    static constexpr float ceiling = 0.98f;
    static constexpr double aheadSeconds = 0.0015;
    static constexpr double releaseSeconds = 0.08;

    std::size_t ahead = 1;
    std::vector<float> left;
    std::vector<float> right;
    std::vector<float> recent;
    std::vector<Low> lows;
    std::size_t first = 0;
    std::size_t count = 0;
    uint64_t frame = 0;
    std::size_t at = 0;
    float held = 1;
    float sum = 1;
    float letGo = 0;
};

}

#endif
