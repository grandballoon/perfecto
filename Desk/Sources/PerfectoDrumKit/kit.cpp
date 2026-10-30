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
    explicit Noise(uint32_t seed) : state_(seed ? seed : 1) {}

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

using Kind = Biquad::Kind;

/// Falls to 37% of where it starts every `seconds`.
double fall(double t, double seconds) { return std::exp(-t / seconds); }

/// Rises from nothing over `seconds`, so nothing starts with a step.
double rise(double t, double seconds) { return std::min(1.0, t / seconds); }

/// Pushed into a soft limit: rounder and fuller, no louder.
double warmed(double x, double drive) { return drive > 1 ? std::tanh(drive * x) / std::tanh(drive) : x; }

/// The metal's six pitches, at a tune of 1: none a chord's.
constexpr std::array<double, 6> metal = {317.4, 421.6, 538.2, 603.1, 795.7, 1043.9};

/// The mid and high toms above the low one: a fourth, then a fourth more.
constexpr std::array<double, 3> tomIntervals = {1, 4.0 / 3, 16.0 / 9};

/// The longest each piece can be: past this, nothing that matters is left.
constexpr double longest = 2.0;

/// The fade every recording ends with, in seconds, so whatever is left
/// ends at nothing.
constexpr double fadeTime = 0.03;

/// How long `piece` rings in `kit` before its room: enough of its decay
/// for it to be far under its strike, even pushed up by the kit's drive.
double ring(const Kit &kit, Piece piece) {
    const double decays = std::log(400 * kit.character.drive);
    switch (piece) {
    case Piece::kick: return decays * kit.kick.decay;
    case Piece::snare: return decays * std::max(kit.snare.toneDecay, kit.snare.wiresDecay);
    case Piece::closedHat: return (decays + 1) * kit.hat.closed;
    case Piece::openHat: return decays * kit.hat.open;
    case Piece::clap: return kit.clap.spread * kit.clap.slaps + decays * kit.clap.tail;
    case Piece::lowTom:
    case Piece::midTom:
    case Piece::highTom: return decays * kit.tom.decay;
    }
    return 0;
}

void kick(const KickVoice &v, std::vector<double> &out, Noise &noise, double rate) {
    Biquad click(Kind::bandPass, v.clickPitch, 0.8, rate);
    double phase = 0;
    for (size_t i = 0; i < out.size(); ++i) {
        const double t = double(i) / rate;
        phase += tau * (v.pitch + v.sweep * fall(t, v.sweepTime)) / rate;
        const double shape = (1 - v.edge) * std::sin(phase) + v.edge * std::asin(std::sin(phase)) * 2 / std::numbers::pi;
        const double body = warmed(shape * fall(t, v.decay), v.drive);
        const double beater = click(noise.next()) * fall(t, v.clickTime) * v.click;
        out[i] = (body + beater) * rise(t, 0.0008);
    }
}

void snare(const SnareVoice &v, std::vector<double> &out, Noise &noise, double rate) {
    Biquad wiresLow(Kind::highPass, v.wiresLow, 0.7, rate), wiresHigh(Kind::lowPass, v.wiresHigh, 0.7, rate);
    Biquad snap(Kind::highPass, 5000, 0.7, rate);
    double low = 0, high = 0;
    for (size_t i = 0; i < out.size(); ++i) {
        const double t = double(i) / rate;
        low += tau * (v.low * (1 + 0.27 * fall(t, 0.012))) / rate;
        high += tau * (v.high * (1 + 0.09 * fall(t, 0.008))) / rate;
        const double drum =
            std::sin(low) * fall(t, v.toneDecay) * 0.55 + std::sin(high) * fall(t, v.toneDecay * 0.6) * 0.30;
        const double white = noise.next();
        const double wires = wiresHigh(wiresLow(white)) * fall(t, v.wiresDecay) * v.wires;
        const double stick = snap(white) * fall(t, 0.010) * v.snap;
        out[i] = warmed((drum + wires + stick) * rise(t, 0.0006), v.drive);
    }
}

