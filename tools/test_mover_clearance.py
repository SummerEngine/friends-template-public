"""Unit tests for tools/mover_clearance_check.py (python3 -m unittest discover -s tools -p 'test_*.py'): the sweep finds movers that meet, cross a block or crowd it
under 0.3 m, ignores a mover standing on its floor, and the levels of the daylight race world have no hit."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mover_clearance_check as mcc  # noqa: E402

LEVELS = Path(__file__).resolve().parent.parent / "demo" / "levels"


def slide(hid, p, to, period=8.0, pause=1.0, phase=0.0, size=(3.0, 0.5, 3.0), **kw):
    return {"k": "slide", "id": hid, "p": list(p), "to": list(to), "period": period, "pause": pause, "phase": phase, "s": list(size), **kw}


def hits(blocks=(), hazards=()):
    return mcc.sweep({"blocks": list(blocks), "hazards": list(hazards)})


class Sweep(unittest.TestCase):
    def test_cycle_matches_the_engine_formula(self):
        self.assertEqual(mcc.cycle(0.5, 8.0, 1.0, "sine"), 0.0)                      # at rest at the start
        self.assertAlmostEqual(mcc.cycle(1.0 + 3.0 / 2, 8.0, 1.0, "sine"), 0.5)      # half way (moving 3 s each way)
        self.assertEqual(mcc.cycle(1.0 + 3.0 + 0.5, 8.0, 1.0, "sine"), 1.0)          # held at the far end
        self.assertAlmostEqual(mcc.cycle(-0.5, 8.0, 1.0, "sine", 2.0), mcc.cycle(7.5, 8.0, 1.0, "sine", 2.0))  # negative clock wraps

    def test_two_movers_that_meet_are_found_and_a_phase_offset_that_keeps_them_apart_is_not(self):
        a = slide("a", (0, 0, 0), (6, 0, 0))
        b = slide("b", (8, 0, 0), (6, 0, 0), phase=4.0)   # 3 m wide each, 5 m apart at rest, runs of 6 m: they overlap when a is out and b is back
        self.assertTrue(hits(hazards=[a, b]))
        b_in_step = slide("b", (8, 0, 0), (6, 0, 0), phase=0.0)   # in step they keep 5 m for ever
        self.assertTrue(hits(hazards=[a, slide("b", (8, 0, 0), (-6, 0, 0))]))   # opposite ways: they meet
        short = [slide("a", (0, 0, 0), (4.5, 0, 0)), slide("b", (8, 0, 0), (4.5, 0, 0), phase=4.0)]
        self.assertEqual(hits(hazards=short), [])                               # 8 - 3 - 4.5 = 0.5 m at worst
        self.assertEqual(hits(hazards=[a, b_in_step]), [])

    def test_a_block_in_the_way_and_a_block_too_near(self):
        stone = {"k": "box", "p": [3, 0, 0], "s": [1, 1, 1]}
        self.assertTrue(hits(blocks=[stone], hazards=[slide("a", (0, 0, 0), (6, 0, 0))]))   # runs through the stone
        near = {"k": "box", "p": [3.0, 0, 0], "s": [1, 1, 1]}
        ferry = slide("f", (0, 0, 0), (1.0, 0, 0), size=(3.0, 0.5, 3.0))                  # ends 1.0 + 1.5 = 2.5; the block starts at 2.5
        self.assertTrue(hits(blocks=[near], hazards=[ferry]))
        far = slide("f", (0, 0, 0), (0.6, 0, 0))                                          # ends 2.1: 0.4 m of air
        self.assertEqual(hits(blocks=[near], hazards=[far]), [])
        tight = slide("f", (0, 0, 0), (0.75, 0, 0))                                       # ends 2.25: 0.25 m of air
        self.assertTrue(hits(blocks=[near], hazards=[tight]))

    def test_a_wall_standing_on_its_floor_is_not_a_hit_but_a_platform_touching_it_is(self):
        floor = {"k": "box", "p": [0, -1, 0], "s": [20, 2, 20]}
        crate = slide("crate", (0, 1.5, 0), (4, 0, 0), hit=True, size=(3, 3, 3))
        self.assertEqual(hits(blocks=[floor], hazards=[crate]), [])
        platform = slide("plat", (0, 0.25, 0), (4, 0, 0), size=(3, 0.5, 3))                 # the bottom is on the floor's top, not a wall
        self.assertTrue(hits(blocks=[floor], hazards=[platform]))
        wall_in_the_floor = slide("sunk", (0, 1.0, 0), (4, 0, 0), hit=True, size=(3, 3, 3))   # reaches into the floor
        self.assertTrue(hits(blocks=[floor], hazards=[wall_in_the_floor]))

    def test_a_gate_door_may_touch_its_frame_only(self):
        door = {"k": "lift", "id": "door", "p": [0, 5.25, 0], "rise": -3.5, "period": 4.0, "pause": 1.25, "hit": True, "parts": [{"k": "box", "p": [0, 0, 0], "s": [2, 3.5, 0.5], "tone": "door"}]}
        floor = {"k": "box", "p": [0, -1, 0], "s": [20, 2, 6]}
        pier = {"k": "box", "p": [-1.25, 2, 0], "s": [0.5, 4, 1.5], "tone": "arch"}
        self.assertEqual(hits(blocks=[floor, pier], hazards=[door]), [])
        plain = dict(pier, tone="")
        self.assertTrue(hits(blocks=[floor, plain], hazards=[door]))

    def test_a_spinner_arm_counts(self):
        arm = {"k": "spin", "id": "arm", "p": [0, 1, 4], "rate": 90, "parts": [{"k": "box", "p": [0, 0, 0], "s": [8, 0.5, 0.5]}]}
        self.assertTrue(hits(hazards=[arm, slide("a", (0, 1, 0), (0, 0, 2))]))             # its sweep reaches the ferry
        self.assertEqual(hits(hazards=[arm, slide("a", (0, 1, -6), (0, 0, 2))]), [])

    def test_turned_blocks_use_their_turned_box(self):
        post = {"k": "cyl", "p": [3, 0, 0], "d": 1.0, "h": 6.0, "r": [90, 0, 0]}           # lies along z: 6 m long, 1 m across
        self.assertTrue(hits(blocks=[post], hazards=[slide("a", (0, 0, 4.5), (2, 0, 0))]))


class Levels(unittest.TestCase):
    def test_the_daylight_race_levels_have_no_hit(self):
        for n in (29, 30, 31, 32):
            level = json.loads((LEVELS / f"level_{n}.json").read_text())
            self.assertEqual(mcc.check(level), [], f"level {n}")


if __name__ == "__main__":
    unittest.main()
