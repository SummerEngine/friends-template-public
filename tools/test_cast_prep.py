#!/usr/bin/env python3
"""Tests of tools/cast_prep.py and tools/cast_prep.gd: the cast's logo pictures lose their plain background.

The pictures are made in pure Python (zlib + struct) and the output is decoded the same way; the engine runs headless through
cast_prep.prepare (so $SUMMER / $SUMMER_RUN apply). Without an engine the engine cases are skipped with a message.

    FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 -m unittest discover -s tools -p 'test_cast_prep.py'
"""
import hashlib
import json
import random
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path

import cast_check
import cast_prep

ENGINE = Path(cast_prep.engine_path())
NEEDS_ENGINE = unittest.skipUnless(ENGINE.is_file(), f"no Summer engine at {ENGINE}; set $SUMMER to run the cast prep engine tests")
SIZE = 160
CENTRE = (80, 80)
ORANGE = (230, 90, 40)
INK = (30, 30, 40)
WHITE = (255, 255, 255)


# ------------------------------------------------------------------ pure Python PNG
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def write_png(path, width, height, pixel, alpha=True):
    """pixel(x, y) -> (r, g, b) or (r, g, b, a)."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            value = pixel(x, y)
            raw.extend(value if alpha else value[:3])
    header = struct.pack(">IIBBBBB", width, height, 8, 6 if alpha else 2, 0, 0, 0)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))


def read_png(path):
    """(width, height, rows of RGBA bytes) of an 8-bit RGB or RGBA PNG, every filter type."""
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
    assert depth == 8 and interlace == 0 and color in (2, 6), "unsupported PNG"
    step = 4 if color == 6 else 3
    raw, stride, rows, previous, pos = zlib.decompress(idat), width * step, [], bytearray(width * step), 0
    for _ in range(height):
        kind, line = raw[pos], bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - step] if i >= step else 0
            b = previous[i]
            c = previous[i - step] if i >= step else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        previous = line
        if step == 3:
            line = bytearray(value for x in range(width) for value in (*line[x * 3:x * 3 + 3], 255))
        rows.append(line)
    return width, height, rows


def at(image, x, y):
    return tuple(image[2][y][x * 4:x * 4 + 4])


# ------------------------------------------------------------------ fixtures
def disc(background, jitter=0, seed=1, ring=(48, 56), hole=0):
    """A coloured disc with a dark ring on `background`; `jitter` adds +-jitter to every background channel (the noise of a JPEG);
    `hole` makes a background-coloured hole in the middle (an enclosed region the fill cannot reach)."""
    noise = random.Random(seed)

    def pixel(x, y):
        distance = ((x - CENTRE[0]) ** 2 + (y - CENTRE[1]) ** 2) ** 0.5
        if hole and distance < hole:
            return (*background, 255)
        if distance <= ring[0]:
            return (*ORANGE, 255)
        if distance <= ring[1]:
            return (*INK, 255)
        return (*(min(255, max(0, c + noise.randint(-jitter, jitter))) for c in background), 255)
    return pixel


def transparent_logo(x, y):
    distance = ((x - CENTRE[0]) ** 2 + (y - CENTRE[1]) ** 2) ** 0.5
    return (*ORANGE, 255) if distance <= 56 else (255, 255, 255, 0)


def busy_picture(x, y):
    noise = (x * 7 + y * 13) % 17
    return (x * 255 // (SIZE - 1), y * 255 // (SIZE - 1), min(255, 255 - x * 255 // (SIZE - 1) + noise), 255)


def speck(x, y):
    return (*INK, 255) if 78 <= x <= 80 and 78 <= y <= 80 else (*WHITE, 255)


FIXTURES = {
    "white.png": disc(WHITE),
    "tinted.png": disc((120, 180, 200), jitter=3),
    "clear.png": transparent_logo,
    "busy.png": busy_picture,
    "hole.png": disc(WHITE, ring=(56, 56), hole=30),
    "speck.png": speck,
}


def make_cast(folder, names):
    folder.mkdir(parents=True, exist_ok=True)
    for name in names:
        write_png(folder / name, SIZE, SIZE, FIXTURES[name])
    (folder / "cast.json").write_text(json.dumps({"format": "team-cast-v2", "team": {"name": "Test"}, "players": [{"name": "Ida", "color": "#aa22cc"}]}))
    return folder


def manifest_of(folder):
    return json.loads((folder / "prepared" / "manifest.json").read_text())


def make_jpeg(source, target):
    """A quality-80 JPEG of a PNG with whatever tool the machine has; False when there is none."""
    for command in (["magick", str(source), "-quality", "80", str(target)],
                    ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "80", str(source), "--out", str(target)]):
        try:
            if subprocess.run(command, capture_output=True, timeout=60).returncode == 0 and target.is_file():
                return True
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    return False


# ------------------------------------------------------------------ tests
@NEEDS_ENGINE
class KeyOutTest(unittest.TestCase):
    """One engine run over every fixture; each test reads its own result."""

    @classmethod
    def setUpClass(cls):
        cls.dir = Path(tempfile.mkdtemp())
        cls.cast = make_cast(cls.dir / "cast", FIXTURES)
        cls.counts = cast_prep.prepare(cls.cast, also=sorted(FIXTURES))
        cls.manifest = manifest_of(cls.cast)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir)

    def prepared(self, name):
        return read_png(self.cast / "prepared" / name)

    def test_counts_and_manifest_format(self):
        self.assertEqual(self.counts, {"keyed": 3, "skipped": 3})
        self.assertEqual(self.manifest["format"], "cast-prep-v1")
        self.assertEqual({name: entry["result"] for name, entry in self.manifest["files"].items()},
                         {"white.png": "keyed", "tinted.png": "keyed", "hole.png": "keyed", "speck.png": "empty", "clear.png": "transparent", "busy.png": "busy"})
        text = (self.cast / "prepared" / "manifest.json").read_text()
        self.assertEqual(text, json.dumps(self.manifest, indent=2, sort_keys=True) + "\n")

    def test_only_keyed_pictures_get_a_file(self):
        names = sorted(path.name for path in (self.cast / "prepared").iterdir())
        self.assertEqual(names, ["hole.png", "manifest.json", "tinted.png", "white.png"])

    def test_manifest_entries(self):
        for name, entry in self.manifest["files"].items():
            self.assertEqual(entry["sha256"], hashlib.sha256((self.cast / name).read_bytes()).hexdigest(), name)
            if entry["result"] == "keyed":
                width, height, _ = self.prepared(name)
                self.assertEqual(entry["size"], [width, height])
                self.assertRegex(entry["background"], r"^#[0-9a-f]{6}$")
            else:
                self.assertEqual(set(entry), {"sha256", "result"}, name)

    def test_white_background_logo(self):
        image = self.prepared("white.png")
        width, height, rows = image
        self.assertEqual(self.manifest["files"]["white.png"]["background"], "#ffffff")
        self.assertLess(width * height, 0.97 * SIZE * SIZE)  # trimmed to the disc and its margin
        self.assertGreaterEqual(width, 112)
        for corner in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
            self.assertEqual(at(image, *corner)[3], 0, corner)
        self.assertEqual(at(image, width // 2, height // 2), (*ORANGE, 255))
        # The ring is untouched inside and the edge is a thin soft band: semi-transparent pixels are a small share of the disc's outline.
        semi = sum(1 for row in rows for x in range(width) if 0 < row[x * 4 + 3] < 255)
        opaque = sum(1 for row in rows for x in range(width) if row[x * 4 + 3] == 255)
        self.assertGreater(opaque, 0.7 * 3.14159 * 56 * 56)
        self.assertLess(semi, 2 * 3.14159 * 2 * 56 * 3)  # under about three pixels of band around the 56 px outline
        # The ring colour reaches the edge: the first visible pixel of the middle row is dark, not a light halo.
        row = rows[height // 2]
        left = next(x for x in range(width) if row[x * 4 + 3] > 0)
        self.assertLess(sum(row[left * 4:left * 4 + 3]) / 3, 120)

    def test_tinted_background_with_jpeg_like_noise(self):
        image = self.prepared("tinted.png")
        width, height, rows = image
        background = self.manifest["files"]["tinted.png"]["background"]
        self.assertTrue(all(abs(int(background[i:i + 2], 16) - target) <= 3 for i, target in zip((1, 3, 5), (120, 180, 200))), background)
        for corner in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
            self.assertEqual(at(image, *corner)[3], 0, corner)
        self.assertEqual(at(image, width // 2, height // 2), (*ORANGE, 255))
        # No speckle of the noisy background is left opaque outside the ring.
        stray = sum(1 for y, row in enumerate(rows) for x in range(width)
                    if row[x * 4 + 3] > 8 and ((x - width / 2) ** 2 + (y - height / 2) ** 2) ** 0.5 > 60)
        self.assertEqual(stray, 0)

    def test_transparent_picture_is_skipped(self):
        self.assertEqual(self.manifest["files"]["clear.png"]["result"], "transparent")
        self.assertFalse((self.cast / "prepared" / "clear.png").exists())

    def test_busy_picture_is_left_alone(self):
        self.assertEqual(self.manifest["files"]["busy.png"]["result"], "busy")
        self.assertFalse((self.cast / "prepared" / "busy.png").exists())

    def test_enclosed_background_coloured_hole_stays_opaque(self):
        image = self.prepared("hole.png")
        width, height, _ = image
        self.assertEqual(at(image, 0, 0)[3], 0)
        self.assertEqual(at(image, width // 2, height // 2), (*WHITE, 255))
        self.assertEqual(at(image, width // 2 + 10, height // 2 - 10), (*WHITE, 255))

    def test_nearly_empty_picture_is_skipped(self):
        self.assertEqual(self.manifest["files"]["speck.png"]["result"], "empty")
        self.assertFalse((self.cast / "prepared" / "speck.png").exists())

    def test_originals_are_untouched(self):
        for name in FIXTURES:
            self.assertEqual((self.cast / name).read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(read_png(self.cast / name)[:2], (SIZE, SIZE))

    def test_cast_check_accepts_the_output_and_sees_a_changed_source(self):
        cast = self.dir / "checked"
        shutil.copytree(self.cast, cast)
        (cast / "cast.json").write_text(json.dumps({"format": "team-cast-v2", "team": {"name": "Test"}, "brand": {"logo": "white.png"},
                                                    "players": [{"name": "Ida", "color": "#aa22cc"}]}))
        about_prep = lambda: [p for p in cast_check.check_cast(cast / "cast.json") if "prepared" in p or "cast_prep" in p]
        self.assertEqual(about_prep(), [])
        write_png(cast / "white.png", SIZE, SIZE, disc(WHITE, ring=(40, 50)))
        self.assertTrue(any("white.png changed since tools/cast_prep.py ran" in p for p in about_prep()), about_prep())


@NEEDS_ENGINE
class RunTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.dir)

    def snapshot(self, cast):
        return {path.name: path.read_bytes() for path in sorted((cast / "prepared").iterdir())}

    def test_same_input_same_bytes_and_rerun_overwrites(self):
        cast = make_cast(self.dir / "cast", ["white.png", "tinted.png"])
        cast_prep.prepare(cast, also=["white.png", "tinted.png"])
        first = self.snapshot(cast)
        (cast / "prepared" / "white.png").write_bytes(b"tampered")
        cast_prep.prepare(cast, also=["white.png", "tinted.png"])
        self.assertEqual(self.snapshot(cast), first)

    def test_prepared_files_of_removed_pictures_are_deleted_and_an_empty_folder_goes(self):
        cast = make_cast(self.dir / "cast", ["white.png", "tinted.png"])
        cast_prep.prepare(cast, also=["white.png", "tinted.png"])
        (cast / "tinted.png").unlink()
        (cast / "prepared" / "stray.png").write_bytes(b"x")
        (cast / "prepared" / "white.png.import").write_text("[remap]\n")
        (cast / "prepared" / "tinted.png.import").write_text("[remap]\n")
        counts = cast_prep.prepare(cast, also=["white.png", "tinted.png"])
        self.assertEqual(counts, {"keyed": 1, "skipped": 0})
        self.assertEqual(sorted(self.snapshot(cast)), ["manifest.json", "white.png", "white.png.import"])
        self.assertEqual(list(manifest_of(cast)["files"]), ["white.png"])
        (cast / "white.png").unlink()
        self.assertEqual(cast_prep.prepare(cast, also=["white.png"]), {"keyed": 0, "skipped": 0})
        self.assertFalse((cast / "prepared").exists())

    def test_a_picture_that_stops_qualifying_loses_its_prepared_file(self):
        cast = make_cast(self.dir / "cast", ["white.png"])
        cast_prep.prepare(cast, also=["white.png"])
        self.assertTrue((cast / "prepared" / "white.png").is_file())
        write_png(cast / "white.png", SIZE, SIZE, busy_picture)
        cast_prep.prepare(cast, also=["white.png"])
        self.assertEqual(sorted(self.snapshot(cast)), ["manifest.json"])
        self.assertEqual(manifest_of(cast)["files"]["white.png"]["result"], "busy")

    def test_cast_json_picks_the_sources(self):
        cast = make_cast(self.dir / "cast", ["white.png", "tinted.png", "hole.png", "clear.png", "speck.png"])
        (cast / "goal_sign.png").write_bytes((cast / "tinted.png").read_bytes())
        (cast / "cast.json").write_text(json.dumps({"format": "team-cast-v2", "team": {"name": "Test"}, "brand": {"logo": "white.png"},
                                                    "balloon": {"picture": "hole.png"}, "players": [{"name": "Ida", "color": "#aa22cc"}]}))
        cast_prep.prepare(cast)
        self.assertEqual(sorted(manifest_of(cast)["files"]), ["goal_sign.png", "hole.png", "white.png"])  # not tinted, clear or speck: nothing names them

    def test_unreadable_picture_fails_with_its_name(self):
        cast = make_cast(self.dir / "cast", ["white.png"])
        (cast / "white.png").write_bytes(b"this is not a picture")
        with self.assertRaisesRegex(cast_prep.CastPrepError, "white.png"):
            cast_prep.prepare(cast, also=["white.png"])

    def test_jpeg_with_real_noise(self):
        cast = make_cast(self.dir / "cast", ["white.png", "tinted.png"])
        for name in ("white", "tinted"):
            if not make_jpeg(cast / f"{name}.png", cast / f"{name}.jpg"):
                self.skipTest("neither magick nor sips can make a JPEG here")
            (cast / f"{name}.png").unlink()
        counts = cast_prep.prepare(cast, also=["white.jpg", "tinted.jpg"])
        self.assertEqual(counts, {"keyed": 2, "skipped": 0})
        for name in ("white", "tinted"):
            image = read_png(cast / "prepared" / f"{name}.png")
            width, height, _ = image
            self.assertEqual(at(image, 0, 0)[3], 0, name)
            self.assertEqual(at(image, width // 2, height // 2)[3], 255, name)
            self.assertEqual(manifest_of(cast)["files"][f"{name}.jpg"]["size"], [width, height])


class PythonSideTest(unittest.TestCase):
    def test_png_roundtrip_of_the_helpers(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "p.png"
            write_png(path, 3, 2, lambda x, y: (x * 80, y * 100, 7, 200 + x))
            width, height, rows = read_png(path)
            self.assertEqual((width, height), (3, 2))
            self.assertEqual(at((width, height, rows), 2, 1), (160, 100, 7, 202))
            self.assertTrue(cast_check.png_ok(path.read_bytes()))

    def test_missing_cast_folder_is_an_error(self):
        with self.assertRaisesRegex(cast_prep.CastPrepError, "not a folder"):
            cast_prep.prepare(Path(tempfile.gettempdir()) / "no-such-cast-folder-for-prep")

    def test_missing_engine_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder, self.assertRaisesRegex(cast_prep.CastPrepError, "cannot start the engine"):
            cast_prep.prepare(folder, engine="/no/such/engine")


if __name__ == "__main__":
    unittest.main()