void hat(const HatVoice &v, double decay, std::vector<double> &out, Noise &noise, double rate) {
    Biquad low(Kind::highPass, v.highPass, 0.9, rate), high(Kind::highPass, v.highPass, 0.9, rate);
    Biquad air(Kind::highPass, v.highPass * 1.2, 0.7, rate);
    std::array<double, 6> phase = {0, 0.17, 0.41, 0.63, 0.29, 0.86};
    for (size_t i = 0; i < out.size(); ++i) {
        const double t = double(i) / rate;
        double ring = 0;
        if (v.fm) {
            // Three carriers, each bent by a modulator at a ratio no chord
            // has, the bending dying away faster than the ring.
            const double index = 2.5 + 4 * fall(t, decay * 0.5);
            for (size_t k = 0; k < 3; ++k) {
                const double carrier = metal[2 * k + 1] * v.tune * 4, modulator = carrier * 1.4142;
                ring += std::sin(tau * carrier * t + index * std::sin(tau * modulator * t)) / 3;
            }
        } else {
            for (size_t k = 0; k < metal.size(); ++k) {
                phase[k] = std::fmod(phase[k] + metal[k] * v.tune / rate, 1.0);
                ring += (phase[k] < 0.5 ? 1 : -1) / 6.0;
            }
        }
        out[i] = (high(low(ring)) * (1 - v.air) + air(noise.next()) * v.air) * fall(t, decay) * rise(t, 0.0004);
    }
}

void clap(const ClapVoice &v, std::vector<double> &out, Noise &noise, double rate) {
    Biquad band(Kind::bandPass, v.band, v.q, rate), body(Kind::highPass, 500, 0.7, rate);
    for (size_t i = 0; i < out.size(); ++i) {
        const double t = double(i) / rate;
        double envelope = 0;
        for (int slap = 0; slap < v.slaps; ++slap) {
            const double at = v.spread * slap * (1 + 0.08 * (slap % 2));
            if (t < at) break;
            envelope += slap + 1 < v.slaps ? fall(t - at, 0.0032) * (0.85 + 0.05 * slap) : fall(t - at, v.tail) * 0.8;
        }
        out[i] = body(band(noise.next())) * envelope * rise(t, 0.0005);
    }
}

void tom(const TomVoice &v, double interval, std::vector<double> &out, Noise &noise, double rate) {
    const double pitch = v.pitch * interval;
    Biquad skin(Kind::bandPass, pitch * 3.1, 1.5, rate);
    double phase = 0, modulator = 0;
    for (size_t i = 0; i < out.size(); ++i) {
        const double t = double(i) / rate;
        modulator += tau * pitch * 1.41 / rate;
        phase += tau * pitch * (1 + v.bend * fall(t, 0.05)) / rate;
        const double body = std::sin(phase + v.fm * fall(t, v.decay * 0.3) * std::sin(modulator)) * fall(t, v.decay);
        out[i] = (body + skin(noise.next()) * fall(t, 0.03) * v.skin) * rise(t, 0.0006);
    }
}

void normalize(std::vector<double> &out, double to) {
    double loudest = 0;
    for (const double x : out) loudest = std::max(loudest, std::abs(x));
    if (loudest > 0)
        for (double &x : out) x *= to / loudest;
}

/// `x` folded back on itself into ±`fold`, then brought back to full scale.
double folded(double x, double fold) {
    const double period = 4 * fold;
    double u = std::fmod(x + fold, period);
    if (u < 0) u += period;
    return (u < 2 * fold ? u - fold : 3 * fold - u) / fold;
}

/// A small room: four combs that ring for `time` seconds, and two
/// all-passes to smear them.
std::vector<double> roomOf(const std::vector<double> &dry, double time, double rate) {
    std::vector<double> wet(dry.size());
    for (const double delay : {0.0297, 0.0371, 0.0411, 0.0437}) {
        const size_t frames = size_t(delay * rate);
        const double feedback = std::pow(10.0, -3 * delay / time);
        std::vector<double> line(dry.size());
        for (size_t i = 0; i < dry.size(); ++i) {
            line[i] = dry[i] + (i >= frames ? feedback * line[i - frames] : 0);
            wet[i] += line[i] / 4;
        }
    }
    for (const double delay : {0.005, 0.0017}) {
        const size_t frames = size_t(delay * rate);
        std::vector<double> in = wet;
        for (size_t i = 0; i < wet.size(); ++i)
            wet[i] = -0.7 * in[i] + (i >= frames ? in[i - frames] + 0.7 * wet[i - frames] : 0);
    }
    return wet;
}

