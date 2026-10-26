#!/usr/bin/env python3
"""Draws the placeholder pictures and sounds of the sample team cast `samples/acme/` (docs/slots.md). Pure Python, no paid API.

    python3 tools/make_sample_cast.py              # writes samples/acme/*.png, voice/, announcer/ and team/
    python3 tools/make_sample_cast.py --out DIR    # somewhere else

Every picture is flat comic art built from polygons and circles: thick ink outlines, bold flat colours, light halftone dots, no
lettering (the game letters the labels and captions). "Acme" is an invented sample team; the badge and icons are drawn here.
The team wall stand-ins are simple objects on colour (no faces: in a real game each photo is that person's own, opt-in).
The voice and announcer clips are short synthetic tones made here as mono PCM and encoded with oggenc (Ogg Vorbis, mono); they are
skipped when oggenc is missing.
To try the sample: cp -R samples/acme/. demo/cast/   (back to the neutral cast: git checkout -- demo/cast && git clean -fdq demo/cast)
"""
import argparse
import math
import shutil
import struct
import tempfile
import wave
import subprocess
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INK = (27, 29, 58, 255)
PAPER = (246, 236, 210, 255)
WHITE = (255, 250, 238, 255)
ORANGE = (255, 106, 19, 255)
ORANGE_DARK = (214, 78, 8, 255)
BLUE = (58, 91, 217, 255)
BLUE_LIGHT = (153, 189, 255, 255)
YELLOW = (255, 210, 63, 255)
GREEN = (46, 194, 126, 255)
RED = (230, 72, 52, 255)
GREY = (150, 156, 180, 255)
CLEAR = (0, 0, 0, 0)
SUPERSAMPLE = 2


