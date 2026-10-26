"""A quick look at a hero prop (or any .glb) without the game: renders it to a PNG with Blender, background only (no window).

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/cast_models/preview_glb.py -- demo/cast/hero_prop.glb /tmp/hero.png

The camera looks at the front (+Z) from the side and above, the way the player meets the prop. The game's own frames (docs/hero-prop.md,
"Look at it in the game") are the real proof; this is the fast loop while the script is being written.
"""
import math
import sys

import bpy
from mathutils import Vector

source, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 900, 700
camera = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
scene.collection.objects.link(camera)
scene.camera = camera
camera.location = Vector((6.5, -9.0, 5.0))  # Blender is Z-up: the game's +Z (the front) is -Y here
camera.rotation_euler = (Vector((0.0, 0.0, 1.5)) - camera.location).to_track_quat("-Z", "Y").to_euler()
light = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
light.data.energy = 3.0
light.rotation_euler = (math.radians(50), 0.0, math.radians(30))
scene.collection.objects.link(light)
scene.world = bpy.data.worlds.new("world")
scene.world.color = (0.6, 0.65, 0.7)
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