/// The kit's character, over a recording brought to full scale.
void characterize(const Character &c, std::vector<double> &out, double rate) {
    for (double &x : out) {
        x = warmed(x, c.drive);
        if (c.fold > 0) x = folded(x, c.fold);
    }
    if (c.ratio < 1) {
        // Down at once on the strike, back up over `recover`.
        const double back = std::exp(-1 / (c.recover * rate));
        double level = 0;
        for (double &x : out) {
            level = std::max(std::abs(x), level * back);
            if (level > c.threshold) x *= (c.threshold + (level - c.threshold) * c.ratio) / level;
        }
    }
    if (c.tone > 0) {
        Biquad dull(Kind::lowPass, c.tone, 0.7, rate);
        for (double &x : out) x = dull(x);
    }
    if (c.room > 0) {
        const auto wet = roomOf(out, c.roomTime, rate);
        for (size_t i = 0; i < out.size(); ++i) out[i] += wet[i] * c.room;
    }
    if (c.rate > 0 || c.bits > 0) {
        normalize(out, 1);
        const double steps = c.bits > 0 ? std::exp2(c.bits - 1) : 0;
        double held = 0, clock = 1;
        for (double &x : out) {
            clock += c.rate > 0 ? c.rate / rate : 1;
            if (clock >= 1) {
                clock -= 1;
                held = steps > 0 ? std::round(x * steps) / steps : x;
            }
            x = held;
        }
    }
}

uint32_t seed(const Kit &kit, Piece piece) {
    uint32_t hash = 0x9E3779B9u;
    for (const char c : kit.name) hash = (hash ^ uint32_t(uint8_t(c))) * 16777619u;
    return hash + uint32_t(piece) * 0x85EBCA6Bu;
}

} // namespace

std::string name(Piece piece) {
    switch (piece) {
    case Piece::kick: return "Kick";
    case Piece::snare: return "Snare";
    case Piece::closedHat: return "Closed hat";
    case Piece::openHat: return "Open hat";
    case Piece::clap: return "Clap";
    case Piece::lowTom: return "Low tom";
    case Piece::midTom: return "Mid tom";
    case Piece::highTom: return "High tom";
    }
    return {};
}

