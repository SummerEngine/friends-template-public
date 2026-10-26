#!/usr/bin/env python3
"""Tests of tools/cast_check.py: the cast validator and the locked-file guard.

    (cd tools && python3 -m unittest test_cast_check)
"""
import hashlib
import json
import math
import shutil
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

import cast_check
import cast_fonts

GOOD = {
    "format": "team-cast-v1",
    "team": {"name": "Sommer Spil", "tagline": "Bær kunsten · knæk ikke noget"},
    "object": {"kind": "landscape", "picture": "logo.png", "fit": "contain"},
    "players": [{"name": "Søren", "color": "#22aa55", "catchphrase": "Ship it!"}, {"name": "Ida", "color": "#aa22cc", "skin": "#a56b45"}],
    "words": {"break": "KNÆK!"},
}


def png(width, height):
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * width for _ in range(height))
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


class CastTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / "logo.png").write_bytes(png(300, 300))

    def tearDown(self):
        shutil.rmtree(self.dir)

    def problems(self, cast):
        path = self.dir / "cast.json"
        path.write_text(json.dumps(cast, ensure_ascii=False), encoding="utf-8")
        return cast_check.check_cast(path)

    def changed(self, **parts):
        cast = json.loads(json.dumps(GOOD))
        for dotted, value in parts.items():
            *keys, last = dotted.split("__")
            target = cast
            for key in keys:
                target = target[int(key)] if isinstance(target, list) else target[key]
            target[last] = value
        return self.problems(cast)

    def test_good_cast_passes(self):
        self.assertEqual(self.problems(GOOD), [])

    def test_shipped_cast_passes(self):
        self.assertEqual(cast_check.check_cast(), [])

    def test_wrong_format(self):
        self.assertTrue(any("format" in p for p in self.changed(format="v0")))

    def test_unknown_field_is_named(self):
        problems = self.changed(team__logo="logo.png")
        self.assertTrue(any('no field "logo"' in p for p in problems), problems)

    def test_long_team_name(self):
        self.assertTrue(any("team.name" in p for p in self.changed(team__name="X" * 19)))

    def test_emoji_is_refused(self):
        self.assertTrue(any("cannot draw" in p for p in self.changed(players__0__name="Søren 🚀")))

    def test_bad_colour(self):
        self.assertTrue(any("colour" in p for p in self.changed(players__1__color="purple")))

    def test_too_many_players(self):
        self.assertTrue(any("1 to 8" in p for p in self.changed(players=[{"name": "A", "color": "#000000"}] * 9)))

    def test_missing_picture(self):
        self.assertTrue(any("not in demo/cast" in p for p in self.changed(object__picture="nope.png")))

    def test_picture_path_escape(self):
        self.assertTrue(any("plain file name" in p for p in self.changed(object__picture="../run.gd")))

    def test_unknown_object_kind(self):
        self.assertTrue(any("object.kind" in p for p in self.changed(object__kind="statue")))

    def test_object_kinds(self):
        for kind in ("landscape", "portrait", "glass"):
            self.assertEqual(self.changed(object__kind=kind), [], kind)

    def test_tiny_picture(self):
        (self.dir / "logo.png").write_bytes(png(20, 20))
        self.assertTrue(any("short side" in p for p in self.problems(GOOD)))

    def test_forbidden_name_in_cast_text(self):
        import clean_scan
        saved = {k: dict(v) for k, v in clean_scan.JOINED.items()}
        try:  # made-up words: one under a name rule, one under an ordinary-English rule (clean_scan.CAST_TEXT_OK)
            clean_scan.JOINED.setdefault(10, {})[clean_scan.fingerprint(b"zorbleflux")] = "rule 01"
            clean_scan.JOINED.setdefault(9, {})[clean_scan.fingerprint(b"quaximble")] = "rule 11"
            problems = self.changed(team__tagline="Zorbleflux forever")
            self.assertTrue(any("forbidden name" in p for p in problems), problems)
            self.assertEqual(self.changed(team__tagline="Quaximble forever"), [])
        finally:
            clean_scan.JOINED.clear()
            clean_scan.JOINED.update(saved)


def vorbis(seconds, rate=44100, channels=1):
    """Just enough of an Ogg Vorbis file for the check: the identification header and a last page with the sample position."""
    first = b"OggS" + bytes(22) + b"\x01vorbis" + struct.pack("<IBI", 0, channels, rate) + bytes(16)
    return first + b"OggS\x00\x04" + struct.pack("<q", int(seconds * rate)) + bytes(16)


def glb():
    """Just enough of a glTF binary for the check: the header and the JSON chunk."""
    document = b'{"asset":{"version":"2.0"}}  '
    body = struct.pack("<II", len(document), 0x4E4F534A) + document
    return b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body


def glb_mesh(points):
    """A glTF binary with one mesh node holding these (x, y, z) vertices: what the hero prop check reads."""
    binary = b"".join(struct.pack("<fff", *point) for point in points)
    document = json.dumps({"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
                           "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
                           "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(points), "type": "VEC3"}],
                           "bufferViews": [{"buffer": 0, "byteLength": len(binary)}], "buffers": [{"byteLength": len(binary)}]}).encode()
    document += b" " * (-len(document) % 4)
    body = struct.pack("<II", len(document), 0x4E4F534A) + document + struct.pack("<II", len(binary), 0x004E4942) + binary
    return b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body


def tiers(scale=1.0, wide=1.0):
    """Rings of vertices of a stepped stand like the template's: three drums 1 m tall of radius 2.25, 1.5 and 0.75 (times `wide` on the middle one)."""
    points = []
    for tier, radius in enumerate((2.25, 1.5 * wide, 0.75)):
        for y in (float(tier), float(tier + 1)):
            points += [(math.cos(k * math.tau / 24) * radius * scale, y * scale, math.sin(k * math.tau / 24) * radius * scale) for k in range(24)]
    return points


