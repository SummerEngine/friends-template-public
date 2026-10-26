import json
import unittest

import picture_match_gen as gen
from level_lint import MAX_CUES, MAX_HAZARDS

LEVEL = json.loads(gen.LEVEL.read_text())


def stands(hazard, t):
    """The blink formula of levels/hazards.gd: solid while (t + phase) mod (on + off) < on."""
    return (t + hazard.get("phase", 0.0)) % (hazard["on"] + hazard["off"]) < hazard["on"]


def standing(t):
    """The pictures whose tiles stand at level clock t, per tile position."""
    out = {}
    for hazard in LEVEL["hazards"]:
        if hazard["id"] == gen.START_ID or not stands(hazard, t):
            continue
        for part in hazard["parts"]:
            out.setdefault(tuple(part["p"]), set()).add(int(part["slot"].rsplit("_", 1)[1]))
    return out


class PictureMatchSchedule(unittest.TestCase):
    def test_file_is_what_the_generator_writes(self):
        self.assertEqual(gen.dump(gen.build(LEVEL)), gen.LEVEL.read_text())

    def test_windows_shrink_from_five_seconds_to_the_floor(self):
        cues = LEVEL["cues"]
        self.assertLessEqual(len(cues), MAX_CUES)
        self.assertEqual((cues[0]["t"], cues[0]["until"] - cues[0]["t"]), (5.0, 5.0))
        lengths = [c["until"] - c["t"] for c in cues]
        self.assertEqual(lengths, sorted(lengths, reverse=True))
        self.assertEqual(min(lengths), gen.FLOOR)
        self.assertGreater(lengths.count(gen.FLOOR), 2)
        for before, after in zip(cues, cues[1:]):
            self.assertEqual(after["t"] - before["until"], gen.GAP)
            self.assertNotEqual(before["slot"], after["slot"])
        self.assertLess(cues[-1]["until"] + gen.RETURN, 60.0)

    def test_hazard_budget(self):
        self.assertLessEqual(len(LEVEL["hazards"]), MAX_HAZARDS)

    def test_only_the_shown_picture_stands_after_a_drop(self):
        for index, cue in enumerate(LEVEL["cues"]):
            shown = int(cue["slot"].rsplit("_", 1)[1])
            floor = standing(cue["until"] + 0.1)
            self.assertTrue(floor, cue)
            self.assertTrue(all(pictures == {shown} for pictures in floor.values()), cue)
            layout = gen.tiles_of(LEVEL["hazards"])[0]
            self.assertEqual(len(floor), sum(1 for picture, _, _ in layout if picture == shown), cue)
            if index < len(LEVEL["cues"]) - 1:
                whole = standing(cue["until"] + gen.RETURN + 0.1)
                self.assertEqual(len(whole), len(gen.tiles_of(LEVEL["hazards"])[0]))
                self.assertTrue(all(len(pictures) == 1 for pictures in whole.values()))

    def test_floor_is_whole_before_every_cue_and_gone_at_the_end(self):
        tiles = len(gen.tiles_of(LEVEL["hazards"])[0])
        for cue in LEVEL["cues"][1:]:
            self.assertEqual(len(standing(cue["t"])), tiles, cue)
        self.assertEqual(len(standing(LEVEL["cues"][0]["t"])), tiles)
        self.assertEqual(standing(59.0), {})


if __name__ == "__main__":
    unittest.main()
