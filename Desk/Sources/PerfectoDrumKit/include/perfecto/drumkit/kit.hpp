// The desk's drum kits, made in code: each drum of each kit is rendered here
// as a recording, once, and the kernel plays the recordings as loaded
// samples (through sampled patches), so the drums are mixed, limited and
// timed as every other note is. Nothing is downloaded: every sound is the
// sum of a few oscillators, filters and envelopes, from a noise whose seed
// is fixed, so a kit rendered twice is the same to the bit.
//
// A kit is two things. Its voices say how each drum is struck: how deep the
// kick is and how far its pitch drops, how much of the snare is wires, what
// metal the hats are made of. Its character is what the recordings are put
// through after, the qualities drum machines are known by: pushed into
// saturation, folded until it buzzes, squashed together by a compressor
// (glue), sampled at few bits and a low rate (lo-fi), dulled, and given a
// room to ring in. The kits (`kits()`) are these, chosen to differ.

#ifndef PERFECTO_DRUMKIT_KIT_HPP
#define PERFECTO_DRUMKIT_KIT_HPP

#include <array>
#include <string>
#include <vector>

namespace perfecto::drumkit {

/// The drums every kit has, each its own recording.
enum class Piece { kick, snare, closedHat, openHat, clap, lowTom, midTom, highTom };

inline constexpr std::array<Piece, 8> allPieces = {Piece::kick,  Piece::snare,  Piece::closedHat, Piece::openHat,
                                                   Piece::clap,  Piece::lowTom, Piece::midTom,    Piece::highTom};

std::string name(Piece piece);

/// A deep sine whose pitch falls fast from far above, with a click on top:
/// the beater.
struct KickVoice {
    /// Where its pitch settles, and how far above that it starts and how
    /// quickly it falls there, in Hz and seconds.
    double pitch, sweep, sweepTime;
    /// Seconds in which the body falls to 37%.
    double decay;
    /// The beater: how loud, how bright (Hz) and how long (seconds).
    double click, clickPitch, clickTime;
    /// How hard the body is pushed into its own soft limit.
    double drive;
    /// How much of the body is a triangle rather than a sine: a little
    /// grit in the low end.
    double edge = 0;
};

/// Two drum tones under the wires' noise, and a snap where the stick lands.
struct SnareVoice {
    double low, high;
    double toneDecay;
    /// The wires: how loud, between which pitches, how long.
    double wires, wiresLow, wiresHigh, wiresDecay;
    double snap;
    double drive;
};

/// The ring of two cymbals: six square waves at pitches no chord has (or,
/// with `fm`, a carrier and its modulator), with air over them, through a
/// high band.
struct HatVoice {
    /// The metal's pitches are the kit's six times this.
    double tune;
    double highPass;
    /// How much of the ring is air (noise) rather than metal.
    double air;
    /// Seconds in which the closed and the open hat fall to 37%.
    double closed, open;
    bool fm = false;
};

/// Hands clapped: a few quick slaps of a band of noise, a little apart, and
/// the room's answer after them.
struct ClapVoice {
    int slaps;
    /// Seconds between the slaps.
    double spread;
    double band, q;
    double tail;
};

/// Pitched drums: a sine that bends down a little, with some skin noise.
struct TomVoice {
    /// The low tom's pitch, in Hz; the mid and high are above it by the
    /// kit's intervals.
    double pitch;
    /// How far the pitch bends, as a share of it.
    double bend;
    double decay;
    double skin;
    /// How far a modulator a little over an octave and a half above bends
    /// it at the strike: a bell in the skin (0 none).
    double fm = 0;
};

/// What a kit's recordings are put through, in this order.
struct Character {
    /// Pushed into a soft limit (1 leaves it alone).
    double drive = 1;
    /// Folded back on itself past this share of full scale: buzzing,
    /// bright, harsh (0 leaves it alone).
    double fold = 0;
    /// A compressor over each recording: how far over the threshold is
    /// kept (1 none; 0.25 is four to one), and how soon it lets go. With
    /// its gain made back up, the tails come up under the strike: glue.
    double ratio = 1, threshold = 0.25, recover = 0.08;
    /// The highest it passes, in Hz (0 leaves it alone).
    double tone = 0;
    /// How much of a small room is added, and how long it rings.
    double room = 0, roomTime = 0.4;
    /// Sampled again at this rate and this many bits (0 leaves it alone).
    double rate = 0;
    int bits = 0;
};

struct Kit {
    std::string name;
    KickVoice kick;
    SnareVoice snare;
    HatVoice hat;
    ClapVoice clap;
    TomVoice tom;
    Character character;
};

/// The kits there are, in the order they are chosen through: Analog,
/// Punch, Glue, Harsh, Lo-fi, FM, Room and Tight.
const std::vector<Kit> &kits();

/// How long `piece` lasts in `kit`, in seconds: its ring and its room.
double length(const Kit &kit, Piece piece);

/// The loudest `piece` is, 0 to 1: what it is brought to when rendered.
double peak(Piece piece);

/// `kit`'s `piece` rendered at `rate` frames a second: one channel,
/// starting at once and dying away to silence by its end.
std::vector<float> render(const Kit &kit, Piece piece, double rate);

} // namespace perfecto::drumkit

#endif