GOOD_V2 = {
    "format": "team-cast-v2",
    "team": {"name": "Acme", "tagline": "Four founders · one demo · don't drop it"},
    "brand": {"logo": "logo.png", "colors": ["#ff6a13", "#1d1d1f"]},
    "world": {"theme": "office"},
    "object": {"kind": "landscape", "picture": "print.png", "fit": "contain"},
    "balloon": {"shape": "blimp", "picture": "balloon.png"},
    "obstacles": [{"label": "FLAKY CI", "picture": "obstacle_1.png", "color": "#ffd23f"}, {"label": "CHAT PINGS"}],
    "posters": [{"picture": "poster_1.png", "caption": "SHIP FRIDAY"}],
    "eggs": ["Someone always says it's a quick one"],
    "players": [{"name": "Maja", "color": "#22aa55", "catchphrase": "Ship it!", "voice": "voice/member_1.ogg"},
                {"name": "Theo", "color": "#2c4bff", "hat": "beanie"}],
    "words": {"delivered": "SHIPPED", "break": "BUG!", "fall": "WHOOPS!", "pop": "POP!"},
    "music": "careful-step",
    "video": {"intro": "video/intro.ogv"},
}


class CastFontsTest(unittest.TestCase):
    def test_wanted(self):
        self.assertEqual(cast_fonts.wanted({"team": {"name": "忘年会"}, "players": [{"name": "Ida"}]}), (["会", "年", "忘"], ("sc", "jp")))
        self.assertEqual(cast_fonts.wanted({"players": [{"name": "さくら", "title": "年会"}]})[1], ("jp", "sc"))
        self.assertEqual(cast_fonts.wanted({"team": {"name": "Sommer"}, "words": {"reveal": "Ünïcødé"}}), ([], ("sc", "jp")))


