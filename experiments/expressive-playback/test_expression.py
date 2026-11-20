"""The core, tested by equality on its outputs.

    .venv/bin/python -m pytest -q
"""

import pytest

import expression as ex

SCORE = [
    ex.ScoreNote("s1", 60, 0.0, 1.0),
    ex.ScoreNote("s2", 64, 0.0, 1.0),
    ex.ScoreNote("s3", 67, 1.0, 1.0),
    ex.ScoreNote("s4", 72, 2.0, 2.0),
]

PERFORMED = [
    ex.PerformedNote("p1", 60, 10.0, 0.9, 50),
    ex.PerformedNote("p2", 64, 10.5, 0.75, 70),
    ex.PerformedNote("p3", 61, 10.5, 0.1, 30),  # a slip, not in the score
    ex.PerformedNote("p4", 72, 12.25, 2.5, 90),
]

ALIGNMENT = [
    {"label": "match", "score_id": "s1", "performance_id": "p1"},
    {"label": "match", "score_id": "s2", "performance_id": "p2"},
    {"label": "deletion", "score_id": "s3"},
    {"label": "insertion", "performance_id": "p3"},
    {"label": "match", "score_id": "s4", "performance_id": "p4"},
]


def test_matches_pair_only_what_was_played():
    assert ex.matches(ALIGNMENT) == {"s1": "p1", "s2": "p2", "s4": "p4"}


def test_a_chord_is_at_the_median_of_its_notes():
    paired = {"s1": PERFORMED[0], "s2": PERFORMED[1], "s4": PERFORMED[3]}
    assert ex.time_map(SCORE, paired) == ex.TimeMap((0.0, 2.0), (10.25, 12.25))


def test_an_onset_played_out_of_order_is_left_to_its_neighbours():
    score = [ex.ScoreNote(f"s{i}", 60, float(i), 1.0) for i in range(3)]
    paired = {
        "s0": ex.PerformedNote("a", 60, 1.0, 1, 64),
        "s1": ex.PerformedNote("b", 60, 0.5, 1, 64),  # before the note it follows
        "s2": ex.PerformedNote("c", 60, 3.0, 1, 64),
    }
    assert ex.time_map(score, paired) == ex.TimeMap((0.0, 2.0), (1.0, 3.0))


def test_a_tempo_needs_two_onsets():
    with pytest.raises(ValueError):
        ex.time_map(SCORE[:1], {"s1": PERFORMED[0]})


def test_the_time_map_is_linear_between_onsets_and_goes_on_past_them():
    tempo = ex.TimeMap((0.0, 2.0, 4.0), (0.0, 1.0, 3.0))
    assert [tempo.time(b) for b in (1.0, 3.0, 5.0, -2.0)] == [0.5, 2.0, 4.0, -1.0]


def test_the_score_is_played_as_the_pianist_played_it():
    played = ex.performance(SCORE, PERFORMED, ALIGNMENT)
    assert played == [
        ex.PlayedNote("s1", 60, 0.0, 10.0, 0.9, 50, True),
        ex.PlayedNote("s2", 64, 0.0, 10.5, 0.75, 70, True),
        # left out: placed by the tempo between its neighbours, as loud as the nearest
        ex.PlayedNote("s3", 67, 1.0, 11.25, 1.0, 70, False),
        ex.PlayedNote("s4", 72, 2.0, 12.25, 2.5, 90, True),
    ]


def test_deadpan_is_one_tempo_and_one_loudness():
    assert ex.deadpan(SCORE[2:], 0.5) == [
        ex.PlayedNote("s3", 67, 1.0, 0.5, 0.5, 64, False),
        ex.PlayedNote("s4", 72, 2.0, 1.0, 1.0, 64, False),
    ]


def test_the_average_tempo_spans_the_onsets_played():
    assert ex.average_seconds_per_beat(ex.TimeMap((0.0, 1.0, 4.0), (2.0, 2.5, 4.0))) == 0.5


def test_the_pedal_is_down_from_64():
    changes = [(1.0, 127), (1.5, 100), (2.0, 0), (3.0, 64), (3.5, 63), (4.0, 127)]
    assert ex.pedal_intervals(changes) == [ex.Pedal(1.0, 2.0), ex.Pedal(3.0, 3.5)]


def test_midi_lets_a_key_go_before_it_is_struck_again_and_pedals_after():
    notes = [
        ex.PlayedNote("a", 60, 0.0, 0.0, 1.0, 80, True),
        ex.PlayedNote("b", 60, 1.0, 1.0, 1.0, 70, True),
    ]
    assert ex.midi_events(notes, [ex.Pedal(1.0, 2.0)]) == [
        (0.0, "note_on", 60, 80),
        (1.0, "note_off", 60, 0),
        (1.0, "note_on", 60, 70),
        (1.0, "pedal_down", 64, 127),
        (2.0, "note_off", 60, 0),
        (2.0, "pedal_up", 64, 0),
    ]


def test_shifting_starts_at_the_first_note_and_drops_earlier_pedal():
    notes = [ex.PlayedNote("a", 60, 0.0, 5.0, 1.0, 80, True)]
    pedals = [ex.Pedal(1.0, 2.0), ex.Pedal(4.0, 6.0)]
    assert ex.shifted(notes, pedals) == (
        [ex.PlayedNote("a", 60, 0.0, 0.0, 1.0, 80, True)],
        [ex.Pedal(0.0, 1.0)],
    )