class Canvas:
    """RGBA canvas drawn at SUPERSAMPLE x the size and averaged down when saved (smooth edges)."""

    def __init__(self, width, height, background=CLEAR):
        self.width, self.height = width, height
        self.w, self.h = width * SUPERSAMPLE, height * SUPERSAMPLE
        self.px = bytearray(bytes(background) * (self.w * self.h))

    def poly(self, points, color):
        """Fills a polygon (even-odd), points in output pixels."""
        pts = [(x * SUPERSAMPLE, y * SUPERSAMPLE) for x, y in points]
        ys = [p[1] for p in pts]
        fill = bytes(color)
        for y in range(max(0, int(min(ys))), min(self.h - 1, int(max(ys)) + 1) + 1):
            sy = y + 0.5
            xs = []
            for i in range(len(pts)):
                (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
                if (ay <= sy < by) or (by <= sy < ay):
                    xs.append(ax + (sy - ay) * (bx - ax) / (by - ay))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                xa, xb = max(0, math.ceil(xs[k] - 0.5)), min(self.w, math.ceil(xs[k + 1] - 0.5))
                if xb > xa:
                    start = (y * self.w + xa) * 4
                    self.px[start:start + (xb - xa) * 4] = fill * (xb - xa)

    def circle(self, cx, cy, r, color, steps=72):
        self.poly([(cx + r * math.cos(a * math.tau / steps), cy + r * math.sin(a * math.tau / steps)) for a in range(steps)], color)

    def inked(self, points, color, width=10):
        """A polygon with a thick ink outline."""
        self.stroke(points, INK, width, closed=True)
        self.poly(points, color)

    def disc(self, cx, cy, r, color, width=10):
        self.circle(cx, cy, r + width / 2, INK)
        self.circle(cx, cy, r - width / 2, color)

    def stroke(self, points, color, width, closed=False):
        count = len(points) if closed else len(points) - 1
        for i in range(count):
            (ax, ay), (bx, by) = points[i], points[(i + 1) % len(points)]
            length = math.hypot(bx - ax, by - ay) or 1.0
            nx, ny = -(by - ay) / length * width / 2, (bx - ax) / length * width / 2
            self.poly([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], color)
        for x, y in points:
            self.circle(x, y, width / 2, color, 24)

    def halftone(self, rect, color, cell=14, grow=(0.08, 0.32)):
        """Light halftone dots over `rect` (x, y, w, h), bigger towards the bottom."""
        x0, y0, w, h = rect
        for row in range(int(h // cell) + 1):
            radius = cell * (grow[0] + (grow[1] - grow[0]) * row / max(1, h // cell))
            for col in range(int(w // cell) + 1):
                cx = x0 + col * cell + (cell / 2 if row % 2 else 0)
                if cx < x0 + w:
                    self.circle(cx, y0 + row * cell, radius, color, 12)

    def save(self, path):
        out = bytearray()
        for y in range(self.height):
            out.append(0)
            for x in range(self.width):
                r = g = b = a = 0
                for dy in range(SUPERSAMPLE):
                    base = ((y * SUPERSAMPLE + dy) * self.w + x * SUPERSAMPLE) * 4
                    for dx in range(SUPERSAMPLE):
                        i = base + dx * 4
                        alpha = self.px[i + 3]
                        r += self.px[i] * alpha
                        g += self.px[i + 1] * alpha
                        b += self.px[i + 2] * alpha
                        a += alpha
                out += bytes((r // a, g // a, b // a, a // SUPERSAMPLE ** 2) if a else (0, 0, 0, 0))
        chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(out), 9)) + chunk(b"IEND", b"")
        Path(path).write_bytes(png)


# ------------------------------------------------------------------ pieces
def badge(c, cx, cy, r):
    """The Acme badge: an orange disc in an ink ring with a bold paper 'A' mark and a yellow spark."""
    c.disc(cx, cy, r, ORANGE, r * 0.1)
    c.circle(cx, cy, r * 0.8, ORANGE_DARK)
    c.circle(cx, cy, r * 0.76, ORANGE)
    s = r * 0.62
    mark = [(-0.5, 0.55), (-0.13, -0.62), (0.13, -0.62), (0.5, 0.55), (0.22, 0.55), (0.14, 0.3), (-0.14, 0.3), (-0.22, 0.55)]
    mark = [(cx + x * s, cy + y * s) for x, y in mark]
    c.inked(mark, PAPER, r * 0.08)
    c.inked([(cx - 0.075 * s, cy + 0.1 * s), (cx, cy - 0.2 * s), (cx + 0.075 * s, cy + 0.1 * s)], ORANGE, r * 0.05)
    star(c, cx + r * 0.62, cy - r * 0.62, r * 0.22, YELLOW)


def star(c, cx, cy, r, color, points=4):
    pts = []
    for i in range(points * 2):
        radius = r if i % 2 == 0 else r * 0.38
        angle = i * math.pi / points - math.pi / 2
        pts.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    c.inked(pts, color, r * 0.18)


def gear(c, cx, cy, r, color):
    pts = []
    for i in range(48):
        angle = i * math.tau / 48
        radius = r if (i // 3) % 2 == 0 else r * 0.78
        pts.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    c.inked(pts, color, r * 0.1)
    c.disc(cx, cy, r * 0.32, PAPER, r * 0.1)


def bolt(c, cx, cy, s, color):
    pts = [(0.1, -0.6), (-0.35, 0.08), (-0.02, 0.08), (-0.15, 0.6), (0.35, -0.12), (0.03, -0.12), (0.18, -0.6)]
    c.inked([(cx + x * s, cy + y * s) for x, y in pts], color, s * 0.07)


def bubble(c, x, y, w, h, color, tail_left=True):
    r = h * 0.3
    pts = []
    for corner, (ox, oy) in enumerate(((x + w - r, y + r), (x + w - r, y + h - r), (x + r, y + h - r), (x + r, y + r))):
        for step in range(7):
            angle = (corner - 1 + step / 6) * math.pi / 2
            pts.append((ox + r * math.cos(angle), oy + r * math.sin(angle)))
        if corner == 1:
            tip = x + w * (0.3 if tail_left else 0.7)
            pts += [(tip + h * 0.12, y + h), (tip - h * 0.08 if tail_left else tip + h * 0.3, y + h * 1.35), (tip - h * 0.1, y + h)]
    c.inked(pts, color, 9)


def sign_background(c, w, h, color):
    c.poly([(0, 0), (w, 0), (w, h), (0, h)], color)
    c.halftone((0, h * 0.45, w, h * 0.55), tuple(max(0, v - 18) for v in color[:3]) + (255,), 16)


# ------------------------------------------------------------------ pictures
def logo(path):
    c = Canvas(512, 512)
    badge(c, 256, 262, 214)
    c.save(path)


def print_picture(path):
    """The painting's print (2:1): a sunset over a small comic city, the badge on a billboard."""
    w, h = 768, 384
    c = Canvas(w, h, PAPER)
    c.halftone((0, 0, w, h * 0.55), (255, 214, 170, 255), 18, (0.05, 0.3))
    c.disc(560, 150, 70, YELLOW, 10)
    c.inked([(0, 260), (140, 190), (300, 240), (470, 175), (640, 230), (768, 200), (768, 384), (0, 384)], BLUE_LIGHT, 10)
    for x, top, width in ((40, 180, 90), (150, 130, 70), (240, 200, 110), (380, 150, 80), (480, 210, 120), (630, 170, 90)):
        c.inked([(x, top), (x + width, top), (x + width, 340), (x, 340)], BLUE if x % 3 else GREY, 8)
        for wy in range(top + 20, 320, 34):
            for wx in range(x + 14, x + width - 18, 26):
                c.poly([(wx, wy), (wx + 12, wy), (wx + 12, wy + 16), (wx, wy + 16)], YELLOW if (wx + wy) % 3 == 0 else PAPER)
    c.inked([(0, 330), (768, 330), (768, 384), (0, 384)], GREEN, 8)
    c.inked([(300, 60), (470, 60), (470, 140), (300, 140)], WHITE, 8)
    c.stroke([(330, 140), (330, 200)], INK, 10)
    c.stroke([(440, 140), (440, 200)], INK, 10)
    badge(c, 385, 100, 34)
    c.save(path)


def balloon(path):
    """The print on the floating thing (1:1): orange and paper rays round the badge."""
    c = Canvas(512, 512, PAPER)
    for i in range(16):
        a0, a1 = i * math.tau / 16, (i + 1) * math.tau / 16
        if i % 2 == 0:
            c.poly([(256, 256), (256 + 400 * math.cos(a0), 256 + 400 * math.sin(a0)), (256 + 400 * math.cos(a1), 256 + 400 * math.sin(a1))], ORANGE)
    badge(c, 256, 256, 170)
    c.save(path)


def obstacle(path, kind):
    w, h = 512, 256
    c = Canvas(w, h)
    sign_background(c, w, h, PAPER)
    if kind == 1:   # a gear struck by lightning
        gear(c, 200, 128, 86, GREY)
        bolt(c, 320, 120, 170, YELLOW)
    elif kind == 2:  # a pile of speech bubbles with alert marks
        bubble(c, 90, 40, 180, 90, WHITE)
        bubble(c, 230, 100, 200, 96, BLUE_LIGHT, False)
        for x, y in ((180, 85), (330, 148)):
            c.inked([(x - 9, y - 30), (x + 9, y - 30), (x + 5, y + 6), (x - 5, y + 6)], RED, 5)
            c.disc(x, y + 22, 8, RED, 5)
    elif kind == 3:  # stairs that keep climbing out of the frame
        steps = [(80 + i * 70, 200 - i * 34) for i in range(6)]
        pts = [(60, 220)] + [p for x, y in steps for p in ((x, y), (x + 70, y))] + [(500, 220)]
        c.inked(pts, ORANGE, 10)
        c.inked([(430, 40), (480, 40), (480, 10), (512, 60), (480, 110), (480, 80), (430, 80)], RED, 8)
    elif kind == 4:  # two arrows meeting head on with a spark
        c.inked([(40, 100), (190, 100), (190, 70), (250, 128), (190, 186), (190, 156), (40, 156)], BLUE, 10)
        c.inked([(472, 100), (322, 100), (322, 70), (262, 128), (322, 186), (322, 156), (472, 156)], ORANGE, 10)
        star(c, 256, 128, 70, YELLOW, 6)
    else:            # a stopwatch with a running hand
        c.disc(256, 140, 96, WHITE, 12)
        c.inked([(236, 24), (276, 24), (276, 46), (236, 46)], RED, 8)
        c.stroke([(256, 140), (256, 70)], INK, 12)
        c.stroke([(256, 140), (318, 168)], RED, 10)
        for i in range(12):
            a = i * math.tau / 12
            c.stroke([(256 + 78 * math.cos(a), 140 + 78 * math.sin(a)), (256 + 88 * math.cos(a), 140 + 88 * math.sin(a))], INK, 6)
    c.save(path)


def poster(path, kind):
    w, h = 384, 512
    c = Canvas(w, h, BLUE_LIGHT if kind == 1 else PAPER)
    c.halftone((0, 0, w, h), (255, 255, 255, 255) if kind == 1 else (240, 222, 186, 255), 20, (0.06, 0.24))
    if kind == 1:    # a rocket lifting off a cloud
        c.inked([(192, 60), (240, 140), (240, 330), (144, 330), (144, 140)], WHITE, 10)
        c.disc(192, 200, 30, BLUE, 9)
        c.inked([(144, 260), (104, 340), (144, 330)], ORANGE, 9)
        c.inked([(240, 260), (280, 340), (240, 330)], ORANGE, 9)
        c.inked([(156, 330), (228, 330), (192, 430)], YELLOW, 9)
        c.inked([(170, 330), (214, 330), (192, 390)], ORANGE, 6)
        for cx, cy, r in ((110, 450, 60), (200, 470, 70), (290, 450, 60)):
            c.disc(cx, cy, r, WHITE, 9)
    else:            # a big mug of coffee, steam rising
        c.inked([(100, 220), (270, 220), (255, 420), (115, 420)], ORANGE, 10)
        c.stroke([(270, 260), (320, 270), (318, 340), (262, 360)], INK, 26)
        c.stroke([(270, 260), (320, 270), (318, 340), (262, 360)], ORANGE, 12)
        c.inked([(110, 230), (260, 230), (260, 250), (110, 250)], (110, 64, 36, 255), 6)
        badge(c, 185, 330, 46)
        for x in (140, 185, 230):
            c.stroke([(x, 200), (x - 12, 170), (x + 10, 140), (x - 6, 110)], (255, 255, 255, 255), 10)
    c.save(path)


def team_photo(path, kind):
    """A team wall stand-in (512 x 512, square): one simple object on a colour, no face."""
    c = Canvas(512, 512, [BLUE_LIGHT, (255, 214, 170, 255), (190, 230, 200, 255), (225, 205, 245, 255)][kind - 1])
    c.halftone((0, 0, 512, 512), (255, 255, 255, 255), 24, (0.05, 0.2))
    if kind == 1:    # a bike wheel
        c.disc(256, 256, 170, WHITE, 18)
        c.circle(256, 256, 120, BLUE_LIGHT)
        for i in range(12):
            a = i * math.tau / 12
            c.stroke([(256, 256), (256 + 150 * math.cos(a), 256 + 150 * math.sin(a))], INK, 6)
        c.disc(256, 256, 26, ORANGE, 8)
    elif kind == 2:  # a potted plant
        c.inked([(176, 330), (336, 330), (316, 450), (196, 450)], ORANGE, 12)
        for x, y, r in ((256, 200, 70), (190, 250, 55), (322, 250, 55)):
            c.disc(x, y, r, GREEN, 10)
        c.stroke([(256, 330), (256, 220)], INK, 10)
    elif kind == 3:  # a paper plane
        c.inked([(90, 300), (430, 140), (300, 420), (250, 320)], WHITE, 12)
        c.stroke([(250, 320), (430, 140)], INK, 8)
    else:            # a star
        star(c, 256, 256, 190, YELLOW, 5)
    c.save(path)


def tone(path, notes, rate=22050, buzz=0.0):
    """Mono clip of the given notes [(Hz, seconds)], soft attack and decay; `buzz` adds a square edge. PCM16, then oggenc."""
    frames = bytearray()
    for frequency, seconds in notes:
        count = int(rate * seconds)
        for i in range(count):
            t = i / rate
            wave_value = math.sin(math.tau * frequency * t)
            if buzz:
                wave_value = (1 - buzz) * wave_value + buzz * (1.0 if wave_value >= 0 else -1.0)
            envelope = min(1.0, t * 80.0) * math.exp(-3.0 * t)
            frames += struct.pack("<h", int(12000 * envelope * wave_value))
    with tempfile.TemporaryDirectory(dir=path.parent) as scratch:
        source = Path(scratch) / "clip.wav"
        with wave.open(str(source), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(rate)
            out.writeframes(bytes(frames))
        subprocess.run(["oggenc", "--quiet", "-q", "2", "-o", str(path), str(source)], check=True)


# The announcer: two short tone figures per event (placeholders for the pack's spoken lines).
ANNOUNCER = {
    "start": [[(523, 0.18), (784, 0.35)], [(392, 0.15), (523, 0.15), (784, 0.3)]],
    "near_drop": [[(660, 0.12), (620, 0.12), (660, 0.12), (620, 0.2)], [(880, 0.1), (830, 0.1), (880, 0.25)]],
    "break": [[(523, 0.15), (392, 0.15), (262, 0.4)], [(440, 0.2), (330, 0.45)]],
    "pop": [[(1200, 0.06), (300, 0.25)], [(900, 0.05), (220, 0.3)]],
    "zap": [[(1500, 0.08), (1100, 0.08), (700, 0.25)], [(1300, 0.3)]],
    "goal": [[(523, 0.12), (659, 0.12), (784, 0.12), (1047, 0.45)], [(392, 0.15), (523, 0.15), (659, 0.4)]],
    "perfect": [[(523, 0.1), (659, 0.1), (784, 0.1), (1047, 0.1), (1319, 0.6)], [(659, 0.12), (784, 0.12), (1047, 0.12), (1568, 0.6)]],
}


def sounds(folder):
    """Voice blips per cast member (member_<n>.ogg plus one variant member_<n>_1.ogg) and the announcer's lines, when oggenc is there."""
    if shutil.which("oggenc") is None:
        print("make_sample_cast: oggenc not found, sound clips skipped")
        return
    (folder / "voice").mkdir(exist_ok=True)
    for member, (low, high) in enumerate(((330, 660), (520, 300), (440, 880), (600, 380)), start=1):
        tone(folder / f"voice/member_{member}.ogg", [(low, 0.15), (high, 0.35)])
        tone(folder / f"voice/member_{member}_1.ogg", [(high, 0.12), (low, 0.12), (high, 0.3)])
    (folder / "announcer").mkdir(exist_ok=True)
    for event, figures in ANNOUNCER.items():
        for variant, notes in enumerate(figures, start=1):
            tone(folder / f"announcer/{event}_{variant}.ogg", notes, buzz=0.35 if event == "zap" else 0.0)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=str(ROOT / "samples/acme"))
    folder = Path(parser.parse_args().out)
    folder.mkdir(parents=True, exist_ok=True)
    logo(folder / "logo.png")
    print_picture(folder / "print.png")
    balloon(folder / "balloon.png")
    for kind in range(1, 6):
        obstacle(folder / f"obstacle_{kind}.png", kind)
    for kind in (1, 2):
        poster(folder / f"poster_{kind}.png", kind)
    (folder / "team").mkdir(exist_ok=True)
    for kind in range(1, 5):
        team_photo(folder / f"team/member_{kind}.png", kind)
    sounds(folder)
    print(f"make_sample_cast: wrote {folder}")


if __name__ == "__main__":
    main()
