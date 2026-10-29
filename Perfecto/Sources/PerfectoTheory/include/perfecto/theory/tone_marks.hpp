// Marks on a stack of thirds: each tone above the root moved a semitone up
// or down, or left out. A chord symbol is built the same way (C9♯5♯9 is the
// 9th chord with its 5th and 9th raised), so every color a lead sheet names
// is a stack and a few marks, and every mark is one step (`colorSteps`).

#ifndef PERFECTO_THEORY_TONE_MARKS_HPP
#define PERFECTO_THEORY_TONE_MARKS_HPP

#include "perfecto/theory/modes.hpp"
#include "perfecto/theory/tertian.hpp"

#include <array>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace perfecto::theory {

/// A tone of a stack of thirds above its root, by the degree it stands for.
enum class ChordTone { third = 3, fifth = 5, seventh = 7, ninth = 9, eleventh = 11, thirteenth = 13 };

inline constexpr std::array<ChordTone, 6> allChordTones = {
    ChordTone::third, ChordTone::fifth, ChordTone::seventh, ChordTone::ninth, ChordTone::eleventh,
    ChordTone::thirteenth,
};

inline int raw(ChordTone t) { return static_cast<int>(t); }

/// The tone's name at `semitones` above the root, as a chord symbol writes
/// it: "sus4", "♯5", "maj7", "♭9".
std::string name(ChordTone tone, int semitones);

/// Marks on a stack's tones: a tone moved a semitone up (+1) or down (-1),
/// and tones whose leaving out is turned round. A tone the stack leaves out
/// to begin with (`droppedTones`) is brought back by the same mark that
/// leaves another out.
class ToneMarks {
public:
    bool operator==(const ToneMarks &) const = default;
    auto operator<=>(const ToneMarks &) const = default;

    bool isEmpty() const { return moves_.empty() && skips_.empty(); }

    /// How far `tone` is marked to move: +1, -1 or 0.
    int move(ChordTone tone) const;

    /// Whether `tone`'s leaving out is turned round.
    bool skips(ChordTone tone) const { return skips_.count(tone) > 0; }

    const std::map<ChordTone, int> &moves() const { return moves_; }
    const std::set<ChordTone> &skipped() const { return skips_; }

    /// Marks `tone` to move by `offset` (+1 or -1); marking it the same way
    /// again takes the mark off.
    void toggleMove(ChordTone tone, int offset);

    /// Turns round whether `tone` is left out.
    void toggleSkip(ChordTone tone);

    /// Marks `tone` to move by `offset` (+1 or -1), or not to move (0),
    /// whatever it was marked before.
    void setMove(ChordTone tone, int offset);

    /// Sets whether `tone`'s leaving out is turned round.
    void setSkip(ChordTone tone, bool isOn);

private:
    std::map<ChordTone, int> moves_;
    std::set<ChordTone> skips_;
};

/// One tone of a marked stack: which it is, where the mode puts it, and
/// where it sounds once marked.
struct MarkedTone {
    ChordTone tone;
    /// Semitones above the root, as the mode stacks it.
    int stacked;
    /// Semitones above the root, once its move is made.
    int sounding;

    bool operator==(const MarkedTone &) const = default;
    bool isMoved() const { return sounding != stacked; }
};

struct StackedTone {
    ChordTone tone;
    int semitones;

    bool operator==(const StackedTone &) const = default;
};

/// The tones of `height` thirds stacked through `mode` above the root, with
/// none left out (`stackThirds` leaves out the ones in `droppedTones`).
std::vector<StackedTone> stackedTones(const std::vector<int> &mode, StackHeight height);

/// The tones `stackThirds` leaves out: a perfect 11th over a major 3rd
/// clashes, so an 11th chord leaves out its 3rd and a 13th chord its 11th.
std::set<ChordTone> droppedTones(const std::vector<int> &mode, StackHeight height);

/// The tones `height` thirds stacked through `mode` sound with `marks`, from
/// the 3rd up: the ones left out are not there. A move is made only where
/// the tone has a name there and no other tone already sounds that pitch
/// class, since landing on one is not a move but a tone lost; tones are
/// moved in order from the 3rd.
std::vector<MarkedTone> markedTones(const std::vector<int> &mode, StackHeight height, const ToneMarks &marks);

/// `stackThirds` with `marks`: the root and the marked tones. With no marks
/// it is `stackThirds` itself.
std::vector<int> markedStack(const std::vector<int> &mode, StackHeight height, const ToneMarks &marks);

/// The marks a chord symbol adds to the stack's own name, in order from the
/// 3rd: a tone moved by its name there ("♯5"), a tone left out as "no 7",
/// and one brought back as "add 3".
std::vector<std::string> markNames(const std::vector<int> &mode, StackHeight height, const ToneMarks &marks);

/// The name of a marked stack: the stack's own (`tertianChordName`) and the
/// marks in brackets, e.g. "9(♯5, ♯9)".
std::string markedChordName(HeptatonicMode mode, StackHeight height, const ToneMarks &marks);

/// What a tone's marks can do in a stack, for the controls that set them.
struct ToneMarkOption {
    ChordTone tone;
    /// Whether the stack has the tone at all.
    bool isInStack;
    /// Whether it is left out now, by the stack or by a mark.
    bool isLeftOut;
    /// Whether the stack leaves it out to begin with.
    bool isDroppedByStack;
    /// The tone's name a semitone up or down from where the stack puts it,
    /// or none where a move cannot be made.
    std::optional<std::string> up;
    std::optional<std::string> down;
    /// The move made now: +1, -1 or 0.
    int moved;

    bool operator==(const ToneMarkOption &) const = default;
};

/// Every tone's options in a stack with `marks`, from the 3rd up.
std::vector<ToneMarkOption> toneMarkOptions(const std::vector<int> &mode, StackHeight height,
                                            const ToneMarks &marks);

} // namespace perfecto::theory

#endif
