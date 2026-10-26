#!/usr/bin/env python3
"""Pack the two generated painting pictures into demo/assets/paintings/painting_atlas.png (512 px wide atlas).

    /tmp/lr-venv/bin/python tools/make_painting_atlas.py <landscape raw png> <portrait raw png>

The raws (1536x1024) were generated on 2026-10-19 with the OpenAI image API, model gpt-image-2.5-sunburst (the raw PNGs are kept
in the project's local lab folder, not in this tree). Prompts:
  landscape: a charming naive-art oil painting landscape, rolling green hills, a winding river, a small red-roofed farmhouse, puffy
    clouds, warm morning light; bold simple shapes, visible brushstrokes, saturated colours; wide panoramic composition; no text,
    no frame, no border, paint fills the canvas edge to edge.
  portrait: a grand formal wedding portrait oil painting in a warm old-master style with a friendly storybook charm: a smiling bride
    in a big white gown with a veil and bouquet and a groom in a navy suit with a pink rose, close together in the centre, in front of
    a burgundy velvet curtain and a tall window with garden roses; the couple fills the central third and garlands fill the sides so
    the picture can be cropped to a wide band; no text, no frame, no border.
Each is cropped to its picture's aspect (tools/build_painting_items.py PAINTINGS: landscape 1.7x0.7 m, portrait 2.4x0.9 m) and
resized to 512 px wide; the rects below are the atlas regions build_painting_items.py bakes into the canvas UVs.
"""
import sys
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "demo/assets/paintings/painting_atlas.png"
WIDTH = 512
# name -> (picture width m, height m, crop top in the raw image, atlas y)
LAYOUT = {"landscape": (1.7, 0.7, 190, 0), "portrait": (2.4, 0.9, 30, 212)}

def main():
    raws = dict(zip(("landscape", "portrait"), sys.argv[1:3]))
    height = max(y + round(WIDTH * h / w) for w, h, _, y in LAYOUT.values())
    atlas = Image.new("RGB", (WIDTH, height), (255, 255, 255))
    for name, (w, h, top, y) in LAYOUT.items():
        raw = Image.open(raws[name]).convert("RGB")
        crop_h = round(raw.width * h / w)
        crop = raw.crop((0, top, raw.width, top + crop_h)).resize((WIDTH, round(WIDTH * h / w)), Image.LANCZOS)
        atlas.paste(crop, (0, y))
        print(name, "rect", (0, y, WIDTH, crop.height))
    atlas.save(OUT, optimize=True)
    print("wrote", OUT, atlas.size, OUT.stat().st_size, "bytes")

if __name__ == "__main__":
    main()
