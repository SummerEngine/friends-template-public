"""Unit tests for tools/blink_drop.py: a blink block that is not solid hangs under the level (it falls away, it never vanishes) and the lint rule on `off`
(python3 -m unittest discover -s tools -p 'test_*.py'). The numbers pin the twin in demo/levels/hazards.gd (_blink_fall, blink_depth); tools/vanish_check.gd
runs the same arithmetic in the engine over every level."""
import glob
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blink_drop  # noqa: E402
import level_lint  # noqa: E402
from test_level_lint import lint_hazards  # noqa: E402

LEVELS = Path(__file__).resolve().parent.parent / "demo" / "levels"
PAD = {"k": "blink", "p": [0, -0.5, -39], "s": [12, 1, 4], "on": 3.0, "off": 3.0, "warn": 1.0}
GATE = {"k": "blink", "id": "gate", "p": [0, 2, -4.75], "s": [17, 4, 0.5], "on": 4.0, "off": 600.0, "warn": 1.0}


def blinks():
    """Every blink hazard of every level file: (file name, hazard)."""
    found = []
    for name in sorted(glob.glob(str(LEVELS / "level_*.json"))):
        for h in json.loads(Path(name).read_text()).get("hazards", []):
            if h.get("k") == "blink":
                found.append((Path(name).name, h))
    return found


class BlinkDrop(unittest.TestCase):
    def test_height_of_the_parts(self):
        self.assertAlmostEqual(blink_drop.height(PAD), 1.0)
        self.assertAlmostEqual(blink_drop.height(GATE), 4.0)
        parts = {"k": "blink", "parts": [{"k": "box", "p": [0, 0, 0], "s": [2, 1, 2]}, {"k": "cyl", "p": [0, 1.5, 0], "d": 2, "h": 2}]}
        self.assertAlmostEqual(blink_drop.height(parts), 3.0)  # from -0.5 to 2.5
        tilted = {"k": "blink", "r": [0, 0, 90], "s": [4, 1, 1]}
        self.assertAlmostEqual(blink_drop.height(tilted), 4.0)  # a plank on its end

    def test_a_solid_block_stays_put_and_a_gone_one_falls_out_of_reach(self):
        f = blink_drop.fall(PAD)
        self.assertEqual(blink_drop.depth(f, 0.0), 0.0)
        self.assertEqual(blink_drop.depth(f, 2.99), 0.0)  # solid for `on`, however long it shakes
        self.assertAlmostEqual(blink_drop.depth(f, 3.0 + blink_drop.FALL_TIME), 3.0)  # its own height 1 + the clearance 2
        self.assertGreater(blink_drop.depth(f, 3.0 + blink_drop.FALL_TIME), 1.0 + blink_drop.CLEAR - 1e-6)
        self.assertAlmostEqual(blink_drop.depth(f, 4.5), 3.0)  # it hangs there
        self.assertAlmostEqual(blink_drop.depth(f, 6.0 - blink_drop.RISE_TIME), 3.0)
        self.assertAlmostEqual(blink_drop.depth(f, 6.0 - 0.001), 0.0, places=2)  # and arrives exactly when it is solid again

    def test_a_block_that_is_gone_for_the_round_falls_on_out_of_sight(self):
        f = blink_drop.fall(GATE)
        self.assertGreaterEqual(blink_drop.depth(f, 4.0 + blink_drop.FALL_TIME), 4.0 + blink_drop.CLEAR - 1e-6)  # at least its own height and the clearance at once
        self.assertAlmostEqual(blink_drop.depth(f, 4.0 + 5.0), blink_drop.AWAY_DEPTH)
        self.assertAlmostEqual(blink_drop.depth(f, 604.0 - 1e-6), 0.0, places=3)
        for later in (4.0 + 1.0, 4.0 + 20.0, 4.0 + 300.0):
            self.assertGreater(blink_drop.depth(f, later), 4.0 + blink_drop.CLEAR - 1e-6)

    def test_the_depth_is_continuous_and_never_negative(self):
        dt = 0.001
        for name, h in blinks():
            f = blink_drop.fall(h)
            total = f["on"] + f["off"]
            slope = max((2.0 * f["accel"] * f["sink"]) ** 0.5, 2.0 * f["sink"] / f["rise_time"])  # the steepest the fall or the climb gets (m/s)
            windows = [(max(f["on"] - 0.2, 0.0), min(f["on"] + 2.0, total)), (max(total - f["rise_time"] - 0.2, 0.0), total)]
            for lo, hi in windows:
                previous = blink_drop.depth(f, lo)
                for i in range(1, int((hi - lo) / dt) + 1):
                    d = blink_drop.depth(f, lo + i * dt)
                    self.assertGreaterEqual(d, 0.0)
                    self.assertLessEqual(abs(d - previous), slope * dt * 1.05 + 1e-9, (name, h.get("id"), lo + i * dt))  # no jump anywhere: nothing pops
                    previous = d
            self.assertEqual(blink_drop.depth(f, 0.0), 0.0)

    def test_every_blink_of_every_level_hangs_out_of_reach_while_it_is_gone(self):
        found = blinks()
        self.assertGreater(len(found), 20)
        for name, h in found:
            f = blink_drop.fall(h)
            need = blink_drop.height(h) + blink_drop.CLEAR
            total = f["on"] + f["off"]
            deepest = max(blink_drop.depth(f, f["on"] + (total - f["on"]) * i / 400) for i in range(401))
            self.assertGreaterEqual(deepest, need - 1e-6, (name, h.get("id"), "falls less than its own height + clearance"))
            # while it is not solid, the first moment it is below its own thickness is within the fall time
            self.assertGreaterEqual(blink_drop.depth(f, f["on"] + blink_drop.FALL_TIME), min(need, f["sink"]) - 1e-6, (name, h.get("id")))
            self.assertGreaterEqual(f["off"], blink_drop.MIN_OFF, (name, h.get("id")))

    def test_the_lint_wants_time_to_fall_and_climb(self):
        self.assertGreaterEqual(level_lint.BLINK_OFF_MIN, blink_drop.MIN_OFF)
        block = {"k": "blink", "p": [0, 1, -8], "s": [2, 0.5, 2], "on": 4}
        self.assertEqual(lint_hazards(dict(block, off=level_lint.BLINK_OFF_MIN)), [])
        short = lint_hazards(dict(block, off=0.5))
        self.assertTrue(any("outside" in text and "off" in text for text in short), short)


if __name__ == "__main__":
    unittest.main()
