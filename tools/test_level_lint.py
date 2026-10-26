"""Unit tests for tools/level_lint.py: lasers, fire jets, spiked movers and the show additions (python3 -m unittest discover -s tools -p 'test_*.py')."""
import copy
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import level_lint  # noqa: E402

TESTDATA = Path(__file__).resolve().parent / "level_testdata"
BASE = {
    "format": "level-1", "number": 1, "title": "LINT TEST",
    "start": {"p": [0, 0, 0], "yaw": 0},
    "goal": {"p": [0, 2, -20], "s": [6, 4, 3], "yaw": 0},
    "path": [[0, 0, 0], [0, 0, -5], [0, 0, -10], [0, 0, -15], [0, 0, -20]],
    "kill": [],
    "blocks": [{"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24]}],
    "hazards": [],
}


def lint_hazards(*hazards):
    """The errors of a small valid level with these hazards."""
    level = copy.deepcopy(BASE)
    level["hazards"] = list(hazards)
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "level_01.json"
        path.write_text(json.dumps(level))
        return level_lint.lint_level(path, 1).errors


ISLAND = {"k": "box", "p": [40, -0.5, 0], "s": [8, 1, 8]}  # a block far off the course: not under the start
SURVIVAL_TILES = [{"k": "blink", "p": [x, -0.25, 0], "s": [3, 0.5, 3], "on": 20, "off": 600, "warn": 1.5} for x in (-3, 0, 3)]
GATE = {"k": "blink", "id": "gate", "p": [0, 1.5, -2], "s": [10, 3, 0.5], "on": 4, "off": 600, "warn": 1}


def show_level(**changes):
    """A valid race show level with these top-level keys changed (a value of None removes the key)."""
    level = copy.deepcopy(BASE)
    level.update({"modes": ["show"], "pool": False, "show": "race", "hazards": [copy.deepcopy(GATE)]})
    for key, value in changes.items():
        if value is None:
            level.pop(key, None)
        else:
            level[key] = value
    return level


def lint_level_data(level):
    """The report of a level given as a dictionary."""
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "level_01.json"
        path.write_text(json.dumps(level))
        return level_lint.lint_level(path, 1)


class ScorcherLintTest(unittest.TestCase):
    def assert_error(self, errors, fragment):
        self.assertTrue(any(fragment in text for text in errors), f"no error with {fragment!r} in {errors}")

    def test_sampler_level_is_clean(self):
        report = level_lint.lint_level(TESTDATA / "level_04.json", 4)
        self.assertEqual(report.errors, [])
        kinds = {h["k"] for h in json.loads((TESTDATA / "level_04.json").read_text())["hazards"]}
        self.assertTrue({"laser", "fire"} <= kinds)

    def test_valid_lasers_and_fire(self):
        self.assertEqual(lint_hazards(
            {"k": "laser", "p": [-4, 1, -6], "to": [8, 0, 0]},
            {"k": "laser", "p": [-4, 1, -8], "to": [8, 0, 0], "on": 2, "off": 1.5, "warn": 0.5, "move": [0, 2, 0], "period": 4, "pause": 0.5},
            {"k": "laser", "p": [0, 2, -10], "to": [4, 0, 0], "rate": 45, "axis": "y", "phase": 1},
            {"k": "fire", "p": [-2, 1.5, -12], "s": [2, 3, 2], "on": 2, "off": 2, "warn": 1},
            {"k": "fire", "g": "cyl", "p": [2, 1.5, -12], "d": 2, "h": 3},
            {"k": "slide", "p": [-3, 1, -14], "to": [6, 0, 0], "period": 4, "s": [1, 2, 1], "look": "spikes"},
            {"k": "spin", "p": [0, 1, -16], "s": [5, 0.5, 0.5], "rate": 40, "look": "spikes"},
        ), [])

    def test_laser_needs_a_beam(self):
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6]}), "laser needs to")
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [0.25, 0, 0]}), "0.5 to 40 m")

    def test_schedule_rules(self):
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [4, 0, 0], "on": 2}), "on and off together")
        self.assert_error(lint_hazards({"k": "fire", "p": [0, 1.5, -6], "s": [2, 3, 2], "on": 2, "off": 1, "warn": 1.5}), "longer than off")
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [4, 0, 0], "warn": 1}), "warn needs on and off")
        self.assert_error(lint_hazards({"k": "fire", "p": [0, 1.5, -6], "s": [2, 3, 2], "on": 0.3, "off": 2}), "on: 0.3 outside")

    def test_laser_motion_rules(self):
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [4, 0, 0], "move": [0, 2, 0]}), "missing 'period'")
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [4, 0, 0], "period": 4}), "belongs to a laser that moves")
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [4, 0, 0], "rate": 0}), "rate 0")
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [4, 0, 0], "axis": "x"}), "belongs to a laser that spins")
        self.assert_error(lint_hazards({"k": "laser", "p": [0, 1, -6], "to": [4, 0, 0], "hit": False}), "does not belong to 'laser'")

    def test_fire_shape_rules(self):
        self.assert_error(lint_hazards({"k": "fire", "p": [0, 1.5, -6], "g": "cone", "s": [2, 3, 2]}), "g must be box or cyl")
        self.assert_error(lint_hazards({"k": "fire", "g": "cyl", "p": [0, 1.5, -6], "h": 3}), "missing 'd'")
        self.assert_error(lint_hazards({"k": "fire", "p": [0, 1.5, -6]}), "box fire needs s")

    def test_spike_look_rules(self):
        self.assert_error(lint_hazards({"k": "slide", "p": [-3, 1, -14], "to": [6, 0, 0], "period": 4, "s": [1, 2, 1], "look": "spiky"}), "look must be")
        self.assert_error(lint_hazards({"k": "blink", "p": [0, 1, -8], "s": [2, 0.5, 2], "on": 2, "off": 2, "look": "spikes"}), "does not belong to 'blink'")


class SupportLintTest(unittest.TestCase):
    """Nothing hangs in the air: a swing's pivot is held by a block, a pad or bumper stands on a block."""
    HAMMER = {"k": "swing", "id": "hammer", "p": [0, 6.25, -8], "axis": "z", "a0": -40, "a1": 40, "period": 4,
              "parts": [{"k": "box", "p": [0, -2.5, 0], "s": [0.5, 5, 0.5]}, {"k": "box", "p": [0, -5.25, 0], "s": [2.5, 1.5, 2]}]}
    BEAM = {"k": "box", "p": [0, 6.5, -8], "s": [10, 0.75, 2]}

    def errors(self, hazards, extra_blocks=()):
        level = copy.deepcopy(BASE)
        level["blocks"] = level["blocks"] + [copy.deepcopy(b) for b in extra_blocks]
        level["hazards"] = [copy.deepcopy(h) for h in hazards]
        return lint_level_data(level).errors

    def assert_error(self, errors, fragment):
        self.assertTrue(any(fragment in text for text in errors), f"no error with {fragment!r} in {errors}")

    def test_a_hammer_hanging_from_nothing_is_an_error(self):
        self.assert_error(self.errors([self.HAMMER]), "hangs from nothing")

    def test_a_hammer_on_a_gantry_is_fine(self):
        self.assertEqual(self.errors([self.HAMMER], [self.BEAM]), [])

    def test_a_beam_beside_the_pivot_does_not_hold_it(self):
        beam = dict(self.BEAM, p=[0, 8.0, -8])
        self.assert_error(self.errors([self.HAMMER], [beam]), "hangs from nothing")

    def test_a_pad_and_a_bumper_float_or_stand(self):
        floating = {"k": "push", "id": "pad", "g": "box", "p": [0, 3, -8], "s": [2, 0.5, 2], "v": [0, 8, -10]}
        self.assert_error(self.errors([floating]), "floats more than")
        self.assertEqual(self.errors([dict(floating, p=[0, 0.75, -8])]), [])        # volume 0.5 m over the floor: its pad lies on it
        self.assert_error(self.errors([{"k": "bumper", "id": "bump", "p": [0, 4, -8], "rad": 1.25}]), "floats more than")
        self.assertEqual(self.errors([{"k": "bumper", "id": "bump", "p": [0, 1.5, -8], "rad": 1.25}]), [])

    def test_a_launcher_riding_a_hazard_needs_no_floor(self):
        deck = {"k": "slide", "id": "deck", "p": [0, 4, -8], "to": [4, 0, 0], "period": 4, "s": [4, 1, 4]}
        pad = {"k": "push", "id": "pad", "g": "box", "p": [0, 1, 0], "s": [2, 0.5, 2], "v": [0, 8, -10], "ride": "deck"}
        self.assertEqual(self.errors([deck, pad]), [])