const std::vector<Kit> &kits() {
    static const std::vector<Kit> all = {
        // Round and long: a kick that booms, soft hats, a little air.
        {"Analog",
         {49, 70, 0.05, 0.42, 0.25, 1800, 0.003, 1.6},
         {180, 330, 0.06, 0.7, 1200, 8000, 0.12, 0.3, 1.3},
         {1, 7000, 0.2, 0.035, 0.30},
         {4, 0.010, 1100, 1.2, 0.13},
         {100, 0.15, 0.30, 0.05},
         {.room = 0.05, .roomTime = 0.3}},
        // Short, hard and forward: a kick that hits, a snare of noise.
        {"Punch",
         {52, 160, 0.025, 0.22, 0.9, 2600, 0.004, 2.8, 0.15},
         {190, 340, 0.045, 1.1, 1500, 10000, 0.15, 0.5, 1.8},
         {1.15, 7500, 0.55, 0.03, 0.22},
         {4, 0.0095, 1200, 1.4, 0.11},
         {110, 0.3, 0.22, 0.15},
         {.room = 0.04, .roomTime = 0.3}},
        // Punch's drums pressed together: squashed, saturated, the tails
        // brought up under the strikes, a little dulled.
        {"Glue",
         {50, 140, 0.03, 0.30, 0.7, 2400, 0.004, 2.4, 0.1},
         {185, 335, 0.05, 1.0, 1300, 9000, 0.16, 0.45, 1.8},
         {1.1, 7000, 0.5, 0.035, 0.26},
         {4, 0.0095, 1150, 1.3, 0.12},
         {105, 0.25, 0.25, 0.12},
         {.drive = 2.0, .ratio = 0.25, .threshold = 0.15, .recover = 0.03, .tone = 11000, .room = 0.06,
          .roomTime = 0.35}},
        // Distorted and folded until it buzzes: bright, dense, loud.
        {"Harsh",
         {55, 220, 0.02, 0.20, 1.2, 3500, 0.004, 4.0, 0.5},
         {210, 380, 0.04, 1.3, 2000, 14000, 0.14, 0.8, 3.0},
         {1.4, 8500, 0.6, 0.025, 0.20},
         {5, 0.008, 1600, 2.0, 0.10},
         {120, 0.35, 0.18, 0.3},
         {.drive = 3.0, .fold = 0.45}},
        // An old sampler's: a low rate, few bits, dulled and squashed.
        {"Lo-fi",
         {50, 110, 0.035, 0.30, 0.6, 2000, 0.004, 2.0},
         {200, 350, 0.05, 0.9, 1300, 9000, 0.13, 0.4, 1.6},
         {0.9, 6000, 0.4, 0.04, 0.25},
         {4, 0.010, 1000, 1.2, 0.12},
         {105, 0.2, 0.25, 0.1},
         {.drive = 1.4, .ratio = 0.5, .threshold = 0.3, .tone = 7000, .rate = 14000, .bits = 10}},
        // Clean and glassy: a sine kick that drops from high, bell-like
        // hats and toms of frequency modulation.
        {"FM",
         {45, 300, 0.012, 0.35, 0.2, 4000, 0.002, 1.2},
         {220, 410, 0.03, 0.8, 2500, 12000, 0.09, 0.6, 1.2},
         {1.3, 6000, 0.1, 0.04, 0.35, true},
         {3, 0.012, 1400, 2.5, 0.08},
         {140, 0.5, 0.2, 0.0, 2.2},
         {.room = 0.08, .roomTime = 0.5}},
        // Drums in a room: a tight kick, wide wires, washy cymbals, and
        // the walls answering all of them.
        {"Room",
         {60, 50, 0.03, 0.18, 0.5, 1500, 0.006, 1.5},
         {200, 360, 0.07, 1.0, 800, 7000, 0.18, 0.5, 1.4},
         {1.8, 5000, 0.8, 0.05, 0.45},
         {5, 0.011, 900, 1.0, 0.16},
         {90, 0.1, 0.35, 0.2},
         {.ratio = 0.6, .threshold = 0.35, .room = 0.25, .roomTime = 0.9}},
        // Dry and short: every drum a click and gone.
        {"Tight",
         {58, 140, 0.015, 0.09, 0.7, 3000, 0.002, 2.0},
         {240, 420, 0.025, 0.9, 3000, 12000, 0.05, 0.7, 1.8},
         {1.25, 9000, 0.4, 0.018, 0.12},
         {3, 0.006, 1500, 1.8, 0.05},
         {130, 0.2, 0.10, 0.1},
         {}},
    };
    return all;
}

double length(const Kit &kit, Piece piece) {
    const double room = kit.character.room > 0 ? kit.character.roomTime : 0;
    return std::min(longest, std::max(0.08, ring(kit, piece)) + room + fadeTime);
}

double peak(Piece piece) {
    switch (piece) {
    case Piece::kick: return 0.95;
    case Piece::closedHat:
    case Piece::openHat: return 0.8;
    default: return 0.9;
    }
}

std::vector<float> render(const Kit &kit, Piece piece, double rate) {
    const size_t frames = size_t(std::ceil(length(kit, piece) * rate));
    std::vector<double> out(frames);
    Noise noise(seed(kit, piece));
    switch (piece) {
    case Piece::kick: kick(kit.kick, out, noise, rate); break;
    case Piece::snare: snare(kit.snare, out, noise, rate); break;
    case Piece::closedHat: hat(kit.hat, kit.hat.closed, out, noise, rate); break;
    case Piece::openHat: hat(kit.hat, kit.hat.open, out, noise, rate); break;
    case Piece::clap: clap(kit.clap, out, noise, rate); break;
    case Piece::lowTom: tom(kit.tom, tomIntervals[0], out, noise, rate); break;
    case Piece::midTom: tom(kit.tom, tomIntervals[1], out, noise, rate); break;
    case Piece::highTom: tom(kit.tom, tomIntervals[2], out, noise, rate); break;
    }
    normalize(out, 1);
    characterize(kit.character, out, rate);
    const size_t fade = std::min(frames, size_t(fadeTime * rate));
    for (size_t i = 0; i < fade; ++i) out[frames - 1 - i] *= double(i) / double(fade);
    normalize(out, peak(piece));
    return {out.begin(), out.end()};
}

} // namespace perfecto::drumkit