class CastV2Test(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        for name, size in {"logo.png": (512, 512), "print.png": (512, 256), "balloon.png": (300, 300), "obstacle_1.png": (512, 256),
                           "poster_1.png": (384, 512)}.items():
            (self.dir / name).write_bytes(png(*size))
        (self.dir / "voice").mkdir()
        (self.dir / "voice/member_1.ogg").write_bytes(vorbis(1.5))
        (self.dir / "video").mkdir()
        (self.dir / "video/intro.ogv").write_bytes(b"OggS" + bytes(24) + b"\x80theora" + bytes(64))

    def tearDown(self):
        shutil.rmtree(self.dir)

    def problems(self, cast):
        path = self.dir / "cast.json"
        path.write_text(json.dumps(cast, ensure_ascii=False), encoding="utf-8")
        return cast_check.check_cast(path)

    def changed(self, **parts):
        cast = json.loads(json.dumps(GOOD_V2))
        for dotted, value in parts.items():
            *keys, last = dotted.split("__")
            target = cast
            for key in keys:
                target = target[int(key)] if isinstance(target, list) else target[key]
            if isinstance(target, list):
                target[int(last)] = value
            else:
                target[last] = value
        return self.problems(cast)

    def expect(self, needle, **parts):
        problems = self.changed(**parts)
        self.assertTrue(any(needle in p for p in problems), problems)

    def test_good_v2_cast_passes(self):
        self.assertEqual(self.problems(GOOD_V2), [])

    def test_sample_cast_passes(self):
        self.assertEqual(cast_check.check_cast(cast_check.ROOT / "samples/acme/cast.json"), [])

    def test_v1_cast_still_passes(self):
        cast = dict(GOOD)
        cast["object"] = {"kind": "portrait", "picture": "logo.png", "fit": "cover"}
        self.assertEqual(self.problems(cast), [])

    def test_v1_has_no_v2_fields(self):
        cast = dict(GOOD, brand={"logo": "logo.png"})
        self.assertTrue(any('no field "brand"' in p for p in self.problems(cast)))

    def test_fixed_file_names(self):
        (self.dir / "mylogo.png").write_bytes(png(300, 300))
        self.expect("fixed file names", brand__logo="mylogo.png")
        self.expect("fixed file names", obstacles__0__picture="poster_1.png")

    def test_missing_picture_file(self):
        self.expect("not in demo/cast", posters__0__picture="poster_1.webp")

    def test_picture_bytes_must_match_the_ending(self):
        (self.dir / "logo.jpg").write_bytes(png(300, 300))
        self.expect("is not a JPG picture", brand__logo="logo.jpg")

    def test_small_picture(self):
        (self.dir / "print.png").write_bytes(png(400, 200))
        self.expect("at least 256 px", object__picture="print.png")

    def test_webp_size_is_read(self):
        vp8l = b"RIFF" + struct.pack("<I", 30) + b"WEBP" + b"VP8L" + struct.pack("<I", 10) + b"\x2f" + ((300 - 1) | ((200 - 1) << 14)).to_bytes(4, "little") + bytes(8)
        (self.dir / "logo.webp").write_bytes(vp8l)
        self.expect("300x200 px", brand__logo="logo.webp")

    def test_shirt_print(self):
        (self.dir / "shirt_print.png").write_bytes(png(1024, 1024))
        self.assertEqual(self.problems(GOOD_V2), [])
        (self.dir / "shirt_print.png").write_bytes(png(200, 200))
        self.expect("at least 256 px")
        (self.dir / "shirt_print.png").unlink()
        (self.dir / "shirt_print.gif").write_bytes(png(1024, 1024))
        self.expect("fixed file names")

    def test_brand_colours(self):
        self.expect("brand.colors[1] must be a colour", brand__colors=["#ff6a13", "orange"])
        self.expect("1 to 3 colours", brand__colors=["#000000"] * 4)

    def test_theme_and_shape_are_closed_lists(self):
        self.expect("world.theme must be one of office, outdoor", world__theme="space")
        self.expect("balloon.shape must be one of", balloon__shape="kite")

    def test_world_style_is_a_closed_list(self):
        self.expect("world.style must be one of party, night, auto", world__style="neon")
        for style in ("party", "night", "auto"):
            self.assertEqual(self.changed(world__style=style), [], style)

    def test_obstacles(self):
        self.expect("obstacles[0].label is 17 characters", obstacles__0__label="X" * 17)
        self.expect("has no label", obstacles__1={"picture": ""})
        self.expect("at most 5", obstacles=[{"label": "A"}] * 6)
        self.expect("obstacles[0].color must be a colour", obstacles__0__color="red")

    def test_poster_caption(self):
        self.expect("posters[0].caption is 25 characters", posters__0__caption="Y" * 25)

    def test_egg_never_names_a_person(self):
        self.expect("names a cast member (Maja)", eggs=["Maja always says it's a quick one"])
        self.assertEqual(self.changed(eggs=["Majestic plans, quick ones"]), [])

    def test_music_must_be_an_id(self):
        self.expect("music must be one of careful-step", music="loud-song")
        self.assertEqual(self.changed(music="lofi"), [])  # an Ogg Vorbis loop

    def test_music_ids_are_the_loop_files(self):
        folder = self.dir / "music"
        folder.mkdir()
        for name in ("friends-careful-step.wav", "friends-lofi.ogg", "end-sting.wav"):
            (folder / name).write_bytes(b"x")
        self.assertEqual(cast_check.music_ids(folder), ["careful-step", "lofi"])

    def test_title_backdrop(self):
        (self.dir / "title_backdrop.png").write_bytes(png(1536, 1024))
        self.assertEqual(self.changed(title={"pet_ground": [0.885, 0.848]}), [])
        self.expect("two numbers from 0 to 1", title={"pet_ground": [1.2, 0.5]})
        self.expect("two numbers from 0 to 1", title={"pet_ground": "lower right"})
        self.expect('title has no field "backdrop"', title={"backdrop": "title_backdrop.png"})
        (self.dir / "title_backdrop.png").write_bytes(png(1024, 1024))
        self.expect("use a landscape picture of at least 1280x720", title={})
        (self.dir / "title_backdrop.png").write_bytes(png(1536, 1024))
        (self.dir / "title_backdrop.jpg").write_bytes(png(1536, 1024))
        self.expect("keep one", title={})
        self.expect("is not a JPG picture", title={})

    def test_japanese_and_chinese(self):
        self.expect("run python3 tools/cast_fonts.py", team__name="忘年会")
        self.expect("the game's font cannot draw", players__0__catchphrase="Ship it 🚀")
        fonts = self.dir / "fonts"
        fonts.mkdir()
        (fonts / "fallback_1.ttf").write_bytes(b"\x00\x01\x00\x00")
        (fonts / "fallback.txt").write_text("会年忘\n", encoding="utf-8")
        self.assertEqual(self.changed(team__name="忘年会"), [])
        self.expect("do not have yet: '新'", team__name="新年会")

    def test_titles(self):
        self.assertEqual(self.changed(team__title="ACME: DON'T DROP THE PARCEL", players__0__title="THE FIXER"), [])
        self.expect("team.title is 41 characters", team__title="T" * 41)
        self.expect("players[0].title is 17 characters", players__0__title="F" * 17)
        self.expect("reads like an ad", team__title="ACME: SIGN UP TODAY")

    def test_reveal(self):
        self.assertEqual(self.changed(words__reveal="Will you marry me?"), [])
        self.expect("words.reveal is 41 characters", words__reveal="W" * 41)
        self.expect("reads like an ad", words__reveal="Visit acme.com")
        (self.dir / "goal_sign.png").write_bytes(png(512, 256))
        self.assertEqual(self.changed(), [])
        (self.dir / "goal_sign.png").write_bytes(b"not a picture")
        self.expect("demo/cast/goal_sign.png", )

    def test_mode(self):
        for mode in cast_check.mode_ids():
            self.assertEqual(self.changed(mode=mode), [], mode)
        self.assertIn("show", cast_check.mode_ids())
        self.expect("mode must be one of carry, who_said_it", mode="tag")

    def test_show_words(self):
        words = {"qualified": "IN!", "eliminated": "OUT", "champion": "KING!", "go": "GO GO GO"}
        self.assertEqual(self.changed(mode="show", show={"words": words}), [])
        self.assertEqual(self.changed(mode="show", show={}), [])
        self.expect("show.words.go is 17 characters", show={"words": {"go": "G" * 17}})
        self.expect('show.words has no field "win"', show={"words": {"win": "YAY"}})
        self.expect('show has no field "rules"', show={"rules": 1})
        self.expect("show.words.champion reads like an ad", show={"words": {"champion": "Visit acme.com"}})
        self.expect("show.words.qualified must be text", show={"words": {"qualified": 3}})
        self.expect('"show.words" must be an object', show={"words": "GO"})
        self.expect('"show" must be an object', show="go")

    def test_rounds_pass(self):
        """show.rounds: every round takes title, rule and hint; r15, r17, r21 and r23 a label; r21 and r23 a model."""
        (self.dir / "round_r21.glb").write_bytes(glb())
        rounds = {"r15": {"title": "DON'T DROWN IN PRS", "rule": "TILES VANISH UNDER YOU · KEEP MOVING", "hint": "STAY ON THE MOVE", "label": ["#1234", "LGTM", "WIP"]},
                  "r21": {"title": "KEY ROTATION", "model": "round_r21.glb"}, "r23": {"title": "MERGE CONFLICTS", "label": "CONFLICT"},
                  "r17": {"title": "BREAK THROUGH", "label": "SHIP IT"}, "r24": {"title": "WHO HAS THE BUILD?"}, "r16": {"title": "SHIP IT"}}
        self.assertEqual(self.changed(mode="show", show={"rounds": rounds}), [])
        (self.dir / "round_r21.glb").unlink()
        self.assertEqual(self.changed(mode="show", show={"rounds": {}}), [])
        for round_id in cast_check.ROUND_NAMES:
            self.assertEqual(self.changed(mode="show", show={"rounds": {round_id: {"title": "A TITLE", "rule": "A RULE", "hint": "A HINT"}}}), [], round_id)
        self.assertEqual(self.changed(mode="show", show={"rounds": {"r15": {"title": "", "rule": ""}}}), [])  # empty = the level's own

    def test_items_pass(self):
        """show.items: texts (jokes about prices and subscribers are fine), clips and the call's footage under items/, tuning inside the template's ranges."""
        (self.dir / "items").mkdir()
        (self.dir / "items/smash.ogg").write_bytes(vorbis(1.0))
        (self.dir / "items/call.ogv").write_bytes(b"OggS" + bytes(24) + b"\x80theora" + bytes(64))
        items = [{"id": "smash", "name": "INVESTOR", "banner": "INVESTOR LOOKED AT THE BUILD", "line": "{user} SHOWED THE BUILD TO THE INVESTOR", "voice": "items/smash.ogg", "sfx": "items/smash.ogg",
                  "tuning": {"pin": 2.5}},
                 {"id": "boost", "banner": "NEW $200 SUBSCRIBER!"}, {"id": "call", "media": "items/call.ogv"}, {"id": "glitch", "off": True}]
        self.assertEqual(self.changed(mode="show", show={"items": items}), [])
        self.assertEqual(self.changed(mode="show", show={"items": []}), [])

    def test_item_lab_flag(self):
        self.assertEqual(self.changed(mode="show", show={"item_lab": True}), [])
        self.expect('"show.item_lab" must be true or false', mode="show", show={"item_lab": "yes"})

    def test_items_refusals(self):
        (self.dir / "items").mkdir()
        (self.dir / "items/long.ogg").write_bytes(vorbis(9.0))
        self.expect("is not an item of the show", mode="show", show={"items": [{"id": "rocket"}]})
        self.expect("is there twice", mode="show", show={"items": [{"id": "flip"}, {"id": "flip"}]})
        self.expect('has no field "colour"', mode="show", show={"items": [{"id": "flip", "colour": "#ff0000"}]})
        self.expect("show.items[0] (flip).banner is 31 characters; keep it to 30", mode="show", show={"items": [{"id": "flip", "banner": "B" * 31}]})
        self.expect("reads like an ad", mode="show", show={"items": [{"id": "flip", "line": "SIGN UP NOW"}]})
        self.expect("reads like an ad", mode="show", show={"items": [{"id": "flip", "banner": "www.acme.com"}]})
        self.expect("must be items/<file>", mode="show", show={"items": [{"id": "flip", "voice": "flip.ogg"}]})
        self.expect("plain file name", mode="show", show={"items": [{"id": "flip", "sfx": "items/../logo.png"}]})
        self.expect("is not in demo/cast", mode="show", show={"items": [{"id": "flip", "sfx": "items/none.ogg"}]})
        self.expect("keep a clip to 4 s", mode="show", show={"items": [{"id": "flip", "voice": "items/long.ogg"}]})
        self.expect("only the call takes footage", mode="show", show={"items": [{"id": "flip", "media": "items/x.ogv"}]})
        self.expect("has no key 'color'", mode="show", show={"items": [{"id": "flip", "tuning": {"color": 1}}]})
        self.expect("the game keeps it between", mode="show", show={"items": [{"id": "flip", "tuning": {"duration": 99}}]})
        self.expect("must be a number", mode="show", show={"items": [{"id": "flip", "tuning": {"duration": "long"}}]})
        self.expect("must be true or false", mode="show", show={"items": [{"id": "flip", "off": "yes"}]})

    def test_manager_passes(self):
        """show.manager (the manager experiment): its words, rules by id with their words and a duration, rules that are off."""
        manager = {"title": "NEW MANAGER", "line": "{manager} HAS OPINIONS", "you": "YOU HAVE OPINIONS NOW", "prompt": "GIVE AN ORDER", "waiting": "{manager} IS DRAFTING AN ORDER", "made": "ORDER FROM {manager}",
                   "rules": [{"id": "nojump", "name": "FEATURE FREEZE", "banner": "MANAGER SAYS: FEATURE FREEZE", "line": "{manager} SAYS SO", "tuning": {"duration": 10}}, {"id": "tiny", "off": True}]}
        self.assertEqual(self.changed(mode="show", show={"manager": manager}), [])
        self.assertEqual(self.changed(mode="show", show={"manager": {}}), [])
        self.assertEqual(self.changed(mode="show", show={"manager": {"off": True}}), [])

    def test_manager_refusals(self):
        self.expect('has no field "colour"', mode="show", show={"manager": {"colour": "red"}})
        self.expect("show.manager.title is 25 characters; keep it to 24", mode="show", show={"manager": {"title": "T" * 25}})
        self.expect("show.manager.off must be true or false", mode="show", show={"manager": {"off": "yes"}})
        self.expect("is not a rule of the manager", mode="show", show={"manager": {"rules": [{"id": "rocket"}]}})
        self.expect("is there twice", mode="show", show={"manager": {"rules": [{"id": "ice"}, {"id": "ice"}]}})
        self.expect("(ice).banner is 31 characters; keep it to 30", mode="show", show={"manager": {"rules": [{"id": "ice", "banner": "B" * 31}]}})
        self.expect("reads like an ad", mode="show", show={"manager": {"rules": [{"id": "ice", "line": "SIGN UP NOW"}]}})
        self.expect("has no key 'speed'", mode="show", show={"manager": {"rules": [{"id": "ice", "tuning": {"speed": 1}}]}})
        self.expect("the game keeps it between 3 and 30 seconds", mode="show", show={"manager": {"rules": [{"id": "ice", "tuning": {"duration": 99}}]}})
        self.expect("must be a number", mode="show", show={"manager": {"rules": [{"id": "ice", "tuning": {"duration": "long"}}]}})
        self.expect("must be true or false", mode="show", show={"manager": {"rules": [{"id": "ice", "off": "yes"}]}})

    def test_rounds_must_be_an_object(self):
        self.expect('"show.rounds" must be an object', show={"rounds": ["r15"]})
        self.expect("show.rounds.r15 must be an object", show={"rounds": {"r15": "WIP"}})

    def test_rounds_unknown_id(self):
        self.expect("'r99' is not a round of the show", show={"rounds": {"r99": {"title": "X"}}})
        self.expect("the rounds are r14 CIRCUIT BREAKER, r15 LAST TILE STANDING", show={"rounds": {"r20": {"title": "X"}}})
        self.expect("POSTER RUSH is one round, r17", show={"rounds": {"r20": {"title": "X"}}})
        self.expect("'15' is not a round", show={"rounds": {"15": {"title": "X"}}})

    def test_rounds_unaccepted_keys(self):
        self.expect("LAST TILE STANDING takes no model", show={"rounds": {"r15": {"model": "round_r15.glb"}}})
        self.expect("CROWN CLIMB takes no label; label is for r15, r17, r21 and r23 only", show={"rounds": {"r16": {"label": "X"}}})
        self.expect("POSTER RUSH takes no model", show={"rounds": {"r17": {"model": "round_r17.glb"}}})
        self.expect("SHOVE RING takes no label", show={"rounds": {"r22": {"label": "X"}}})
        self.expect('show.rounds.r21 has no field "color"', show={"rounds": {"r21": {"color": "#ff0000"}}})

    def test_rounds_text_lengths(self):
        self.assertEqual(self.changed(mode="show", show={"rounds": {"r14": {"title": "T" * 24, "rule": "R" * 48, "hint": "H" * 48}}}), [])
        self.expect("show.rounds.r14.title is 25 characters; keep it to 24", show={"rounds": {"r14": {"title": "T" * 25}}})
        self.expect("show.rounds.r14.rule is 49 characters; keep it to 48", show={"rounds": {"r14": {"rule": "R" * 49}}})
        self.expect("show.rounds.r14.hint is 49 characters; keep it to 48", show={"rounds": {"r14": {"hint": "H" * 49}}})
        self.expect("show.rounds.r14.title must be text", show={"rounds": {"r14": {"title": 3}}})
        self.expect("show.rounds.r14.rule reads like an ad", show={"rounds": {"r14": {"rule": "Visit acme.com"}}})
        self.expect("show.rounds.r14.title has letters the game's font cannot draw", show={"rounds": {"r14": {"title": "GO \U0001F680"}}})

    def test_rounds_labels(self):
        eight = [f"L{n}" for n in range(8)]
        self.assertEqual(self.changed(mode="show", show={"rounds": {"r15": {"label": eight}}}), [])
        self.assertEqual(self.changed(mode="show", show={"rounds": {"r15": {"label": "L" * 16}}}), [])
        self.expect("show.rounds.r15.label has 9 labels; keep it to 8", show={"rounds": {"r15": {"label": eight + ["L8"]}}})
        self.expect("show.rounds.r15.label[1] is 17 characters; keep it to 16", show={"rounds": {"r15": {"label": ["OK", "L" * 17]}}})
        self.expect("show.rounds.r23.label is 17 characters; keep it to 16", show={"rounds": {"r23": {"label": "L" * 17}}})
        self.expect("show.rounds.r15.label is an empty list", show={"rounds": {"r15": {"label": []}}})
        self.expect("show.rounds.r15.label[0] must not be empty", show={"rounds": {"r15": {"label": [" "]}}})
        self.expect("show.rounds.r17.label must not be empty", show={"rounds": {"r17": {"label": ""}}})
        self.expect("show.rounds.r15.label[1] must be text", show={"rounds": {"r15": {"label": ["OK", 7]}}})
        self.expect("show.rounds.r21.label must be text", show={"rounds": {"r21": {"label": {"a": "b"}}}})
        self.expect("show.rounds.r15.label[0] reads like an ad", show={"rounds": {"r15": {"label": ["acme.com"]}}})

    def test_rounds_model(self):
        rounds = {"r21": {"model": "round_r21.glb"}}
        self.expect("round_r21.glb is not in demo/cast/", mode="show", show={"rounds": rounds})
        (self.dir / "round_r21.glb").write_bytes(glb())
        self.assertEqual(self.changed(mode="show", show={"rounds": rounds}), [])
        self.expect("'key.glb'; the model of r21 is the file round_r21.glb", show={"rounds": {"r21": {"model": "key.glb"}}})
        self.expect("'round_r23.glb'; the model of r21", show={"rounds": {"r21": {"model": "round_r23.glb"}}})
        self.expect("show.rounds.r21.model must be the file name", show={"rounds": {"r21": {"model": 5}}})
        (self.dir / "round_r21.glb").write_bytes(b"not a model")
        self.expect("demo/cast/round_r21.glb is not a glTF binary", show={"rounds": rounds})
        (self.dir / "round_r21.glb").write_bytes(glb()[:-4])  # cut short: the header's length is wrong
        self.expect("demo/cast/round_r21.glb is not a glTF binary", show={"rounds": rounds})
        (self.dir / "round_r21.glb").write_bytes(glb() + bytes(cast_check.MAX_ROUND_MODEL_BYTES))
        self.expect("keep a round model under 5 MB", show={"rounds": rounds})
        (self.dir / "round_r23.glb").write_bytes(glb())  # the balls
        (self.dir / "round_r21.glb").write_bytes(glb())
        self.assertEqual(self.changed(mode="show", show={"rounds": {"r21": {"model": "round_r21.glb"}, "r23": {"model": "round_r23.glb"}}}), [])

    def test_round_model_files_are_named_and_used(self):
        (self.dir / "round_r21.glb").write_bytes(glb())
        self.expect('demo/cast/round_r21.glb is not used; name it in "show.rounds.r21.model"')
        (self.dir / "round_r21.glb").unlink()
        (self.dir / "round_r15.glb").write_bytes(glb())
        self.expect("demo/cast/round_r15.glb: the game never looks for this file; the round models are round_r21.glb, round_r23.glb")
        (self.dir / "round_r15.glb").unlink()
        (self.dir / "round_r21.gltf").write_bytes(glb())
        self.expect("demo/cast/round_r21.gltf: the game never looks for this file")

    def test_show_pictures(self):
        for name, size in {"banner_1.png": (2048, 512), "banner_2.png": (2048, 512), "billboard_1.png": (1536, 864), "billboard_2.png": (1536, 864)}.items():
            (self.dir / name).write_bytes(png(*size))
        self.assertEqual(self.changed(mode="show"), [])
        (self.dir / "banner_1.png").write_bytes(png(1000, 200))
        self.expect("demo/cast/banner_1.png is 1000x200 px; use at least 256 px")
        (self.dir / "banner_1.png").write_bytes(png(2048, 512))
        (self.dir / "billboard_1.png").write_bytes(b"\x00" * (cast_check.MAX_PICTURE_BYTES + 1))
        self.expect("keep it under 4 MB")
        (self.dir / "billboard_1.png").write_bytes(b"not a picture")
        self.expect("is not a PNG picture")
        (self.dir / "billboard_1.png").write_bytes(png(1536, 864))
        (self.dir / "banner_3.png").write_bytes(png(2048, 512))
        self.expect("demo/cast/banner_3.png: the game never looks for this file")
        (self.dir / "banner_3.png").unlink()
        (self.dir / "billboard_2.gif").write_bytes(png(1536, 864))
        self.expect("fixed file names")

    def test_crown_model(self):
        (self.dir / "crown.glb").write_bytes(glb())
        self.assertEqual(self.changed(mode="show"), [])
        (self.dir / "crown.glb").write_bytes(b"not a model")
        self.expect("demo/cast/crown.glb is not a glTF binary")
        (self.dir / "crown.glb").write_bytes(glb()[:-4])  # cut short: the header's length is wrong
        self.expect("is not a glTF binary")
        (self.dir / "crown.glb").write_bytes(b"glTF" + struct.pack("<II", 1, 20) + bytes(8))  # glTF 1.0
        self.expect("is not a glTF binary")
        (self.dir / "crown.glb").write_bytes(glb() + bytes(cast_check.MAX_CROWN_BYTES))
        self.expect("keep the crown model under 5 MB")
        (self.dir / "crown.glb").unlink()
        (self.dir / "crown.gltf").write_bytes(glb())
        self.expect("demo/cast/crown.gltf: the game never looks for this file")

    def test_hero_prop(self):
        """The hero prop: fixed file name, glTF binary, under 5 MB, and its tiers keep inside the stand (docs/hero-prop.md)."""
        (self.dir / "hero_prop.glb").write_bytes(glb_mesh(tiers()))
        self.assertEqual(self.changed(mode="show"), [])
        (self.dir / "hero_prop.glb").write_bytes(glb_mesh(tiers(scale=0.5)))  # any size is fitted: half-size, same shape
        self.assertEqual(self.changed(mode="show"), [])
        (self.dir / "hero_prop.glb").write_bytes(glb_mesh(tiers(wide=1.4)))  # a middle tier wider than the stand allows
        self.expect("demo/cast/hero_prop.glb leaves the stand")
        (self.dir / "hero_prop.glb").write_bytes(glb())  # a header and no mesh
        self.expect("demo/cast/hero_prop.glb has no meshes")
        (self.dir / "hero_prop.glb").write_bytes(b"not a model")
        self.expect("demo/cast/hero_prop.glb is not a glTF binary")
        (self.dir / "hero_prop.glb").write_bytes(glb_mesh(tiers()) + bytes(cast_check.MAX_HERO_PROP_BYTES))
        self.expect("keep the hero prop under 5 MB")
        (self.dir / "hero_prop.glb").unlink()
        (self.dir / "hero_prop.gltf").write_bytes(glb())
        self.expect("demo/cast/hero_prop.gltf: the game never looks for this file")

    def test_emote(self):
        self.assertEqual(self.changed(players__1__emote="dance"), [])
        self.expect("players[1].emote must be one of dance, sit, yes, no, point, think, cry", players__1__emote="flex")

    def test_looks(self):
        look = {"head": "head_bear", "hat": "hat_cap", "eyes": "eyes_big", "shirt": "shirt_stripes", "hand": "", "hair": ""}
        self.assertEqual(self.changed(players__1__look=look), [])
        self.expect('players[1].look has no slot "face"', players__1__look={"face": "eyes_big"})
        self.expect("players[1].look.hat must be one of hat_cap", players__1__look={"hat": "eyes_big"})
        self.expect("players[1].look.head must be one of head_frog", players__1__look={"head": ""})
        self.expect("players[1].look.hand must be one of", players__1__look={"hand": 3})
        self.expect("players[1].look must be an object", players__1__look="bear")

    def test_people_heads_warn_and_map_to_the_seat_animal(self):
        cast = json.loads(json.dumps(GOOD_V2))
        cast["players"][1]["look"] = {"head": "head_human", "hat": "hat_cap"}
        cast["players"][0]["look"] = {"head": "head_potato"}
        path = self.dir / "cast.json"
        path.write_text(json.dumps(cast), encoding="utf-8")
        warnings = []
        self.assertEqual(cast_check.check_cast(path, warnings=warnings), [])
        self.assertEqual(len(warnings), 2, warnings)
        self.assertIn(f"wears {cast_check.seat_animal(0)} for seat 0", warnings[0])
        self.assertIn(f"wears {cast_check.seat_animal(1)} for seat 1", warnings[1])
        self.assertNotEqual(cast_check.seat_animal(0), cast_check.seat_animal(1))
        self.assertNotIn("head_potato", cast_check.catalog_items()["head"])
        self.assertFalse(any(cast_check.is_people_head(h, cast_check.catalog_people()) for h in cast_check.catalog_items()["head"]))
        clean = []
        cast["players"][0]["look"] = {"head": "head_bear"}
        cast["players"][1]["look"] = {"head": "head_cat"}
        path.write_text(json.dumps(cast), encoding="utf-8")
        cast_check.check_cast(path, warnings=clean)
        self.assertEqual(clean, [])

    def test_voice(self):
        self.expect("fixed file names", players__0__voice="voice/member_2.ogg")
        (self.dir / "voice/member_1.ogg").write_bytes(vorbis(6.0))
        self.expect("6.0 s long", players__0__voice="voice/member_1.ogg")
        (self.dir / "voice/member_1.ogg").write_bytes(b"ID3" + bytes(64))
        self.expect("not an Ogg Vorbis clip", players__0__voice="voice/member_1.ogg")

    def test_video(self):
        self.expect("fixed file names", video__intro="intro.ogv")
        (self.dir / "video/intro.ogv").write_bytes(b"OggS" + bytes(64))
        self.expect("not an Ogg Theora video", video__intro="video/intro.ogv")

    def test_path_escape(self):
        self.expect("plain file name", brand__logo="../logo.png")

    def test_voice_must_be_mono(self):
        (self.dir / "voice/member_1.ogg").write_bytes(vorbis(1.0, channels=2))
        self.expect("2 channels; export it as mono", players__0__voice="voice/member_1.ogg")

    def test_voice_variants(self):
        (self.dir / "voice/member_1_2.ogg").write_bytes(vorbis(1.0))
        self.assertEqual(self.problems(GOOD_V2), [])
        (self.dir / "voice/member_1_4.ogg").write_bytes(vorbis(1.0))
        self.expect("voice/member_1_4.ogg: the game never looks for this file")

    def test_announcer(self):
        (self.dir / "announcer").mkdir()
        for name in ("start_1.ogg", "near_drop_4.ogg", "zap_2.ogg", "perfect_1.ogg"):
            (self.dir / "announcer" / name).write_bytes(vorbis(2.0))
        self.assertEqual(self.problems(GOOD_V2), [])
        (self.dir / "announcer/start_5.ogg").write_bytes(vorbis(1.0))
        self.expect("announcer/start_5.ogg: the game never looks for this file")
        (self.dir / "announcer/start_5.ogg").unlink()
        (self.dir / "announcer/goal_1.ogg").write_bytes(vorbis(4.5))
        self.expect("goal_1.ogg is 4.5 s long")
        (self.dir / "announcer/goal_1.ogg").write_bytes(vorbis(1.0) + bytes(310 * 1024))
        self.expect("keep a clip under 300 KB")

    def test_team_wall(self):
        (self.dir / "team").mkdir()
        (self.dir / "team/member_1.png").write_bytes(png(512, 512))
        wall = [{"name": "Maja", "picture": "team/member_1.png"}, {"name": "Theo"}]
        self.assertEqual(self.changed(team_wall=wall), [])
        self.expect("team_wall[1].name is 17 characters", team_wall=[wall[0], {"name": "X" * 17}])
        self.expect("at most 10", team_wall=[{"name": "A"}] * 11)
        self.expect("fixed file names", team_wall=[{"name": "Maja", "picture": "team/member_2.png"}])
        self.expect("team/member_1.png is not on the team wall", team_wall=[{"name": "Maja"}])
        (self.dir / "team/member_1.png").write_bytes(png(512, 400))
        self.expect("use a square photo", team_wall=wall)

    def test_credit_link(self):
        self.assertEqual(self.changed(team__credit_link="https://acme.example/team"), [])
        self.expect("team.credit_link must be one https:// link", team__credit_link="http://acme.example")
        self.expect("team.credit_link must be one https:// link", team__credit_link="https://acme example")
        self.expect("team.credit_link must be one https:// link", team__credit_link="https://" + "a" * 100 + ".example")

    def test_no_ads_in_visible_text(self):
        self.expect("reads like an ad", team__tagline="Try it free at acme.io")
        self.expect("reads like an ad", posters__0__caption="ONLY $9 A MONTH")
        self.expect("reads like an ad", obstacles__0__label="SIGN UP TODAY")
        self.expect("reads like an ad", players__0__catchphrase="Book a demo!")
        self.expect("reads like an ad", eggs=["Use code ACME for 20% off"])
        self.assertEqual(self.changed(team__tagline="Four couriers · one city · don't drop it"), [])


class PreparedTest(unittest.TestCase):
    """demo/cast/prepared/ (tools/cast_prep.py): the manifest, the sources' hashes and the prepared pictures."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.logo = png(512, 512)
        (self.dir / "logo.png").write_bytes(self.logo)
        (self.dir / "balloon.png").write_bytes(png(300, 300))
        (self.dir / "cast.json").write_text(json.dumps({
            "format": "team-cast-v2", "team": {"name": "Sommer Spil"}, "brand": {"logo": "logo.png"}, "balloon": {"picture": "balloon.png"},
            "players": [{"name": "Ida", "color": "#aa22cc"}]}), encoding="utf-8")
        self.prepared = self.dir / "prepared"
        self.write(self.manifest())

    def tearDown(self):
        shutil.rmtree(self.dir)

    def manifest(self, **files):
        entries = {"logo.png": {"sha256": hashlib.sha256(self.logo).hexdigest(), "result": "keyed", "background": "#ffffff", "size": [400, 380]},
                   "balloon.png": {"sha256": hashlib.sha256((self.dir / "balloon.png").read_bytes()).hexdigest(), "result": "busy"}}
        entries.update(files)
        return {"format": "cast-prep-v1", "files": entries}

    def write(self, manifest, picture=None):
        self.prepared.mkdir(exist_ok=True)
        (self.prepared / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        (self.prepared / "logo.png").write_bytes(picture if picture is not None else png(400, 380))

    def problems(self):
        return cast_check.check_cast(self.dir / "cast.json")

    def expect(self, needle):
        problems = self.problems()
        self.assertTrue(any(needle in p for p in problems), problems)

    def test_no_prepared_folder_passes(self):
        shutil.rmtree(self.prepared)
        self.assertEqual(self.problems(), [])

    def test_matching_manifest_and_picture_pass(self):
        self.assertEqual(self.problems(), [])

    def test_import_sidecars_are_allowed(self):
        (self.prepared / "logo.png.import").write_text("[remap]\n")
        self.assertEqual(self.problems(), [])

    def test_changed_picture_is_stale(self):
        (self.dir / "logo.png").write_bytes(png(512, 513))
        self.expect("logo.png changed since tools/cast_prep.py ran; run it again (ship.py does)")

    def test_removed_picture_is_stale(self):
        (self.dir / "balloon.png").unlink()
        self.expect("balloon.png is not in demo/cast/ any more")

    def test_missing_manifest(self):
        (self.prepared / "manifest.json").unlink()
        self.expect("manifest.json is missing")

    def test_bad_manifest_format(self):
        self.write({"format": "other", "files": {}})
        self.expect('must be {"format": "cast-prep-v1"')
        (self.prepared / "manifest.json").write_text("{nope")
        self.expect("not valid JSON")

    def test_bad_entries(self):
        for entry, needle in [({"sha256": "ab", "result": "keyed"}, "sha256 must be 64 hex"),
                              ({"sha256": "0" * 64, "result": "maybe"}, "result must be one of"),
                              ({"sha256": "0" * 64, "result": "keyed"}, "needs \"background\""),
                              ({"sha256": "0" * 64, "result": "busy", "size": [1, 1]}, "has a background or size"),
                              ({"sha256": "0" * 64, "result": "busy", "other": 1}, "must be an object with")]:
            self.write(self.manifest(**{"balloon.png": entry}))
            self.expect(needle)

    def test_keyed_picture_must_exist_and_be_a_valid_png(self):
        (self.prepared / "logo.png").unlink()
        self.expect("logo.png is missing")
        (self.prepared / "logo.png").write_bytes(b"\x89PNG\r\n\x1a\nnot a png")
        self.expect("not a valid PNG")
        (self.prepared / "logo.png").write_bytes(self.logo[:-4])
        self.expect("not a valid PNG")
        (self.prepared / "logo.png").write_bytes(png(300, 300))
        self.expect("300x300 px but the manifest says 400x380")

    def test_prepared_picture_over_4_mb(self):
        (self.prepared / "logo.png").write_bytes(png(400, 380) + bytes(cast_check.MAX_PICTURE_BYTES))
        self.expect("keep it under 4 MB")

    def test_unlisted_files_are_reported(self):
        (self.prepared / "extra.png").write_bytes(png(10, 10))
        self.expect("extra.png is not a prepared picture the manifest names")
        (self.prepared / "extra.png").unlink()
        (self.prepared / "balloon.png").write_bytes(png(10, 10))  # the manifest says busy: no picture belongs here
        self.expect("balloon.png is not a prepared picture the manifest names")

    def test_two_sources_one_prepared_name(self):
        (self.dir / "logo.jpg").write_bytes(b"\xff\xd8\xff")
        self.write(self.manifest(**{"logo.jpg": {"sha256": hashlib.sha256(b"\xff\xd8\xff").hexdigest(), "result": "keyed", "background": "#000000", "size": [1, 1]}}))
        self.expect("would both be demo/cast/prepared/logo.png")


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        for name, text in {"demo/run.gd": "a", "demo/cast/cast.json": "{}", "tools/x.py": "b", "demo/.gitignore": ".godot/\n*.import\n",
                           ".gitignore": "demo/courses/\n"}.items():
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            (self.root / name).write_text(text)
        self.lock = self.root / "tools/locked_files.json"
        cast_check.lock(self.root, self.lock)

    def tearDown(self):
        shutil.rmtree(self.root)

    def check(self):
        return cast_check.check_guard(self.root, self.lock)

    def test_unchanged_template_passes(self):
        self.assertEqual(self.check(), [])

    def test_cast_edits_are_free(self):
        (self.root / "demo/cast/cast.json").write_text('{"format": "team-cast-v1"}')
        (self.root / "demo/cast/logo.png").write_bytes(b"png")
        self.assertEqual(self.check(), [])

    def test_changed_file_fails(self):
        (self.root / "demo/run.gd").write_text("changed")
        self.assertEqual(self.check(), ["locked file changed: demo/run.gd"])

    def test_added_file_fails(self):
        (self.root / "demo/new_mechanic.gd").write_text("x")
        self.assertEqual(self.check(), ["file added outside demo/cast/: demo/new_mechanic.gd"])

    def test_removed_file_fails(self):
        (self.root / "tools/x.py").unlink()
        self.assertEqual(self.check(), ["locked file removed: tools/x.py"])

    def test_ignored_and_engine_files_are_skipped(self):
        for name in ("demo/.godot/cache.bin", "demo/icon.png.import", "demo/courses/levels.json", "build/game.zip"):
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            (self.root / name).write_text("x")
        self.assertEqual(self.check(), [])

    def test_engine_version_stamp_is_ignored(self):
        project = self.root / "demo/project.godot"
        project.write_text('[summer]\n\nlocal_play/x=1\nversion="0.7.2"\n')
        cast_check.lock(self.root, self.lock)
        project.write_text('[summer]\n\nlocal_play/x=1\nversion="0.7.3"\n')
        self.assertEqual(self.check(), [])
        project.write_text('[summer]\n\nlocal_play/x=2\nversion="0.7.3"\n')
        self.assertEqual(self.check(), ["locked file changed: demo/project.godot"])

    def test_repository_matches_its_lock(self):
        self.assertEqual(cast_check.check_guard(), [])


if __name__ == "__main__":
    unittest.main()
