#include "perfecto/drumkit/kit.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <numbers>

namespace perfecto::drumkit {

namespace {

constexpr double tau = 2 * std::numbers::pi;

/// White noise from -1 to 1, the same every time from the same seed.
class Noise {
public:
    explicit Noise(uint32_t seed) : state_(seed) {}

    double next() {
        state_ ^= state_ << 13;
        state_ ^= state_ >> 17;
        state_ ^= state_ << 5;
        return double(state_) / 2147483648.0 - 1;
    }

private:
    uint32_t state_;
};

/// A two-pole filter (the Audio EQ Cookbook's), set once.
class Biquad {
public:
    enum class Kind { lowPass, highPass, bandPass };

    Biquad(Kind kind, double frequency, double q, double rate) {
        const double w = tau * std::min(frequency, rate * 0.45) / rate;
        const double alpha = std::sin(w) / (2 * q), cosine = std::cos(w);
        double b0 = 0, b1 = 0, b2 = 0;
        switch (kind) {
        case Kind::lowPass: b0 = b2 = (1 - cosine) / 2, b1 = 1 - cosine; break;
        case Kind::highPass: b0 = b2 = (1 + cosine) / 2, b1 = -(1 + cosine); break;
        case Kind::bandPass: b0 = alpha, b1 = 0, b2 = -alpha; break;
        }
        const double a0 = 1 + alpha;
        b0_ = b0 / a0, b1_ = b1 / a0, b2_ = b2 / a0;
        a1_ = -2 * cosine / a0, a2_ = (1 - alpha) / a0;
    }

