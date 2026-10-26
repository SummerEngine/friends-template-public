"""The hero prop of a company with no product to bake: a stack of three giant coins in the brand colours, the logo stamped on a
plaque at the front (docs/hero-prop.md).

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/cast_models/hero_prop_coin_stack.py -- \
        --out demo/cast/hero_prop.glb --colors "#ff6a13,#1d1d1f,#3a5bd9" --logo demo/cast/logo.png

Every coin is a reeded edge in a darker shade of one brand colour (bottom to top) between two gold rims, a field in the colour on top.
The rims are the surfaces players stand on; the top coin's top is where the crown floats. Procedural: the script is the source.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_common as hero  # noqa: E402

GOLD = (0.949, 0.761, 0.188)
CREAM = (0.965, 0.929, 0.820)


def main():
    options = hero.arguments()
    hero.clear_scene()
    colors = hero.tier_palette(options.colors)
    parts = hero.Parts()
    gold = hero.material("gold", GOLD, roughness=0.3, metallic=0.85)
    image = hero.logo_image(options.logo, CREAM)
    mats = {
        "rim": hero.material("plaque_rim", GOLD, roughness=0.3, metallic=0.85),
        "plate": hero.material("plaque_plate", CREAM, roughness=0.5),
        "logo": hero.material("plaque_logo", CREAM, roughness=0.5, image=image),
    }
    for tier in range(hero.TIERS):
        radius = hero.TIER_R[tier]
        y0 = tier * hero.TIER_H
        top = y0 + hero.TIER_H
        outer = radius - 0.03
        inner = radius - 0.22
        face = hero.material(f"coin_{tier}", colors[tier], roughness=0.4, metallic=0.2)
        edge = hero.material(f"reeding_{tier}", hero.shade(colors[tier], 0.62), roughness=0.5, metallic=0.2)
        parts.reeded(f"reeding_{tier}", edge, (0.0, 0.0), outer - 0.01, outer - 0.07, outer - 0.2, y0 + 0.14, top - 0.14, grooves=max(36, round(radius * 40)))
        segments = 72
        for flip, base in ((1.0, top), (-1.0, y0)):  # the top rim and field, the bottom rim
            rim = [(inner, base, True), (outer - 0.05, base, True), (outer, base - flip * 0.05), (outer, base - flip * 0.14), (inner, base - flip * 0.14, True)]
            parts.lathe("gold", gold, rim, closed=True, segments=segments)
            if flip > 0:
                parts.lathe(f"coin_{tier}", face, [(0.0, base - 0.05), (inner + 0.005, base - 0.05, True), (inner + 0.005, base - 0.10), (0.0, base - 0.10)], segments=segments)
    hero.front_plaque(parts, mats, centre_y=0.5, surface_z=hero.TIER_R[0] - 0.07, size=0.7, border=0.04)
    hero.export(parts.build(), options.out)


main()
