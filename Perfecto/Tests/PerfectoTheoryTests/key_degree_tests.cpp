// Ported from Tests/MusicTheoryCoreTests/KeyDegreeTests.swift.

#include <doctest.h>

#include "perfecto/theory/key_degree.hpp"
#include "perfecto/theory/note_name.hpp"
#include "perfecto/theory/voicing.hpp"

#include <vector>

using namespace perfecto::theory;
using Ints = std::vector<int>;

namespace {

const Key cMajor{PitchClass::C, ScaleType::major};
const Key cMinor{PitchClass::C, ScaleType::naturalMinor};

/// The triad on `root` as `key` has it, as pitch classes from the root up.
Ints triad(PitchClass root, const Key &key) {
    const KeyDegree chord = KeyDegree::onRoot(root, key);
    const Ints notes = computeVoicing(chord.key, ChordSpec{chord.degree, ChordColor::base()}, Inversion::root(), 4,
                                      false, std::nullopt)
                           .notes();
    Ints result;
    for (int note : notes) result.push_back((note - notes[0]) % 12);
    return result;
}

const Ints majorTriad = {0, 4, 7};
const Ints minorTriad = {0, 3, 7};
const Ints diminishedTriad = {0, 3, 6};

} // namespace

TEST_SUITE("KeyDegree") {

// MARK: – Notes of the key

TEST_CASE("a note of the key is its degree") {
    CHECK(KeyDegree::onRoot(PitchClass::C, cMajor) == KeyDegree{cMajor, Degree::I});
    CHECK(KeyDegree::onRoot(PitchClass::D, cMajor) == KeyDegree{cMajor, Degree::ii});
    CHECK(KeyDegree::onRoot(PitchClass::B, cMajor) == KeyDegree{cMajor, Degree::viiDim});
    const Key eMinor{PitchClass::E, ScaleType::naturalMinor};
    CHECK(KeyDegree::onRoot(PitchClass::C, eMinor) == KeyDegree{eMinor, Degree::vi});
}

TEST_CASE("a key knows the degree of each of its notes") {
    CHECK(cMajor.degreeOf(PitchClass::G) == Degree::V);
    CHECK(cMajor.degreeOf(PitchClass::Fs) == std::nullopt);
    CHECK(Key{PitchClass::A, ScaleType::major}.degreeOf(PitchClass::Cs) == Degree::iii);
}

// MARK: – Notes outside the key

/// The chords a major key borrows: the flat side's are major, and the
/// raised fourth's is diminished.
TEST_CASE("a major key borrows from its parallel modes") {
    CHECK(triad(PitchClass::Cs, cMajor) == majorTriad);
    CHECK(triad(PitchClass::Ds, cMajor) == majorTriad);
    CHECK(triad(PitchClass::Fs, cMajor) == diminishedTriad);
    CHECK(triad(PitchClass::Gs, cMajor) == majorTriad);
    CHECK(triad(PitchClass::As, cMajor) == majorTriad);
}

/// The Neapolitan, and the raised sixth and seventh's diminished chords.
TEST_CASE("a minor key borrows from its parallel modes") {
    CHECK(triad(PitchClass::Cs, cMinor) == majorTriad);
    CHECK(triad(PitchClass::A, cMinor) == diminishedTriad);
    CHECK(triad(PitchClass::B, cMinor) == diminishedTriad);
}

TEST_CASE("a borrowed chord keeps the tonic where a scale has its mode") {
    CHECK(KeyDegree::onRoot(PitchClass::As, cMajor) == KeyDegree{Key{PitchClass::C, ScaleType::mixolydian}, Degree::viiDim});
    CHECK(KeyDegree::onRoot(PitchClass::Ds, cMajor) == KeyDegree{Key{PitchClass::C, ScaleType::dorian}, Degree::iii});
    CHECK(KeyDegree::onRoot(PitchClass::Gs, cMajor) == KeyDegree{Key{PitchClass::C, ScaleType::naturalMinor}, Degree::vi});
    CHECK(KeyDegree::onRoot(PitchClass::Fs, cMajor) == KeyDegree{Key{PitchClass::C, ScaleType::lydian}, Degree::IV});
}

/// No scale is Phrygian, so its chord is read in the relative major.
TEST_CASE("a mode with no scale is its relative major") {
    CHECK(KeyDegree::onRoot(PitchClass::Cs, cMajor) == KeyDegree{Key{PitchClass::Gs, ScaleType::major}, Degree::IV});
}

// MARK: – Every root, every key

TEST_CASE("every root has a chord built on it in every key") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        for (PitchClass tonic : allPitchClasses) {
            const Key key{tonic, scale};
            for (PitchClass root : allPitchClasses) {
                const KeyDegree chord = KeyDegree::onRoot(root, key);
                CHECK_MESSAGE(chord.root() == root, name(root), " in ", name(tonic), " ", displayName(scale));
                // A borrowed chord's key still has the tonic among its notes.
                CHECK(chord.key.degreeOf(tonic) != std::nullopt);
            }
        }
    }
}

TEST_CASE("the same chords are borrowed in every key") {
    for (PitchClass tonic : allPitchClasses) {
        const Key key{tonic, ScaleType::major};
        const PitchClass flatSeven = static_cast<PitchClass>((raw(tonic) + 10) % 12);
        CHECK(triad(flatSeven, key) == majorTriad);
    }
}

} // TEST_SUITE