    double operator()(double x) {
        const double y = b0_ * x + b1_ * x1_ + b2_ * x2_ - a1_ * y1_ - a2_ * y2_;
        x2_ = x1_, x1_ = x, y2_ = y1_, y1_ = y;
        return y;
    }

private:
    double b0_, b1_, b2_, a1_, a2_;
    double x1_ = 0, x2_ = 0, y1_ = 0, y2_ = 0;
};

/// Falls to 37% of where it starts every `seconds`.
double fall(double t, double seconds) { return std::exp(-t / seconds); }

/// Rises from nothing over `seconds`, so nothing starts with a step.
double rise(double t, double seconds) { return std::min(1.0, t / seconds); }

/// Pushed a little into a soft limit: rounder and fuller, no louder.
double warmed(double x, double drive) { return std::tanh(drive * x) / std::tanh(drive); }

/// A deep sine that drops in pitch fast, with a click on top: the beater.
double kick(double t, double &phase, Noise &noise, Biquad &click, double rate) {
    const double pitch = 46 + 120 * fall(t, 0.032) + 260 * fall(t, 0.0035);
    phase += tau * pitch / rate;
    const double body = std::sin(phase) * fall(t, 0.22);
    const double beater = click(noise.next()) * fall(t, 0.004) * 0.9;
    return warmed((body + beater) * rise(t, 0.0008), 2.8);
}

/// Two drum tones under a wash of the wires' noise, and a snap where the
/// stick lands.
double snare(double t, double phase[2], Noise &noise, Biquad &wiresLow, Biquad &wiresHigh, Biquad &snap,
             double rate) {
    phase[0] += tau * (186 + 50 * fall(t, 0.012)) / rate;
    phase[1] += tau * (334 + 30 * fall(t, 0.008)) / rate;
    const double drum = std::sin(phase[0]) * fall(t, 0.050) * 0.55 + std::sin(phase[1]) * fall(t, 0.030) * 0.30;
    const double white = noise.next();
    const double wires = wiresHigh(wiresLow(white)) * fall(t, 0.13) * 0.95;
    const double stick = snap(white) * fall(t, 0.010) * 0.45;
    return warmed((drum + wires + stick) * rise(t, 0.0006), 1.6);
}

/// Six square waves at pitches no chord has, with air over them, through
/// a high band: the ring of two cymbals.
double hat(double t, double phase[6], Noise &noise, Biquad &low, Biquad &high, Biquad &air, double rate) {
    static constexpr std::array<double, 6> pitches = {317.4, 421.6, 538.2, 603.1, 795.7, 1043.9};
    double metal = 0;
    for (size_t i = 0; i < pitches.size(); ++i) {
        phase[i] = std::fmod(phase[i] + pitches[i] / rate, 1.0);
        metal += phase[i] < 0.5 ? 1 : -1;
    }
    const double ring = high(low(metal / 6)) + air(noise.next()) * 0.35;
    return ring * fall(t, 0.17) * rise(t, 0.0004);
}

/// Hands clapped: three quick slaps of a band of noise, a little apart,
/// and the room's answer after them.
double clap(double t, Noise &noise, Biquad &band, Biquad &body) {
    static constexpr std::array<double, 4> slaps = {0, 0.0095, 0.0185, 0.0290};
    double envelope = 0;
    for (size_t i = 0; i + 1 < slaps.size(); ++i)
        if (t >= slaps[i]) envelope += fall(t - slaps[i], 0.0032) * (0.85 + 0.05 * double(i));
    if (t >= slaps.back()) envelope += fall(t - slaps.back(), 0.11) * 0.8;
    return warmed(body(band(noise.next())) * envelope * rise(t, 0.0005) * 2.4, 1.4);
}

} // namespace

std::string name(Sample sample) {
    switch (sample) {
    case Sample::kick: return "Kick";
    case Sample::snare: return "Snare";
    case Sample::hat: return "Hi-hat";
    case Sample::clap: return "Clap";
    }
    return {};
}

double length(Sample sample) {
    switch (sample) {
    case Sample::kick: return 0.9;
    case Sample::snare: return 0.55;
    case Sample::hat: return 0.9;
    case Sample::clap: return 0.6;
    }
    return 0;
}

double peak(Sample sample) {
    switch (sample) {
    case Sample::kick: return 0.95;
    case Sample::snare: return 0.9;
    case Sample::hat: return 0.8;
    case Sample::clap: return 0.9;
    }
    return 0;
}

std::vector<float> render(Sample sample, double rate) {
    const size_t frames = size_t(std::ceil(length(sample) * rate));
    std::vector<double> out(frames);
    Noise noise(0x9E3779B9u + uint32_t(sample));
    using Kind = Biquad::Kind;
    switch (sample) {
    case Sample::kick: {
        double phase = 0;
        Biquad click(Kind::bandPass, 2600, 0.8, rate);
        for (size_t i = 0; i < frames; ++i) out[i] = kick(double(i) / rate, phase, noise, click, rate);
        break;
    }
    case Sample::snare: {
        double phase[2] = {0, 0};
        Biquad wiresLow(Kind::highPass, 1400, 0.7, rate), wiresHigh(Kind::lowPass, 9500, 0.7, rate);
        Biquad snap(Kind::highPass, 5000, 0.7, rate);
        for (size_t i = 0; i < frames; ++i)
            out[i] = snare(double(i) / rate, phase, noise, wiresLow, wiresHigh, snap, rate);
        break;
    }
    case Sample::hat: {
        double phase[6] = {0, 0.17, 0.41, 0.63, 0.29, 0.86};
        Biquad low(Kind::highPass, 6800, 0.9, rate), high(Kind::highPass, 6800, 0.9, rate);
        Biquad air(Kind::highPass, 8000, 0.7, rate);
        for (size_t i = 0; i < frames; ++i) out[i] = hat(double(i) / rate, phase, noise, low, high, air, rate);
        break;
    }
    case Sample::clap: {
        Biquad band(Kind::bandPass, 1150, 1.3, rate), body(Kind::highPass, 500, 0.7, rate);
        for (size_t i = 0; i < frames; ++i) out[i] = clap(double(i) / rate, noise, band, body);
        break;
    }
    }
    // The last 30 ms fade out, so whatever is left ends at nothing.
    const size_t fade = std::min(frames, size_t(0.03 * rate));
    for (size_t i = 0; i < fade; ++i) out[frames - 1 - i] *= double(i) / double(fade);
    double loudest = 0;
    for (const double x : out) loudest = std::max(loudest, std::abs(x));
    const double gain = loudest > 0 ? peak(sample) / loudest : 0;
    std::vector<float> samples(frames);
    for (size_t i = 0; i < frames; ++i) samples[i] = float(out[i] * gain);
    return samples;
}

} // namespace perfecto::drumkit