class ShowLintTest(unittest.TestCase):
    def assert_error(self, report, fragment):
        self.assertTrue(any(fragment in text for text in report.errors), f"no error with {fragment!r} in {report.errors}")

    def test_valid_show_levels(self):
        report = lint_level_data(show_level())
        self.assertEqual(report.errors, [])
        self.assertFalse(any("start gate" in text for text in report.warnings))
        survival = show_level(show="survival", blocks=[], hazards=copy.deepcopy(SURVIVAL_TILES))
        self.assertEqual(lint_level_data(survival).errors, [])
        final = show_level(show="final", podium=[[40, 1, 10], [38, 0.5, 10], [42, 0.25, 10]])
        self.assertEqual(lint_level_data(final).errors, [])

    def test_show_needs_kind_and_pool(self):
        self.assert_error(lint_level_data(show_level(show=None)), "names its round")
        self.assert_error(lint_level_data(show_level(show="party")), "show: one of")
        self.assert_error(lint_level_data(show_level(pool=None)), "\"pool\": false")
        self.assert_error(lint_level_data(show_level(modes=["carry"])), "must list 'show'")

    def test_camera_stage_is_for_show_levels_only(self):
        self.assertEqual(lint_level_data(show_level(camera="stage")).errors, [])
        self.assert_error(lint_level_data(show_level(camera="orbit")), "camera: ")
        plain = copy.deepcopy(BASE)
        plain["camera"] = "stage"
        self.assert_error(lint_level_data(plain), "camera: ")

    def test_cap_is_for_race_show_levels_only(self):
        self.assertEqual(lint_level_data(show_level(cap=240)).errors, [])
        for bad in (30, 601, "240", True):
            self.assert_error(lint_level_data(show_level(cap=bad)), "cap: seconds")
        plain = show_level()
        del plain["show"]
        plain["cap"] = 240
        self.assert_error(lint_level_data(plain), "cap: seconds")

    def test_world_daylight_is_for_show_levels_only(self):
        self.assertEqual(lint_level_data(show_level(world="daylight")).errors, [])
        self.assert_error(lint_level_data(show_level(world="night")), "world: one of daylight")
        self.assert_error(lint_level_data(show_level(world=1)), "world: one of daylight")
        plain = copy.deepcopy(BASE)
        plain["world"] = "daylight"
        self.assert_error(lint_level_data(plain), "world: one of daylight")

    def test_block_tone_is_for_daylight_levels_only(self):
        def with_tone(tone, **changes):
            level = show_level(**changes)
            level["blocks"] = [dict(level["blocks"][0], tone=tone)]
            return level
        for tone in ("teal", "warm", "navy", "frame", "door", "crate", "eye", "court", "disc", "hub", "arch"):
            self.assertEqual(lint_level_data(with_tone(tone, world="daylight")).errors, [], tone)
        self.assert_error(lint_level_data(with_tone("teal")), "tone only on a level with")
        self.assert_error(lint_level_data(with_tone("pink", world="daylight")), "tone must be one of")
        part = {"k": "spin", "p": [0, 0.6, -10], "rate": 30, "parts": [{"k": "box", "p": [0, 0, 0], "s": [4, 0.5, 0.5], "tone": "teal"}]}
        level = show_level(world="daylight")
        level["hazards"].append(part)
        self.assert_error(lint_level_data(level), "unknown key 'tone'")

    def test_no_gallery(self):  # eliminated players spectate where they are: no level has a spectator pen
        self.assert_error(lint_level_data(show_level(gallery=[40, 0, 0])), "unknown top-level key 'gallery'")

    def test_survival_start_on_blink_tiles(self):
        tiles = copy.deepcopy(SURVIVAL_TILES)
        level = show_level(show="survival", blocks=[], hazards=tiles)
        self.assertEqual(lint_level_data(level).errors, [])
        self.assert_error(lint_level_data(dict(level, show="race", blocks=[ISLAND], hazards=tiles + [GATE])), "no ground top")

    def test_survival_has_no_static_ground(self):
        ground = {"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24]}
        level = show_level(show="survival", blocks=[ground], hazards=copy.deepcopy(SURVIVAL_TILES))
        self.assert_error(lint_level_data(level), "a survival level has no static ground")
        self.assertEqual(lint_level_data(dict(level, blocks=[])).errors, [])
        self.assertEqual(lint_level_data(dict(level, show="race", hazards=[copy.deepcopy(GATE)])).errors, [])  # a race keeps its ground

    def test_kill_volumes_stay_clear_of_floors(self):
        floor = {"k": "box", "p": [0, 0.5, -10], "s": [4, 1, 4]}
        base = show_level(blocks=copy.deepcopy(BASE["blocks"]) + [floor])
        self.assertEqual(lint_level_data(dict(base, kill=[{"p": [0, 5.0, -10], "s": [10, 2, 10], "yaw": 0}])).errors, [])
        for centre, what in ((1.5, "stands"), (2.5, "jumps")):
            volume = {"p": [0, centre + 1.0 - 0.9 + 0.0, -10], "s": [10, 2, 10], "yaw": 0}  # its underside is just under the courier's centre
            self.assert_error(lint_level_data(dict(base, kill=[volume])), "a courier that %s on blocks" % what)
        rising = {"k": "lift", "id": "up", "p": [0, 4.5, -4], "rise": 6, "s": [4, 1, 4], "hit": False}
        self.assert_error(lint_level_data(dict(base, hazards=[copy.deepcopy(GATE), rising], kill=[{"p": [0, 13.0, -4], "s": [10, 5, 10], "yaw": 0}])), "lift up")
        plain = {key: value for key, value in base.items() if key not in ("show", "pool")}  # not a show level: the rule is for the show only
        self.assertEqual(lint_level_data(dict(plain, modes=["carry"], hazards=[], kill=[{"p": [0, 1.75, -10], "s": [10, 2, 10], "yaw": 0}])).errors, [])

    def test_final_needs_a_podium(self):
        self.assert_error(lint_level_data(show_level(show="final")), "podium")
        self.assert_error(lint_level_data(show_level(podium=[[40, 0, 10], [38, 0, 10]])), "exactly 3 points")
        self.assert_error(lint_level_data(show_level(podium=[[40, 0, 10], [38, 0, 10], [42, 0.1, 10]])), "off the 0.25 grid")

    def test_start_gate_warning(self):
        for kind in ("race", "final"):
            level = show_level(show=kind, hazards=[], podium=[[40, 1, 10], [38, 0.5, 10], [42, 0.25, 10]])
            self.assertTrue(any("start gate" in text for text in lint_level_data(level).warnings), kind)
        self.assertFalse(any("start gate" in text for text in lint_level_data(show_level(show="survival", hazards=[])).warnings))
        short = dict(GATE, on=2)
        self.assertTrue(any("start gate" in text for text in lint_level_data(show_level(hazards=[short])).warnings))

    def test_blink_limits(self):
        self.assertEqual(lint_hazards({"k": "blink", "p": [0, 1, -8], "s": [2, 0.5, 2], "on": 4, "off": 600}), [])
        self.assertTrue(any("outside" in text for text in lint_hazards({"k": "blink", "p": [0, 1, -8], "s": [2, 0.5, 2], "on": 4, "off": 601})))

    def test_new_slot_ids(self):
        ids = ["arch_start", "arch_finish", "banner_1", "banner_2", "billboard_1", "billboard_2", "floor_start", "floor_finish", "crown"]
        slots = [{"id": name, "p": [0, 0, -20] if name == "floor_finish" else [0, 1, -4], "yaw": 0, "size": [4, 1.5]} for name in ids]  # floor_finish lies on the goal pad
        self.assertEqual(lint_level_data(show_level(slots=slots)).errors, [])
        self.assert_error(lint_level_data(show_level(slots=[slots[0], slots[0]])), "used twice")
        self.assert_error(lint_level_data(show_level(slots=[dict(slots[0], id="arch_middle")])), "is not a slot id")

    def test_finish_decal_lies_on_the_goal_pad(self):
        decal = {"id": "floor_finish", "p": [0, 0, -20], "yaw": 0, "size": [5, 5]}
        self.assertEqual(lint_level_data(show_level(slots=[decal])).errors, [])
        self.assertEqual(lint_level_data(show_level(slots=[dict(decal, p=[0.25, 0, -20])])).errors, [])  # inside the reach
        for off in ([0, 0, -25], [1.5, 0, -20], [0, 0, -18.5]):
            self.assert_error(lint_level_data(show_level(slots=[dict(decal, p=off)])), "off the goal pad's centre")
        self.assertEqual(lint_level_data(show_level(slots=[dict(decal, id="floor_start", p=[0, 0, -3])])).errors, [])  # the start decal is not on a pad

    def test_shipped_finish_decals_lie_on_their_goal_pad(self):
        for path in sorted((Path(__file__).resolve().parent.parent / "demo" / "levels").glob("level_*.json")):
            data = json.loads(path.read_text())
            for slot in data.get("slots", []):
                if slot.get("id") == "floor_finish":
                    off = ((slot["p"][0] - data["goal"]["p"][0]) ** 2 + (slot["p"][2] - data["goal"]["p"][2]) ** 2) ** 0.5
                    self.assertLessEqual(off, level_lint.FINISH_DECAL_REACH, f"{path.name}: floor_finish {off:.2f} m off the goal pad")

    def test_obstacle_slot_on_blocks_and_parts(self):
        box = {"k": "box", "p": [0, 0.5, -8], "s": [2, 1, 2], "slot": "obstacle_2"}
        part = {"k": "box", "p": [0, 0, 0], "s": [2, 1, 2], "slot": "obstacle_5"}
        level = show_level(blocks=BASE["blocks"] + [box], hazards=[
            GATE,
            {"k": "spin", "p": [0, 1, -17], "s": [6, 0.5, 0.5], "rate": 40, "slot": "obstacle_1"},
            {"k": "slide", "p": [0, 1, -14], "to": [4, 0, 0], "period": 4, "parts": [part]}])
        self.assertEqual(lint_level_data(level).errors, [])

    def test_gate_slot_on_the_start_gate(self):
        self.assertEqual(lint_level_data(show_level(hazards=[dict(GATE, slot="gate")])).errors, [])

    def test_bad_obstacle_slots(self):
        bad_block = {"k": "box", "p": [0, 0.5, -8], "s": [2, 1, 2], "slot": "poster_1"}
        self.assert_error(lint_level_data(show_level(blocks=BASE["blocks"] + [bad_block])), "must be one of obstacle_1..5")
        cyl = {"k": "cyl", "p": [0, 0.5, -8], "d": 2, "h": 1, "slot": "obstacle_1"}
        self.assert_error(lint_level_data(show_level(blocks=BASE["blocks"] + [cyl])), "slot belongs to boxes")
        part = {"k": "box", "p": [0, 0, 0], "s": [2, 1, 2], "slot": "nope"}
        self.assert_error(lint_level_data(show_level(hazards=[{"k": "spin", "p": [0, 1, -12], "parts": [part], "rate": 40}])), "must be one of obstacle_1..5")
        self.assertTrue(any("does not belong to 'bumper'" in text for text in lint_hazards({"k": "bumper", "p": [0, 1, -8], "slot": "obstacle_1"})))
        both = {"k": "spin", "p": [0, 1, -12], "parts": [{"k": "box", "p": [0, 0, 0], "s": [2, 1, 2]}], "rate": 40, "slot": "obstacle_1"}
        self.assertTrue(any("belongs on the parts" in text for text in lint_hazards(both)))

    def test_hero_prop_stand(self):
        """A hero_prop slot (p = bottom centre, size = [footprint, height]) stands on three tagged cylinders: d = footprint * 1, 2/3, 1/3, a third of the height each."""
        def stand(x, base, width, height):
            return [{"k": "cyl", "p": [x, base + height / 3 * (tier + 0.5), -8], "d": width * share, "h": height / 3, "slot": "hero_prop"}
                    for tier, share in enumerate((1.0, 2.0 / 3.0, 1.0 / 3.0))]
        slot = {"id": "hero_prop", "p": [0, 0, -8], "yaw": 0, "size": [4.5, 3.0]}
        level = show_level(slots=[slot, dict(slot, p=[6, 0, -8], size=[2.25, 1.5])], blocks=BASE["blocks"] + stand(0, 0, 4.5, 3.0) + stand(6, 0, 2.25, 1.5))
        self.assertEqual(lint_level_data(level).errors, [])  # the slot may repeat (the podium copies)
        self.assert_error(lint_level_data(show_level(slots=[slot])), "no cylinder block with slot hero_prop for tier 1")
        self.assert_error(lint_level_data(show_level(slots=[slot], blocks=BASE["blocks"] + stand(0, 0, 4.5, 3.0)[:2])), "for tier 3")
        self.assert_error(lint_level_data(show_level(blocks=BASE["blocks"] + stand(0, 0, 4.5, 3.0))), "is no tier of a hero_prop slot")
        box = {"k": "box", "p": [0, 0.5, -8], "s": [2, 1, 2], "slot": "hero_prop"}
        self.assert_error(lint_level_data(show_level(slots=[slot], blocks=BASE["blocks"] + stand(0, 0, 4.5, 3.0) + [box])), "belongs to static cylinder blocks")
        part = {"k": "cyl", "p": [0, 0, 0], "d": 2, "h": 1, "slot": "hero_prop"}
        self.assert_error(lint_level_data(show_level(hazards=[GATE, {"k": "spin", "p": [0, 1, -12], "parts": [part], "rate": 40}])), "belongs to static cylinder blocks")

    def test_obstacle_boards_may_repeat(self):
        board = {"id": "obstacle_2", "p": [0, 1.75, -8], "yaw": 0, "size": [2.75, 3.5]}
        self.assertEqual(lint_level_data(show_level(slots=[board, dict(board, p=[3, 1.75, -8])])).errors, [])
        arch = {"id": "arch_start", "p": [0, 1, -4], "yaw": 0, "size": [4, 1.5]}
        self.assert_error(lint_level_data(show_level(slots=[arch, arch])), "used twice")
        too_many = [dict(board, p=[0, 1.75, -4 - i * 0.25]) for i in range(level_lint.MAX_SLOTS + 1)]
        self.assert_error(lint_level_data(show_level(slots=too_many)), "slots")

    def test_cues(self):
        survival = {"show": "survival", "blocks": [], "hazards": copy.deepcopy(SURVIVAL_TILES)}
        cues = [{"t": 5.0, "until": 10.0, "slot": "obstacle_1"}, {"t": 14.25, "until": 18.75, "slot": "obstacle_2"}]
        self.assertEqual(lint_level_data(show_level(cues=cues, **survival)).errors, [])
        self.assert_error(lint_level_data(show_level(cues=cues)), "cues")  # a race level has no cues
        for bad in ([dict(cues[0], slot="poster_1")], [dict(cues[0], t=5.1)], [dict(cues[0], until=4.0)], [cues[1], cues[0]],
                    [dict(cues[0], until=15.0), cues[1]], [dict(cues[0], extra=1)], [cues[0]] * 13):
            self.assertTrue(lint_level_data(show_level(cues=bad, **survival)).errors, bad)

    def test_step_tiles(self):
        floors = [{"y": 0.0, "origin": [0.0, 0.0], "rows": ["n n ", " n L", "n 1 "]}, {"y": -4.0, "origin": [0.0, 0.0], "rows": ["n n", " n "]}]
        tiles = {"pitch": 2.5, "thick": 0.5, "floors": floors, "fit": [{"players": 3, "radius": 2.5}],
                 "kinds": {"n": {"delay": 0.75, "look": "plain"}, "L": {"delay": 2.5, "look": "logo"}, "1": {"delay": 0.25, "look": "obstacle", "slot": "obstacle_1"}}}
        level = show_level(show="survival", blocks=[], tiles=tiles)
        self.assertEqual(lint_level_data(level).errors, [])

        def broken(**changes):
            bad = copy.deepcopy(level)
            bad["tiles"].update(changes)
            return lint_level_data(bad).errors
        self.assertTrue(broken(kinds={"n": {"delay": 0.8, "look": "plain"}, "L": {"delay": 2.5, "look": "logo"}, "1": {"delay": 0.25, "look": "plain"}}))  # off the 0.25 grid
        self.assertTrue(broken(kinds={"n": {"delay": 0.75, "look": "glow"}}))
        self.assertTrue(broken(kinds={"n": {"delay": 0.75, "look": "obstacle"}}))  # an obstacle look names its slot
        self.assertTrue(broken(floors=[dict(floors[0]), dict(floors[1], y=-2.0)]))  # floors too close
        self.assertTrue(broken(floors=[dict(floors[0], rows=["n n", " n"])]))  # rows of different lengths
        self.assertTrue(broken(floors=[dict(floors[0], rows=["n x n"])]))  # not a kind
        self.assertTrue(broken(floors=[dict(floors[0], rows=["n n", "n n"])]))  # a neighbour in the next row sits half a tile over, not above
        self.assertTrue(broken(fit=[{"players": 3, "radius": 2.0}, {"players": 3, "radius": 4.0}]))
        self.assertTrue(broken(extra=1))
        many = [{"y": float(-4 * i), "origin": [0.0, 0.0], "rows": [("n " * 12).rstrip() if r % 2 == 0 else (" n" * 12) for r in range(13)]} for i in range(4)]
        self.assertTrue(broken(floors=many))  # 4 x 156 tiles: more than a byte each allows

    def test_stage_round(self):
        """A stage round: close floors (a one-way stack), raised pad kinds, `stage.starts` on tile tops, `stage.ground` one layer gap under the last floor, nothing killing before it."""
        rows = ["nnnnn", "nnnnn", "nnnnn", "nnnnn", "nnnnn"]
        pad = ["nnnnn", "nnnnn", "nnnnn", "nnpnn", "nnnnn"]
        tiles = {"grid": "square", "style": "stage", "wrap": True, "pitch": 3.5, "thick": 0.5,
                 "kinds": {"n": {"delay": 0.5, "look": "plain"}, "p": {"delay": 0.5, "look": "plain", "raise": 0.6, "tone": "#50639b"}},
                 "floors": [{"y": 0.0, "origin": [0.0, 0.0], "tone": "#647bb2", "rows": pad}, {"y": -1.6, "origin": [0.0, 0.0], "tone": "#d2aa70", "rows": rows}]}
        stage = {"enclosure": "a", "cap": 120.0, "starts": [[0.0, 0.6, 3.5]],
                 "ground": {"y": -3.2, "thick": 2.0, "centre": [0.0, 0.0], "size": [24.0, 24.0], "tone": "#55659f"}}
        level = show_level(show="survival", blocks=[], tiles=tiles, stage=stage, void_y=-17.2,
                           kill=[{"p": [0.0, -8.2, 0.0], "s": [60.0, 6.0, 60.0], "yaw": 0.0}])
        self.assertEqual(lint_level_data(level).errors, [])
        self.assertFalse([text for text in lint_level_data(level).warnings if "grid" in text])  # a stage round is off the hand-authoring grid on purpose

        def broken(stage_changes=None, **changes):
            bad = copy.deepcopy(level)
            bad["stage"].update(stage_changes or {})
            bad.update(changes)
            return lint_level_data(bad).errors
        self.assertTrue(broken(tiles=dict(tiles, floors=[dict(tiles["floors"][0]), dict(tiles["floors"][1], y=-0.8)])))  # floors closer than twice the thickness
        self.assertTrue(broken(stage_changes={"starts": [[0.0, 0.6, 0.0]]}))  # not a pad top
        self.assertTrue(broken(stage_changes={"starts": [[0.0, 0.6, 3.5], [1.0, 0.6, 3.5]]}))  # two starts closer than 3 m
        self.assertTrue(broken(stage_changes={"starts": []}))
        self.assertTrue(broken(stage_changes={"ground": dict(stage["ground"], y=-4.0)}))  # not one layer gap under the last floor
        self.assertTrue(broken(stage_changes={"ground": dict(stage["ground"], size=[10.0, 10.0])}))  # a tile over the ground's edge
        self.assertTrue(broken(stage_changes={"ground": {"y": -3.2}}))  # no size
        self.assertTrue(broken(stage_changes={"extra": 1}))
        self.assertTrue(broken(void_y=-4.0))  # kills before the ground
        self.assertTrue(broken(kill=[{"p": [0.0, -3.0, 0.0], "s": [60.0, 6.0, 60.0], "yaw": 0.0}]))
        self.assertTrue(broken(tiles=dict(tiles, sweeps=[{"floor": 0, "t": 10.0, "speed": 2.0}])))  # nothing takes a tile by the clock
        plain = copy.deepcopy(level)
        plain["tiles"]["style"] = ""
        self.assertTrue(lint_level_data(plain).errors)  # the floors of an ordinary level stay 3 m apart


class PosterDoorLintTest(unittest.TestCase):
    """`door` on an obstacle slot (levels/poster_doors.gd): problem posters (solid) and logo posters (open / torn), rows of them, a row that rides a slide, and the
    show levels' `rule` / `hint`. The hall is the BASE deck (x +-5, z -22..2) with walls at x +-5.25; the first row is at z -8, the sliding one at z -14."""

    WALLS = [{"k": "box", "p": [-5.25, 3.0, -10.0], "s": [0.5, 8.0, 24.0]}, {"k": "box", "p": [5.25, 3.0, -10.0], "s": [0.5, 8.0, 24.0]}]
    SLIDE = {"k": "slide", "id": "row", "p": [-1.0, 1.75, -14.25], "to": [2.0, 0.0, 0.0], "period": 6.0, "pause": 1.0}

    @staticmethod
    def cell(x, z, width, door, **extra):
        return dict({"id": "obstacle_1", "p": [x, 1.75, z], "yaw": 0.0, "size": [width, 3.5], "door": door}, **extra)

    def level(self, **changes):
        """A valid hall: the first row of five cells (one torn logo poster among four problem posters, each with its hidden block) and a sliding row (a logo
        poster in the middle of problem posters on a slide: it covers the hall from wall to wall at every pose)."""
        slots, blocks = [], copy.deepcopy(self.WALLS)
        for x in (-4.0, -2.0, 0.0, 2.0, 4.0):
            slots.append(self.cell(x, -8.0, 2.0, "torn" if x == 2.0 else "solid"))
            if x != 2.0:
                blocks.append({"k": "box", "p": [x, 1.75, -8.25], "s": [2.0, 3.5, 0.25]})
        parts = []
        for step in range(-3, 4):
            if step == 0:
                slots.append(self.cell(-1.0, -14.0, 2.0, "open", ride="row"))
            else:
                slots.append(self.cell(-1.0 + 2.0 * step, -14.0, 2.0, "solid", ride="row"))
                parts.append({"k": "box", "p": [2.0 * step, 0.0, 0.0], "s": [2.0, 3.5, 0.25]})
        slide = dict(copy.deepcopy(self.SLIDE), parts=parts)
        level = show_level(slots=slots, **changes)
        level["blocks"] = level["blocks"] + blocks
        level["hazards"] = level["hazards"] + [slide]
        return level

    def errors(self, level):
        return lint_level_data(level).errors

    def assert_error(self, level, fragment):
        errors = self.errors(level)
        self.assertTrue(any(fragment in text for text in errors), f"no error with {fragment!r} in {errors}")

    def test_valid_doors_rule_and_hint(self):
        self.assertEqual(self.errors(self.level(rule="RUN THROUGH THE LOGO  ·  PROBLEMS ARE WALLS", hint="THE LOGO POSTER TEARS, THE REST ARE WALLS")), [])

    def test_door_blocks(self):
        level = self.level()
        level["blocks"][-1]["p"][2] = -8.5  # the block too far back
        self.assert_error(level, "no hidden block")
        level = self.level()
        level["blocks"].pop()  # a solid door without a block
        self.assert_error(level, "no hidden block")
        level = self.level()
        level["slots"][1]["door"] = "open"  # a logo poster with its block still behind it
        self.assert_error(level, "block in its opening")
        level = self.level()
        level["hazards"][-1]["parts"][0]["p"][2] = -0.25  # a hazard part behind a riding door: too far back
        self.assert_error(level, "no hidden block")

    def test_door_keys(self):
        level = self.level()
        level["slots"][0]["door"] = "ajar"
        self.assertTrue(self.errors(level))
        level = self.level()
        level["slots"][0]["id"] = "poster_1"  # only an obstacle slot is a door
        self.assertTrue(self.errors(level))
        level = self.level()
        level["slots"].append({"id": "banner_1", "p": [0.0, 6.0, -8.0], "yaw": 0.0, "size": [4.0, 1.0], "ride": "row"})  # only a door rides
        self.assert_error(level, "ride is the id of a slide hazard")

    def test_logo_poster_width(self):
        level = self.level()
        level["slots"][3]["size"][0] = 1.5  # the torn logo poster too narrow for a courier
        self.assert_error(level, "at least 1.75 m")

    def test_every_row_has_a_logo_poster(self):
        level = self.level()
        level["slots"][3]["door"] = "solid"
        level["blocks"].append({"k": "box", "p": [2.0, 1.75, -8.25], "s": [2.0, 3.5, 0.25]})
        self.assert_error(level, "no logo poster")

    def test_first_row_has_one_logo_among_four_problems(self):
        level = self.level()
        level["slots"][0]["door"] = "open"  # two logo posters in the first row
        level["blocks"].remove({"k": "box", "p": [-4.0, 1.75, -8.25], "s": [2.0, 3.5, 0.25]})
        self.assert_error(level, "exactly one logo poster")
        level = self.level()
        level["slots"] = [s for s in level["slots"] if s["p"][0] != 4.0 or s["p"][2] != -8.0]  # three problem posters only
        level["blocks"].remove({"k": "box", "p": [4.0, 1.75, -8.25], "s": [2.0, 3.5, 0.25]})
        self.assert_error(level, "exactly one logo poster")

    def test_only_the_first_row_starts_torn(self):
        level = self.level()
        level["slots"][-4]["door"] = "torn"
        self.assert_error(level, "only a door of the first row starts torn")

    def test_riding_doors(self):
        level = self.level()
        level["slots"][6]["ride"] = "nothing"  # a ride that names no hazard
        self.assert_error(level, "is not the id of a slide hazard")
        level = self.level()
        level["hazards"][-1]["hit"] = True  # a sliding row that knocks the courier about
        self.assert_error(level, "no hit, no turn")
        level = self.level()
        level["hazards"][-1]["to"] = [0.0, 0.0, -2.0]  # a slide along the way, not along the row
        self.assert_error(level, "no hit, no turn")
        level = self.level()
        level["slots"][6]["ride"] = None
        del level["slots"][6]["ride"]  # one door of the row stands still while the others slide
        self.assert_error(level, "a row is one thing")
        level = self.level()
        level["hazards"][-1]["period"] = 12.0  # the opening takes too long to come round
        self.assert_error(level, "round trip")

    def test_a_row_seals_the_hall_at_every_pose(self):
        level = self.level()
        level["slots"] = [s for s in level["slots"] if s["p"][0] != 5.0 or s["p"][2] != -14.0]  # the last problem poster is gone from the slide's right end
        level["hazards"][-1]["parts"].pop()
        self.assert_error(level, "slit")
        level = self.level()
        level["hazards"][-1]["to"] = [6.0, 0.0, 0.0]  # the opening leaves the hall at the end of the travel
        self.assert_error(level, "leaves the hall")
        level = self.level()
        level["blocks"] = [b for b in level["blocks"] if b["s"][1] < 8.0]  # no walls to seal against
        self.assert_error(level, "no tall wall block")

    def test_rule_and_hint_text(self):
        for key in ("rule", "hint"):
            for bad in ("lower case", "", "X" * 49, 5):
                self.assertTrue(self.errors(self.level(**{key: bad})), (key, bad))
        carry = copy.deepcopy(BASE)
        carry["rule"] = "NOT A SHOW LEVEL"
        self.assertTrue(lint_level_data(carry).errors)


class BumperDrawnShapeTest(unittest.TestCase):
    """What is drawn bumps (levels/hazards.gd BUMPER_BAND, level_world.gd _bumper_touched, style/hazard_looks.gd _bumper): the band the look wraps round a
    bumper's ball and the reach of the bump come from one constant, and the bump is a test of the courier's capsule against it, not of a point inside the ball."""
    DEMO = Path(__file__).resolve().parent.parent / "demo"

    def source(self, relative):
        return (self.DEMO / relative).read_text()

    def test_look_and_trigger_share_the_band(self):
        self.assertRegex(self.source("levels/hazards.gd"), r"(?m)^const BUMPER_BAND := 0\.\d+")
        self.assertIn("ring.outer_radius = radius + Hazards.BUMPER_BAND", self.source("style/hazard_looks.gd"))
        world = self.source("levels/level_world.gd")
        body = re.search(r"func _bumper_touched\(.*?\n(?=\n|func |##)", world, re.S)
        self.assertIsNotNone(body, "level_world.gd has no _bumper_touched")
        for needle in ("float(h.rad)", "Hazards.BUMPER_BAND", "COURIER_RADIUS", "COURIER_HALF_SEGMENT"):
            self.assertIn(needle, body.group(0), f"_bumper_touched no longer uses {needle}")
        self.assertIn("return _bumper_touched(h, local, frame.origin)", world)
        self.assertNotIn("inside = point.length() <= float(h.rad)", world)  # not a centre-point test (the centre inside the ball leaves the body 0.35 m into it)

    def test_tool_constants_match_the_courier(self):
        world = self.source("levels/level_world.gd")
        for name, value in (("COURIER_RADIUS", "0.35"), ("COURIER_HALF_SEGMENT", "0.55"), ("CENTRE_HEIGHT", "0.9")):
            self.assertRegex(world, rf"(?m)^const {name} := {re.escape(value)}")
        self.assertEqual(level_lint.CENTRE_HEIGHT, 0.9)


class PictureFloorLintTest(unittest.TestCase):
    """Picture faces never merge with a floor (docs/level-format.md "Pictures and floors"): the BASE deck is a floor with its top at y 0 over x +-5, z -22..2."""
    PHOTO = {"k": "box", "p": [0, 0.25, -5], "s": [2, 0.5, 2], "slot": "obstacle_1"}  # resting on the deck
    BEAM = {"k": "box", "p": [0, 6.5, -8], "s": [10, 0.75, 2]}

    def errors(self, blocks=(), hazards=(), slots=(), **changes):
        level = show_level(blocks=[copy.deepcopy(BASE["blocks"][0])] + [copy.deepcopy(b) for b in blocks],
                           hazards=[copy.deepcopy(GATE)] + [copy.deepcopy(h) for h in hazards], slots=[copy.deepcopy(s) for s in slots], **changes)
        return lint_level_data(level).errors

    def assert_error(self, errors, fragment):
        self.assertTrue(any(fragment in text for text in errors), f"no error with {fragment!r} in {errors}")

    def test_a_box_resting_on_the_floor_is_clean(self):
        self.assertEqual(self.errors([self.PHOTO]), [])

    def test_a_box_sunk_into_the_floor_is_cut(self):
        errors = self.errors([dict(self.PHOTO, p=[0, 0.0, -5], s=[2, 0.5, 2])])
        self.assert_error(errors, "blocks[1]: the picture on its +x face is cut with the floor blocks[0]")
        self.assertEqual(self.errors([dict(self.PHOTO, p=[0, 0.5, -5])]), [])  # lifted clear: only its bottom touches the floor

    def test_a_face_in_the_floors_plane_is_coplanar(self):
        errors = self.errors([{"k": "box", "p": [0, -1.5, -10], "s": [10, 3, 4], "slot": "obstacle_2"}])   # top and both sides flush with the deck, overlapping it
        self.assert_error(errors, "the picture on its +y face is coplanar with the floor blocks[0]")
        self.assert_error(errors, "the picture on its +x face is coplanar with the floor blocks[0]")

    def test_a_pier_butting_the_floors_end_is_clean_until_it_is_wider(self):
        self.assertEqual(self.errors([{"k": "box", "p": [0, -0.5, -25], "s": [10, 1, 6], "slot": "obstacle_3"}]), [])   # touches the deck end, buried whole
        self.assert_error(self.errors([{"k": "box", "p": [0, -0.5, -25], "s": [14, 1, 6], "slot": "obstacle_3"}]), "+z face is cut with the floor blocks[0]")

    def test_a_wall_is_not_a_floor(self):
        wall = {"k": "box", "p": [5.25, 4, -5], "s": [0.5, 8, 6]}
        self.assertEqual(self.errors([wall, {"k": "box", "p": [3.5, 0.5, -5], "s": [3, 1, 6], "slot": "obstacle_4"}]), [])
        rail = {"k": "box", "p": [5.25, 0.5, -5], "s": [0.5, 1, 6]}   # a deck's rim is: a picture box sunk half into it is cut
        self.assert_error(self.errors([rail, {"k": "box", "p": [3.5, 0.5, -5], "s": [3, 1, 8], "slot": "obstacle_4"}]), "is cut with the floor blocks[1]")

    def test_coplanar_floor_tops_must_not_overlap(self):
        self.assert_error(self.errors([{"k": "box", "p": [0, -0.5, -24], "s": [10, 1, 6]}]), "floor tops at y 0.0 overlap by 10.0 x 1.0")
        self.assertEqual(self.errors([{"k": "box", "p": [0, -0.5, -25], "s": [10, 1, 6]}]), [])   # the tops only touch
        self.assertEqual(self.errors([{"k": "box", "p": [0, 0.5, -10], "s": [4, 1, 4]}]), [])      # a step on the deck is a different top

    def test_movers_are_tested_at_every_pose(self):
        slab = {"k": "slide", "id": "slab", "p": [0, 0, -5], "to": [2, 0, 0], "period": 4, "s": [2, 0.5, 2], "slot": "obstacle_2"}
        self.assert_error(self.errors(hazards=[slab]), "hazards[1] (slide slab): the picture on a box's")
        self.assertEqual(self.errors(hazards=[dict(slab, p=[0, 0.25, -5])]), [])
        lift = {"k": "lift", "id": "up", "p": [0, -2, -5], "rise": 4, "period": 4, "s": [2, 1, 2], "slot": "obstacle_2"}   # rises through the deck
        self.assert_error(self.errors(hazards=[lift]), "hazards[1] (lift up)")

    def test_a_hammer_head_swinging_into_the_floor_is_cut(self):
        head = {"k": "box", "p": [0, -5.25, 0], "s": [2.5, 1.5, 2], "slot": "obstacle_3"}
        hammer = {"k": "swing", "id": "hammer", "p": [0, 6.25, -8], "axis": "z", "a0": -40, "a1": 40, "period": 4,
                  "parts": [{"k": "box", "p": [0, -2.5, 0], "s": [0.5, 5, 0.5]}, head]}
        self.assertEqual(self.errors([self.BEAM], [hammer]), [])
        low = dict(hammer, p=[0, 5.25, -8])   # the head at rest centres on the floor top
        self.assert_error(self.errors([dict(self.BEAM, p=[0, 5.25, -8])], [low]), "hazards[1] (swing hammer): the picture on a box's")

    def test_boards_do_not_sink_into_a_floor(self):
        board = {"id": "obstacle_1", "p": [0, 0.5, -5], "yaw": 0, "size": [2, 1]}
        self.assertEqual(self.errors(slots=[board]), [])
        self.assert_error(self.errors(slots=[dict(board, p=[0, 0.0, -5])]), "slots[0] (obstacle_1): the board at")
        self.assertEqual(self.errors(slots=[{"id": "floor_start", "p": [0, 0.0, -3], "yaw": 0, "size": [8, 2]}]), [])   # a decal lies on the floor by design

    def test_only_show_levels_are_checked(self):
        level = copy.deepcopy(BASE)
        level["blocks"] = level["blocks"] + [dict(self.PHOTO, p=[0, 0.0, -5])]
        self.assertEqual(lint_level_data(level).errors, [])

    def test_the_show_levels_have_no_picture_in_a_floor(self):
        levels = Path(__file__).resolve().parent.parent / "demo" / "levels"
        for number in range(14, 25):
            report = level_lint.lint_level(levels / f"level_{number:02d}.json", number)
            bad = [text for text in report.errors if "the picture on" in text or "the board at" in text or "floor tops" in text]
            self.assertEqual(bad, [], f"level_{number:02d}.json")


class BeltLintTest(unittest.TestCase):
    """Conveyor belts (`m: belt` + `belt` [vx, vz], docs/level-format.md "Conveyor belts") and the raised limits (600 blocks, 80 hazards)."""
    BELT = {"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24], "m": "belt", "belt": [0, -3]}   # as wide and long as the BASE deck: the belt alone is the start and goal ground

    def errors(self, blocks=(), hazards=(), **changes):
        level = show_level(blocks=[copy.deepcopy(BASE["blocks"][0])] + [copy.deepcopy(b) for b in blocks], hazards=[copy.deepcopy(GATE)] + [copy.deepcopy(h) for h in hazards], **changes)
        return lint_level_data(level).errors

    def belt_errors(self, **changes):
        belt = dict(self.BELT, **{key: value for key, value in changes.items() if value is not None})
        for key, value in changes.items():
            if value is None:
                belt.pop(key, None)
        level = copy.deepcopy(BASE)
        level["blocks"] = [belt]
        return lint_level_data(level).errors

    def assert_error(self, errors, fragment):
        self.assertTrue(any(fragment in text for text in errors), f"no error with {fragment!r} in {errors}")

    def test_a_valid_belt_is_clean_and_a_floor(self):
        self.assertEqual(self.belt_errors(), [])                                                   # the belt alone is the start and path ground
        self.assertEqual([text for text in self.belt_errors(belt=[-1.5, 0], r=[0, 90, 0]) if "belt" in text], [])   # a turned belt covers other ground: only its own rules are checked
        self.assertEqual(self.belt_errors(belt=[8, 0]), [])
        self.assertEqual(self.belt_errors(belt=[0.5, 0]), [])
        self.assertEqual(self.belt_errors(belt=[3, 4]), [])                                        # 5 m/s along a diagonal

    def test_belt_needs_a_valid_vector(self):
        self.assert_error(self.belt_errors(belt=None), "needs belt [vx, vz]")
        self.assert_error(self.belt_errors(belt=[1, 2, 3]), "needs belt [vx, vz]")
        self.assert_error(self.belt_errors(belt=[0, 0]), "runs at 0.00 m/s")
        self.assert_error(self.belt_errors(belt=[0, 8.5]), "runs at 8.50 m/s")
        self.assert_error(self.belt_errors(belt=[0, -3.25]), "off the 0.5 grid")

    def test_belt_only_with_m_belt_and_on_upright_boxes(self):
        self.assert_error(lint_level_data(dict(copy.deepcopy(BASE), blocks=[dict(self.BELT, m="ground")])).errors, "belt belongs to blocks with m belt")
        self.assert_error(lint_level_data(dict(copy.deepcopy(BASE), blocks=[{"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24], "belt": [0, -3]}])).errors, "belt belongs to blocks with m belt")
        self.assert_error(self.belt_errors(r=[0, 45, 0]), "upright and turned about y by 0, 90, 180 or 270")
        self.assert_error(self.belt_errors(r=[5, 0, 0]), "upright and turned about y")
        self.assert_error(self.belt_errors(k="cyl", d=4, h=1), "a belt is a box")
        self.assert_error(self.belt_errors(hit=True), "cannot be hit")
        self.assert_error(self.belt_errors(m="rubber"), "m must be ground, ice, belt or slime")

    def test_belt_is_not_allowed_on_a_hazard_part(self):
        part = dict(self.BELT, p=[0, 0, 0])
        self.assert_error(self.errors(hazards=[{"k": "slide", "id": "deck", "p": [0, 1, -14], "to": [4, 0, 0], "period": 4, "parts": [part]}]), "unknown key 'm'")

    def test_belts_are_floors_for_the_picture_rules(self):
        deck = dict(self.BELT, p=[0, -0.5, -25], s=[10, 1, 6], belt=[0, 2])           # a belt in the plane of the base deck's end: tops touch, no overlap
        self.assertEqual(self.errors([deck]), [])
        overlap = dict(deck, p=[0, -0.5, -24])
        self.assert_error(self.errors([overlap]), "floor tops at y 0.0 overlap")
        photo = {"k": "box", "p": [0, 0.0, -10], "s": [2, 0.5, 2], "slot": "obstacle_2"}
        belt_floor = dict(self.BELT, p=[0, -0.5, -40], s=[10, 1, 12])
        sunk = dict(photo, p=[0, 0.0, -40])
        self.assert_error(self.errors([belt_floor, sunk]), "is cut with the floor blocks[1]")   # the picture rules see the belt as a floor

    def test_limits_are_600_blocks_and_80_hazards(self):
        self.assertEqual((level_lint.MAX_BLOCKS, level_lint.MAX_HAZARDS), (600, 80))
        def stones(count):
            return [{"k": "box", "p": [20 + (i % 20) * 1.5, -0.5, -10 - (i // 20) * 1.5], "s": [1, 1, 1]} for i in range(count)]
        many = lint_level_data(dict(copy.deepcopy(BASE), blocks=copy.deepcopy(BASE["blocks"]) + stones(599))).errors
        self.assertFalse(any("blocks (at most" in text for text in many), many)
        too_many = lint_level_data(dict(copy.deepcopy(BASE), blocks=copy.deepcopy(BASE["blocks"]) + stones(600))).errors
        self.assert_error(too_many, "601 blocks (at most 600)")
        spinners = [{"k": "spin", "id": f"s{i}", "p": [20 + i, 1, -10], "s": [2, 0.5, 0.5], "rate": 40} for i in range(81)]
        self.assert_error(lint_level_data(dict(copy.deepcopy(BASE), hazards=spinners)).errors, "at most 80")
        ok = lint_level_data(dict(copy.deepcopy(BASE), hazards=spinners[:80])).errors
        self.assertFalse(any("at most 80" in text for text in ok), ok)


class ItemBoxLintTest(unittest.TestCase):
    """`item_boxes`: rows of boxes on a race show level, each on flat static floor, clear of every hazard and kill volume."""
    ROW = {"p": [0, 0, -12], "n": 3, "step": 1.8, "yaw": 0}

    def errors(self, rows, **changes):
        return [text for text in lint_level_data(show_level(item_boxes=rows, **changes)).errors if "item_boxes" in text]

    def assert_error(self, errors, text):
        self.assertTrue(any(text in e for e in errors), errors)

    def test_a_good_row_passes_and_only_a_race_has_boxes(self):
        self.assertEqual(self.errors([self.ROW]), [])
        self.assertEqual(self.errors([self.ROW], hazards=[copy.deepcopy(GATE)], show="race"), [])
        self.assert_error([e for e in lint_level_data(show_level(item_boxes=[self.ROW], show="final", podium=[[40, 1, 10], [38, 0.5, 10], [42, 0.25, 10]])).errors], "only a race show level")
        plain = copy.deepcopy(BASE)
        plain["item_boxes"] = [self.ROW]
        self.assertTrue(any("unknown top-level key 'item_boxes'" in e or "only a race" in e for e in lint_level_data(plain).errors))

    def test_the_row_shape(self):
        self.assert_error(self.errors("rows"), "a list of at most 5 rows")
        self.assert_error(self.errors([dict(self.ROW, n=5)]), "n: a whole number 1-4")
        self.assert_error(self.errors([dict(self.ROW, n=2.0)]), "n: a whole number 1-4")
        self.assert_error(self.errors([dict(self.ROW, step=1.0)]), "step: 1.2-3.0")
        self.assert_error(self.errors([dict(self.ROW, yaw="north")]), "yaw: degrees")
        self.assert_error(self.errors([dict(self.ROW, colour="red")]), "item_boxes[0]")
        self.assert_error(self.errors([{"n": 2}]), "item_boxes[0]")
        self.assert_error(self.errors([dict(self.ROW, p=[0, 0, -5 - 2 * i]) for i in range(6)]), "at most 5 rows")
        rows = [dict(self.ROW, p=[0, 0, -3 - 3.5 * i]) for i in range(4)] + [dict(self.ROW, p=[0, 0, -17], n=4)]
        self.assert_error(self.errors(rows), "16 boxes (at most 12)")

    def test_every_box_stands_on_flat_static_floor(self):
        self.assert_error(self.errors([dict(self.ROW, p=[0, 0.6, -12])]), "the floor top is 0.00 m")
        self.assert_error(self.errors([dict(self.ROW, n=4, step=3.0)]), "item_boxes[0] box 0")   # the ends at x = +-4.5 have their pedestal (and its margin, 0.94 m) over the floor's edge (5 m half width)
        self.assert_error(self.errors([dict(self.ROW, p=[9, 0, -12])]), "no static floor under it")
        self.assertEqual(self.errors([dict(self.ROW, p=[0, 0.04, -12])]), [])    # within 5 cm in the middle
        self.assert_error(self.errors([dict(self.ROW, p=[0, 0.1, -12])]), "the floor under the middle of the row")
        belt = {"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24], "m": "belt", "belt": [0, -2]}
        self.assert_error(self.errors([self.ROW], blocks=[belt]), "belt block")
        slime = {"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24], "m": "ice"}
        self.assert_error(self.errors([self.ROW], blocks=[slime]), "ice block")
        step = [{"k": "box", "p": [0, -0.5, -10], "s": [10, 1, 24]}, {"k": "box", "p": [0.5, 0.05, -12], "s": [1.5, 0.1, 1.5]}]   # a raised plate under one pedestal: not one flat floor
        self.assert_error(self.errors([dict(self.ROW, n=1, p=[0, 0.1, -12])], blocks=step), "item_boxes[0]")

    def test_a_wall_or_a_rail_beside_the_box_is_a_clash(self):
        rail = {"k": "box", "p": [1.0, 0.5, -12], "s": [0.5, 1.0, 8]}
        self.assert_error(self.errors([dict(self.ROW, n=1)], blocks=copy.deepcopy(BASE["blocks"]) + [rail]), "item_boxes[0]")
        far = dict(rail, p=[3.5, 0.5, -12])
        self.assertEqual(self.errors([dict(self.ROW, n=1)], blocks=copy.deepcopy(BASE["blocks"]) + [far]), [])

    def test_two_and_a_half_metres_from_every_hazard_and_kill_volume(self):
        spinner = {"k": "spin", "id": "bar", "p": [0, 1, -15], "s": [4, 0.5, 0.5], "rate": 40}
        self.assert_error(self.errors([self.ROW], hazards=[copy.deepcopy(GATE), spinner]), "spin bar")    # its sphere (radius 2.03) is 1 m from the middle box
        self.assertEqual(self.errors([dict(self.ROW, p=[0, 0, -8])], hazards=[copy.deepcopy(GATE), dict(spinner, p=[0, 1, -17])]), [])
        wall = {"k": "slide", "id": "wall", "p": [-4, 1, -12], "to": [8, 0, 0], "period": 4, "s": [1, 2, 1]}
        self.assert_error(self.errors([self.ROW], hazards=[copy.deepcopy(GATE), wall]), "slide wall")   # it sweeps through the row
        self.assert_error(self.errors([dict(self.ROW, p=[0, 0, -12])], kill=[{"p": [0, 1, -14.5], "s": [6, 2, 2]}]), "kill[0]")
        self.assertEqual(self.errors([dict(self.ROW, p=[0, 0, -12])], kill=[{"p": [0, 1, -20], "s": [6, 2, 2]}]), [])


class EdgeBumpersSwitchTest(unittest.TestCase):
    """`demo/levels/edge_bumpers.json`, the switch of the edge bumpers experiment: format, label, `on`, and one {on, share, seed} per listed race level."""
    SWITCH = {"format": "edge-bumpers-1", "experiment": "EXPERIMENT: test", "on": True, "levels": {"29": {"on": True, "share": 0.5, "seed": 7}}}

    def errors(self, switch, **level):
        race = {"number": 29, "show": "race", "world": "daylight"}
        race.update(level)
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "level_29.json").write_text(json.dumps(race))
            path = Path(folder) / "edge_bumpers.json"
            path.write_text(json.dumps(switch))
            return level_lint.lint_edge_bumpers(path, [Path(folder) / "level_29.json"]).errors

    def test_a_valid_switch_passes_and_off_is_valid_too(self):
        self.assertEqual(self.errors(self.SWITCH), [])
        self.assertEqual(self.errors(dict(self.SWITCH, on=False)), [])

    def test_the_label_the_format_and_the_flag_are_required(self):
        self.assertTrue(any("format" in e for e in self.errors(dict(self.SWITCH, format="edge-bumpers-0"))))
        self.assertTrue(any("experiment" in e for e in self.errors({k: v for k, v in self.SWITCH.items() if k != "experiment"})))
        self.assertTrue(any("on must" in e for e in self.errors(dict(self.SWITCH, on="yes"))))

    def test_a_level_must_exist_be_a_race_level_and_have_a_sane_share_and_seed(self):
        self.assertTrue(any("levels.30" in e for e in self.errors(dict(self.SWITCH, levels={"30": {"on": True}}))))
        self.assertTrue(any("race show levels" in e for e in self.errors(self.SWITCH, show="survival")))
        self.assertTrue(any("share" in e for e in self.errors(dict(self.SWITCH, levels={"29": {"on": True, "share": 1.2}}))))
        self.assertTrue(any("seed" in e for e in self.errors(dict(self.SWITCH, levels={"29": {"on": True, "seed": 1.5}}))))


if __name__ == "__main__":
    unittest.main()
