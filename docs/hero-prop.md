# The hero prop

The centrepiece of the final (level 16 `CROWN CLIMB`): the stand the crown floats over at the top of the climb. It is the one object of the
show that says what the team makes: a cake for a bakery, a stack of giant coins for a company that moves money or parcels, a barrel of
coffee beans for a roaster. The cast's own `hero_prop.glb` (a model made with a Blender script, never AI-generated) is that object; without
it the game builds a stepped stand in the brand colours with the logo on a plaque. Two small copies of it flank the podium after the final.

Players walk up to it and jump up its three tiers (each is 1 m, a jump reaches 1.44 m); reaching it is the goal, the crown turns above its
top. Nothing else marks the goal (no GOAL pad, word, flag or floating logo card on a level that has a hero prop).

![the cake](show-frames/46-hero-cake-tidewheat.jpg) ![the coin stack](show-frames/47-hero-coins-acme.jpg)

## The convention

One box, one anchor, one top. A model of any size and origin is fitted into the box by the game; its collision is fixed, so the model keeps
to the stepped silhouette below.

| | |
|---|---|
| Units, axes | metres, +Y up, the front (the side the players come from) is +Z |
| Box | 4.5 m across the floor (the footprint) x 3.0 m tall (`style/hero_prop.gd`, `tools/cast_check.py` `HERO_BOX`) |
| Fit | the game scales the model evenly until it fits the box (footprint = the longer side of its bounds across the floor, height = its bounds' height), puts the middle of its footprint on the anchor and its bottom on the floor: build it at 4.5 x 3.0 and it is shown as built |
| Anchor | the bottom centre of the footprint: the slot's `p` is on the floor, the prop stands up from it |
| Top surface | flat, at the top of the box (y = 3.0): the crown floats 0.25 m over it (the `crown` slot sits there) |
| Stand (collision) | three cylinders one on top of the other, each a third of the height (1.0 m) tall: radius 2.25 m (y 0 to 1), 1.5 m (1 to 2), 0.75 m (2 to 3). The model keeps inside this stack: no part wider than the tier it is on (a few cm of pearls, a plaque, drips are fine, `cast_check` allows 4 % + 3 cm) |
| Walkable | the flat tops of the tiers (the ledges and the top) are what a player stands on: keep them flat (a row of pearls or trim against the wall of the next tier is fine) |
| Size | under 5 MB; textures up to 512 px, embedded in the .glb |

The collision is the level's, not the model's: `level_16.json` holds the three cylinder blocks of every stand (`"slot": "hero_prop"`) and
the slot `{"id": "hero_prop", "p": [bottom centre], "size": [footprint, height]}`; the model only skins them. That keeps the authority, every
replica and every brand on the same physics, and a bad model (too wide, missing) can never trap anyone. A stand's tiers are always
`footprint x 1, 2/3, 1/3` across and `height / 3` tall, so the same model fits the 2.25 x 1.5 m podium copies (half size).

`python3 tools/cast_check.py` reads the model's vertices and reports `demo/cast/hero_prop.glb leaves the stand: ...` when a part is wider than
its tier at that height, and `has no meshes` for an empty file. `python3 tools/level_lint.py` checks that every `hero_prop` slot has its
three cylinders and that every tagged cylinder belongs to a slot.

The same fit, for the models of two other rounds (the spin bars `round_r21.glb`, the balls `round_r23.glb`): `HeroProp.fit_into(model, box)` scales a model evenly (never stretched)
to lie inside a hazard's collision box, centred on its pivot; the convention and the cast key are in `docs/swappables.md` ("Rounds as metaphors").

## Fallback without a model

`style/hero_prop.gd` `HeroProp.stand()`: three drums in the brand colours (bottom to top: `brand.colors[0]`, `[1]`, `[2]`; with fewer colours
a darker and a paler shade of the first; without any the template's blue, navy and yellow), each with a darker foot and a cream rim whose flat
top is the ledge, and the logo on a cream plaque at the front of the bottom tier when the cast has a logo. Nothing to fill in.

## Make one (for an agent)

1. **The idea.** One object that the team's answer to "what do you make or sell" (`team.facts.products`, `team.one_liner`) turns into,
   as a stack of three that gets narrower: a layered cake, a stack of coins, a tower of crates, books, pizza boxes, coffee sacks,
   sushi drums, a pile of cogs. One idea, big and simple, readable from 10 m. The brand colours (up to three, bottom tier first) and the logo
   decide the look; the idea decides the shape. Never a person, never another company's product or mascot.
2. **Start from a script** in `tools/cast_models/` (they are the source of the sample `hero_prop.glb` files; the .glb is their output):
   * `hero_prop_cake.py`: three fondant drums, icing lips with drips, pearls, a logo plaque (`samples/tidewheat/hero_prop.glb`);
   * `hero_prop_coin_stack.py`: three coins with reeded edges and gold rims, a logo plaque (`samples/acme/hero_prop.glb`);
   * `hero_common.py`: what they share (the box numbers, `Parts` to build geometry in game space, colour handling, the logo composited onto
     its plaque, the glTF export). Copy a script to `hero_prop_<idea>.py`, change the shapes, keep the conventions.
3. **Run it** (Blender in the background only, never its window):
   ```
   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/cast_models/hero_prop_cake.py -- \
       --out demo/cast/hero_prop.glb --colors "#0e9aa7,#4a2c82,#8fe3b8" --logo demo/cast/logo.png
   ```
   `--colors` are the cast's `brand.colors` (up to three, the strongest first), `--logo` is `demo/cast/logo.png`. A new brand is a new command line.
4. **Look at it.** Quick: `Blender --background --python tools/cast_models/preview_glb.py -- demo/cast/hero_prop.glb /tmp/hero.png`. Then in the
   game (offscreen binary on a project clone, never on the live project): `tools/modes/show_frames.gd` with
   `--only=summit --shot=summit:15:12,33,-34:12,32.5,-42:0` renders the summit; `python3 tools/cast_check.py` must pass.

Script conventions (the two scripts follow them; keep them in a new one):

* **Procedural only.** Every vertex comes from the script: lathes (surfaces of revolution), rings, boxes, quads. No AI-generated mesh, no
  downloaded model, no sculpt. The script is committed next to the model it made; the .glb is rebuilt with one command line.
* **Game space inside the script.** Build with `Parts` in the game's axes (x right, y up, z front, metres): `hero_common.to_blender()` turns it
  into Blender's Z-up space, the glTF exporter turns it back, so the .glb has +Y up and the front at +Z with no rotation to fix.
* **Origin at the bottom centre**, the footprint centred on x = z = 0, the bottom on y = 0, the top flat at y = 3.0 (`hero_common.BOX_H`).
  Tier radii `hero_common.TIER_R` = 2.25, 1.5, 0.75 and tier height `TIER_H` = 1.0: keep every vertex of a tier inside its radius.
* **Few objects, few materials.** `Parts` makes one mesh object per material (about ten for the cake, under 12 000 triangles, a phone has to
  draw it); `export_apply` bakes nothing else. Principled BSDF with a base colour (sRGB hex in, linear out), roughness, metallic: flat, bold,
  clean colours in the house look (`docs/slots.md`), no baked lighting.
* **Smooth where it is round, sharp where it is a rim.** `lathe()` takes `(radius, y, sharp)` points: a sharp point is a hard edge, so a flat top
  stays flat-shaded.
* **The logo on a plaque, never on the geometry.** `front_plaque()` stands a cream plate with the logo picture proud of the front of the bottom
  tier (+Z). `logo_image()` composites the logo onto the plate colour and scales it to 512 px, so the model needs no transparency and a
  logo with a background works too.
* **No text in the model**, no brand but the team's own logo, nothing that reads as an ad.
* **Deterministic.** Random choices (the drips) use the seeded `Parts.rng`: the same command line gives the same file.

## Where it is placed

`level_16.json`: the summit stand at the middle of the top platform, in front of the goal volume (`"p": [12, 30, -42]`, `"size": [4.5, 3.0]`,
tiers as cylinder blocks centred at y 30.5, 31.5 and 32.5) with the `crown` slot over it (`"p": [12, 34, -42]`, `"size": [1.5, 1.5]`: the
crown floats 0.25 m over the top and is as wide as the top tier), and two copies at half size beside the podium (`"p": [7, 30, -55]` and
`[17, 30, -55]`, `"size": [2.25, 1.5]`: tiers of 0.5 m that a courier walks up like stairs). The path ends 0.25 m short of the stand, inside
the goal volume. Another show level (`docs/level-format.md`, "Hero props") places a stand the same way: the slot, its three cylinders, the crown slot
over it. `tools/hero_stand_check.gd` (headless, run as the other Godot checks under `tools/engine_slot.sh`) walks a courier into every stand of level 16
on the real collision and checks that the base tier stops it and that jumping reaches the top.
