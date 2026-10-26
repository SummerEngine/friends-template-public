"""The hero prop of a bakery: a three-tier cake in the brand colours, with a logo plaque on the front (docs/hero-prop.md).

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/cast_models/hero_prop_cake.py -- \
        --out demo/cast/hero_prop.glb --colors "#0e9aa7,#4a2c82,#8fe3b8" --logo demo/cast/logo.png

Every tier is a fondant drum in one brand colour (bottom to top), a glossy cream icing lip with drips, and a ring of pearls round its
foot. The flat icing tops are what players stand on; the top one is where the crown floats. Procedural: the script is the source.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_common as hero  # noqa: E402

CREAM = (1.0, 0.953, 0.851)


def main():
    options = hero.arguments()
    hero.clear_scene()
    colors = hero.tier_palette(options.colors)
    parts = hero.Parts()
    icing = hero.material("icing", CREAM, roughness=0.28)
    pearl = hero.material("pearl", (0.96, 0.93, 0.86), roughness=0.22, metallic=0.25)
    image = hero.logo_image(options.logo, CREAM)
    mats = {
        "rim": hero.material("plaque_rim", colors[1], roughness=0.4),
        "plate": hero.material("plaque_plate", CREAM, roughness=0.5),
        "logo": hero.material("plaque_logo", CREAM, roughness=0.5, image=image),
    }
    for tier in range(hero.TIERS):
        radius = hero.TIER_R[tier]
        y0 = tier * hero.TIER_H
        top = y0 + hero.TIER_H
        body = radius - 0.07
        fondant = hero.material(f"fondant_{tier}", colors[tier], roughness=0.45)
        parts.lathe(f"fondant_{tier}", fondant, [(0.0, y0), (body - 0.04, y0, True), (body, y0 + 0.04), (body, top - 0.1, True), (body - 0.1, top - 0.1), (0.0, top - 0.1)],
                    segments=72)
        parts.lathe("icing", icing, [(0.0, top), (body - 0.03, top, True), (body + 0.025, top - 0.035), (body + 0.045, top - 0.10),
                                      (body + 0.03, top - 0.17), (body - 0.02, top - 0.21, True), (0.0, top - 0.21)], segments=72)
        # drips: teardrops hanging off the lip, none in front of the plaque
        count = max(10, round(math.tau * body / 0.30))
        for i in range(count):
            angle = 360.0 * (i + parts.rng.uniform(-0.25, 0.25)) / count
            if tier == 0 and abs((angle + 180.0) % 360.0 - 180.0) < 16.0:
                continue
            width = parts.rng.uniform(0.055, 0.085)
            length = parts.rng.uniform(0.18, 0.46)
            a = math.radians(angle)
            reach = body + 0.025
            y_top = top - 0.12
            parts.lathe("icing", icing, [(0.0, y_top), (width * 0.9, y_top - 0.01), (width, y_top - 0.05), (width, y_top - length + width),
                                          (width * 0.65, y_top - length + width * 0.3), (0.0, y_top - length)],
                        at=(math.sin(a) * reach, math.cos(a) * reach), segments=10, squash=0.55, rotate=angle)
        hero.ring_of_balls(parts, "pearl", pearl, radius - 0.1, y0 + 0.08, max(16, round(math.tau * radius / 0.19)), 0.075)
    hero.front_plaque(parts, mats, centre_y=0.42, surface_z=hero.TIER_R[0] - 0.07, size=0.7, border=0.04)
    hero.export(parts.build(), options.out)


main()
