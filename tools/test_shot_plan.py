"""Unit tests for tools/shot_plan.py: where a ball is housed, how a cannon ball lands, bounces, rolls and is swallowed, and the lint rule that no ball pops in or
out in view (python3 -m unittest discover -s tools -p 'test_*.py'). The numbers pin the twin in demo/levels/hazards.gd (ball_ports, shot_plan)."""
import copy
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import level_lint  # noqa: E402
import shot_plan  # noqa: E402
from test_level_lint import BASE  # noqa: E402

LEVELS = Path(__file__).resolve().parent.parent / "demo" / "levels"
ROAD = [  # a 16 m wide road, x -8..8, z -40..0, with a wall at each side
    {"k": "box", "p": [0, -0.5, -20], "s": [16, 1, 40]},
    {"k": "box", "p": [-8.25, 2, -20], "s": [0.5, 6, 40]},
    {"k": "box", "p": [8.25, 2, -20], "s": [0.5, 6, 40]},
]


def level_errors(hazards, blocks=None):
    """The errors of a small valid level whose floor is ROAD (or `blocks`) with these hazards."""
    level = copy.deepcopy(BASE)
    level["blocks"] = copy.deepcopy(blocks or ROAD)
    level["blocks"].append({"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24]})
    level["hazards"] = copy.deepcopy(hazards)
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "level_01.json"
        path.write_text(json.dumps(level))
        return level_lint.lint_level(path, 1).errors


def ball(**changes):
    h = {"k": "ball", "id": "b", "p": [-6.25, 1.75, -10], "path": [[-6.25, 1.75, -10], [6.25, 1.75, -10]], "speed": 6, "rad": 1.75, "period": 6}
    h.update(changes)
    return h


def cannon(**changes):
    h = {"k": "cannon", "id": "c", "p": [-7.25, 6, -20], "v": [5.5, 3.5, 0], "rad": 0.75, "period": 4, "life": 4}
    h.update(changes)
    return h


class BallPorts(unittest.TestCase):
    def test_a_ball_against_a_wall_goes_through_a_slot_in_it(self):
        plan = shot_plan.ball_ports(ball(), ROAD)
        self.assertEqual((plan["enter"]["kind"], plan["leave"]["kind"]), ("wall", "wall"))
        self.assertAlmostEqual(plan["enter"]["point"][0], -8.0)       # the wall face, 1.75 m from the ball's centre
        self.assertAlmostEqual(plan["enter"]["hide"], 1.75 + 1.75 + shot_plan.SWALLOW)
        self.assertAlmostEqual(plan["leave"]["point"][0], 8.0)
        self.assertEqual(plan["leave"]["normal"], [-1.0, -0.0, -0.0])
        self.assertTrue(shot_plan.ball_hidden(plan, ball()))

    def test_a_ball_in_the_open_comes_out_of_a_hole_in_the_floor(self):
        lane = ball(path=[[0, 1.75, -30], [0, 1.75, -10]])
        plan = shot_plan.ball_ports(lane, ROAD)
        self.assertEqual((plan["enter"]["kind"], plan["leave"]["kind"]), ("floor", "floor"))
        self.assertAlmostEqual(plan["enter"]["point"][1], 0.0)
        self.assertAlmostEqual(plan["lead_in"], shot_plan.PORT_TIME)

    def test_a_ball_high_in_the_air_has_no_housing(self):
        plan = shot_plan.ball_ports(ball(path=[[0, 6.0, -30], [0, 6.0, -10]]), ROAD)
        self.assertEqual((plan["enter"]["kind"], plan["leave"]["kind"]), ("none", "none"))

    def test_the_leads_share_the_gap_of_the_period(self):
        plan = shot_plan.ball_ports(ball(period=3.0), ROAD)          # path 12.5 / 6 = 2.08 s, housings 2 x 0.6 s: 3.28 s
        self.assertFalse(shot_plan.ball_hidden(plan, ball(period=3.0)))
        self.assertAlmostEqual(plan["lead_in"] + plan["lead_out"], plan["gap"])

    def test_the_real_level_hides_every_ball(self):
        data = json.loads((LEVELS / "level_23.json").read_text())
        kinds = {}
        for h in data["hazards"]:
            if h["k"] == "ball":
                plan = shot_plan.ball_ports(h, data["blocks"])
                self.assertTrue(shot_plan.ball_hidden(plan, h), h["id"])
                kinds[h["id"]] = (plan["enter"]["kind"], plan["leave"]["kind"])
        self.assertEqual(kinds["cross_1"], ("wall", "wall"))
        self.assertEqual(kinds["lane_2"], ("floor", "floor"))
        self.assertEqual(kinds["hop_1"], ("floor", "floor"))

    def test_the_real_level_has_many_balls_of_three_sizes_on_staggered_periods(self):
        data = json.loads((LEVELS / "level_23.json").read_text())
        balls = [h for h in data["hazards"] if h["k"] == "ball"]
        self.assertGreaterEqual(len(balls), 25)
        self.assertLessEqual(len(data["hazards"]), level_lint.MAX_HAZARDS)
        self.assertEqual({h["rad"] for h in balls} >= {0.5, 1.0, 1.75}, True)
        self.assertGreaterEqual(len({h["period"] for h in balls}), 8)                     # no two rows share a rhythm
        self.assertGreaterEqual(len({h.get("phase", 0.0) for h in balls}), 12)
        self.assertGreaterEqual(len({h["speed"] for h in balls}), 5)
        self.assertTrue(any(len(h["path"]) >= 4 for h in balls))                          # a ball that bounces off the walls more than once
        self.assertTrue(any(h["path"][0][0] != h["path"][-1][0] and h["path"][0][2] != h["path"][-1][2] for h in balls))  # a diagonal


def zigzag(**changes):
    """A hop-size ball from a hole in the floor that bounces once off the right wall (x 8, its centre 0.5 m from it) and sinks into another hole."""
    h = ball(rad=0.5, speed=8, period=12, path=[[-3, 0.5, -5], [7.5, 0.5, -9], [-7.5, 0.5, -14.75], [1.5, 0.5, -18.25]], **{"p": [-3, 0.5, -5]})
    h.update(changes)
    return h


class BallPath(unittest.TestCase):
    def test_a_path_that_bounces_off_the_walls_is_clean(self):
        self.assertEqual(level_errors([zigzag()]), [])

    def test_wall_face_and_gap(self):
        t, n = shot_plan.wall_face(ROAD, [7.5, 0.5, -9], [1.0, 0.0, 0.0])
        self.assertAlmostEqual(t, 0.5)
        self.assertEqual([round(c) for c in n], [-1, 0, 0])
        self.assertAlmostEqual(shot_plan.surface_gap(ROAD[1], [-6.0, 2.0, -20.0]), 2.0)                     # the left wall's inner face is at x -8
        self.assertEqual(shot_plan.surface_gap(ROAD[0], [0.0, -0.5, -20.0]), 0.0)                           # inside

    def test_a_bend_in_open_ground_is_an_error(self):
        errors = level_errors([zigzag(path=[[-3, 0.5, -5], [3, 0.5, -12], [-3, 0.5, -18]])])
        self.assertTrue(any("no wall to bounce off" in e for e in errors), errors)

    def test_a_bounce_that_does_not_mirror_is_an_error(self):
        errors = level_errors([zigzag(path=[[-3, 0.5, -5], [7.5, 0.5, -9], [-7.5, 0.5, -9.5], [1.5, 0.5, -18.25]])])
        self.assertTrue(any("bounces the wrong way" in e for e in errors), errors)

    def test_a_bounce_at_the_wrong_distance_from_the_wall_is_an_error(self):
        errors = level_errors([zigzag(path=[[-3, 0.5, -5], [6.0, 0.5, -8.5], [-7.5, 0.5, -14.0], [1.5, 0.5, -18.25]])])
        self.assertTrue(any("no wall to bounce off" in e for e in errors), errors)

    def test_a_path_through_a_wall_is_an_error(self):
        errors = level_errors([ball(path=[[-6.25, 1.75, -10], [10.0, 1.75, -10]], **{"p": [-6.25, 1.75, -10]})])
        self.assertTrue(any("into blocks[2]" in e for e in errors), errors)

    def test_a_ball_sunk_into_the_floor_is_an_error(self):
        errors = level_errors([ball(rad=1.0, path=[[0, 0.5, -30], [0, 0.5, -10]], **{"p": [0, 0.5, -30]})])
        self.assertTrue(any("rolls" in e and "into blocks[0]" in e for e in errors), errors)

    def test_a_slot_met_at_a_slant_is_an_error(self):
        errors = level_errors([zigzag(path=[[-3, 0.5, -5], [7.5, 0.5, -8.0]])])
        self.assertTrue(any("at a slant" in e for e in errors), errors)

    def test_a_bend_smaller_than_five_degrees_needs_no_wall(self):
        errors = level_errors([zigzag(path=[[0, 0.5, -5], [0.5, 0.5, -12], [1.25, 0.5, -19]])])
        self.assertEqual(errors, [])



class ShotPlan(unittest.TestCase):
    def test_a_ball_lands_bounces_rolls_and_is_swallowed_by_the_far_wall(self):
        plan = shot_plan.shot_plan(cannon(), ROAD)
        self.assertEqual(plan["kind"], "wall")
        self.assertAlmostEqual(plan["land"][1], 0.75)                 # its centre one radius over the floor
        self.assertGreater(plan["land"][0], -7.25)
        self.assertLess(plan["land"][0], 0.0)
        self.assertEqual(len(plan["segments"]), 4)                    # the arc, two bounces, the roll
        self.assertGreater(plan["end"], plan["hit"])                  # the last metres are inside the wall, harmless
        self.assertAlmostEqual(plan["end"] - plan["hit"], (2 * 0.75 + shot_plan.SWALLOW) / plan["segments"][-1][2][0] / 1.0, places=6)
        self.assertAlmostEqual(plan["port"]["point"][0], 8.0)
        self.assertEqual(plan["port"]["normal"], [-1.0, -0.0, -0.0])

    def test_the_level_23_numbers_stay_what_the_engine_computes(self):
        data = json.loads((LEVELS / "level_23.json").read_text())
        plans = {h["id"]: shot_plan.shot_plan(h, data["blocks"]) for h in data["hazards"] if h["k"] == "cannon"}
        self.assertAlmostEqual(plans["cannon_1"]["hit"], 3.27, places=2)
        self.assertAlmostEqual(plans["cannon_1"]["end"], 3.74, places=2)
        self.assertAlmostEqual(plans["cannon_3"]["end"], 1.54, places=2)
        self.assertAlmostEqual(plans["cannon_1"]["land"][0], -1.65, places=2)
        for plan in plans.values():
            self.assertEqual(plan["kind"], "wall")

    def test_a_ball_that_rolls_off_the_floor_falls(self):
        blocks = [{"k": "box", "p": [0, -0.5, -20], "s": [16, 1, 40]}]
        plan = shot_plan.shot_plan(cannon(), blocks)
        self.assertEqual(plan["kind"], "edge")
        self.assertAlmostEqual(plan["end"] - plan["segments"][-1][0], math.sqrt(2 * shot_plan.FALL_DEPTH / shot_plan.GRAVITY))

    def test_a_ball_that_never_reaches_anything_is_kind_none(self):
        blocks = [{"k": "box", "p": [0, -0.5, -20], "s": [200, 1, 40]}]
        self.assertEqual(shot_plan.shot_plan(cannon(v=[1.0, 3.5, 0]), blocks)["kind"], "none")

    def test_landing_time(self):
        self.assertAlmostEqual(shot_plan.solve_landing(0.0, 8.5), 1.0)  # up 8.5 m/s, back down after 2 * 8.5 / 17 s ... the ball is at the start height again at 1 s
        self.assertAlmostEqual(shot_plan.solve_landing(5.25, 3.5), 1.0183, places=3)


class Lint(unittest.TestCase):
    def test_housed_balls_and_a_landing_cannon_ball_are_clean(self):
        self.assertEqual(level_errors([ball(), cannon()]), [])

    def test_a_ball_that_would_pop_is_an_error(self):
        errors = level_errors([ball(path=[[0, 6.0, -30], [0, 6.0, -10]], **{"p": [0, 6.0, -30]})])
        self.assertTrue(any("starts in open view" in e for e in errors), errors)
        self.assertTrue(any("ends in open view" in e for e in errors), errors)

    def test_a_period_too_short_for_the_housings_is_an_error(self):
        errors = level_errors([ball(period=3.0)])
        self.assertTrue(any("too short" in e and "at least 3.50" in e for e in errors), errors)

    def test_a_cannon_ball_cut_off_in_view_is_an_error(self):
        errors = level_errors([cannon(life=1.0)])
        self.assertTrue(any("vanish in view" in e for e in errors), errors)

    def test_a_cannon_ball_that_never_ends_is_an_error(self):
        errors = level_errors([cannon(v=[1.0, 3.5, 0])], blocks=[{"k": "box", "p": [0, -0.5, -20], "s": [200, 1, 40]}])
        self.assertTrue(any("never reaches a wall" in e for e in errors), errors)

    def test_every_shipped_level_is_clean(self):
        for path in sorted(LEVELS.glob("level_*.json")):
            number = int(path.stem.split("_")[1])
            self.assertEqual(level_lint.lint_level(path, number).errors, [], path.name)


if __name__ == "__main__":
    unittest.main()
