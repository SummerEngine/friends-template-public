"""Shared parts of the hero-prop build scripts (docs/hero-prop.md). Runs inside Blender, never on its own:

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/cast_models/hero_prop_cake.py -- \
        --out demo/cast/hero_prop.glb --colors "#0e9aa7,#4a2c82,#8fe3b8" --logo demo/cast/logo.png

The model is procedural (no AI-generated mesh, no downloaded asset): the script is the source, the .glb is its output, and a new brand
is one new command line. The conventions every hero prop keeps (the game fits and anchors any model, but its collision is fixed):

* Metres, +Y up, +Z is the front (towards the players who climb up to it). The stand is three tiers, each BOX_H / 3 tall and
  1 / 2 / 3 of the way up in width: radius at most BOX_W / 2 on the bottom tier, two thirds of that on the middle one, a third on the top
  one. The walkable collision is exactly that stepped stack of cylinders, so the model keeps inside it and rises to its top.
* Origin at the bottom centre. The top surface (flat, at BOX_H) is where the crown floats.
* Under 5 MB: textures at most 512 px (the logo is composited onto its plaque, so the model needs no transparency).
"""
import argparse
import colorsys
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

BOX_W = 4.5          # footprint (diameter of the bottom tier), m
BOX_H = 3.0          # height of the stand, m
TIERS = 3
TIER_H = BOX_H / TIERS
TIER_R = [BOX_W / 2 * share for share in (1.0, 2.0 / 3.0, 1.0 / 3.0)]  # 2.25, 1.5, 0.75 m


def arguments():
    """The command line after the `--` that ends Blender's own arguments."""
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, help="the .glb to write (demo/cast/hero_prop.glb)")
    parser.add_argument("--colors", default="", help="up to 3 brand colours, #rrggbb, comma separated (the first is the strongest)")
    parser.add_argument("--logo", default="", help="the brand logo (png), stamped on a plaque on the front")
    return parser.parse_args(rest)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ------------------------------------------------------------------ colours

def hex_rgb(text):
    text = text.strip().lstrip("#")
    return tuple(int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_hex(rgb):
    return "#" + "".join(f"{round(max(0.0, min(1.0, v)) * 255):02x}" for v in rgb)


def shade(rgb, value=1.0, saturation=1.0):
    h, s, v = colorsys.rgb_to_hsv(*rgb)
    return colorsys.hsv_to_rgb(h, max(0.0, min(1.0, s * saturation)), max(0.0, min(1.0, v * value)))


def tier_palette(text):
    """Three tier colours, bottom to top, from the brand colours: the colours given, then tints of the first when fewer than three."""
    given = [hex_rgb(part) for part in text.split(",") if part.strip()][:3]
    if not given:
        given = [hex_rgb("#2c4bff")]
    if len(given) < 2:
        given.append(shade(given[0], 0.6))
    if len(given) < 3:
        given.append(shade(given[0], 1.0, 0.4))
    return given


def srgb_to_linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def material(name, rgb, roughness=0.55, metallic=0.0, image=None):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:  # newer Blender: nodes are always on
        pass
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[srgb_to_linear(v) for v in rgb], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if image is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# ------------------------------------------------------------------ geometry

def to_blender(point):
    """Game space (x right, y up, z front) to Blender's Z-up space; the glTF exporter turns it back into the same game space."""
    return Vector((point[0], -point[2], point[1]))


class Parts:
    """Geometry in game space, one mesh per material: the whole prop becomes a handful of objects."""

    def __init__(self):
        self.meshes = {}   # name -> [bmesh, material]
        self.rng = random.Random(7)

    def mesh_for(self, name, mat):
        if name not in self.meshes:
            self.meshes[name] = [bmesh.new(), mat]
        return self.meshes[name][0]

    def lathe(self, name, mat, profile, at=(0.0, 0.0), segments=48, closed=False, squash=1.0, rotate=0.0):
        """A surface of revolution about the vertical axis through `at` (x, z). `profile` = [(radius, y)] or [(radius, y, sharp)]; a sharp
        point gets a hard edge. A profile that starts and ends on the axis (radius 0) is a closed solid; with `closed` the last point joins
        the first (a ring). `squash` flattens the radius along the local z, which `rotate` (degrees from +Z towards +X) then turns about the
        vertical: a drip squashed against a wall it faces."""
        bm = self.mesh_for(name, mat)
        turn_cos, turn_sin = math.cos(math.radians(rotate)), math.sin(math.radians(rotate))
        rings = []
        for point in profile:
            radius, height = point[0], point[1]
            if radius <= 1e-6:
                rings.append([bm.verts.new(to_blender((at[0], height, at[1])))])
                continue
            ring = []
            for i in range(segments):
                a = math.tau * i / segments
                lx, lz = math.sin(a) * radius, math.cos(a) * radius * squash
                ring.append(bm.verts.new(to_blender((at[0] + lx * turn_cos + lz * turn_sin, height, at[1] - lx * turn_sin + lz * turn_cos))))
            rings.append(ring)
        if closed:
            rings.append(rings[0])
        for k in range(len(rings) - 1):
            a, b = rings[k], rings[k + 1]
            for i in range(segments):
                j = (i + 1) % segments
                if len(a) == 1:
                    corners = [a[0], b[j], b[i]]
                elif len(b) == 1:
                    corners = [a[i], a[j], b[0]]
                else:
                    corners = [a[i], a[j], b[j], b[i]]
                try:
                    bm.faces.new(corners).smooth = True
                except ValueError:
                    continue
        for k, point in enumerate(profile):
            if len(point) > 2 and point[2] and len(rings[k]) > 1:
                for i in range(segments):
                    edge = bm.edges.get((rings[k][i], rings[k][(i + 1) % segments]))
                    if edge is not None:
                        edge.smooth = False
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    def reeded(self, name, mat, at, r_hi, r_lo, r_in, y_lo, y_hi, grooves=72):
        """A ring with a grooved (reeded) outside, like a coin's edge: the outside alternates between r_hi and r_lo, flat shaded."""
        bm = self.mesh_for(name, mat)
        count = grooves * 2
        outer_lo, outer_hi, inner_lo, inner_hi = [], [], [], []
        for k in range(count):
            a = math.tau * k / count
            radius = r_hi if (k // 1) % 2 == 0 else r_lo
            direction = (math.sin(a), math.cos(a))
            outer_lo.append(bm.verts.new(to_blender((at[0] + direction[0] * radius, y_lo, at[1] + direction[1] * radius))))
            outer_hi.append(bm.verts.new(to_blender((at[0] + direction[0] * radius, y_hi, at[1] + direction[1] * radius))))
            inner_lo.append(bm.verts.new(to_blender((at[0] + direction[0] * r_in, y_lo, at[1] + direction[1] * r_in))))
            inner_hi.append(bm.verts.new(to_blender((at[0] + direction[0] * r_in, y_hi, at[1] + direction[1] * r_in))))
        for k in range(count):
            j = (k + 1) % count
            for quad in ((outer_lo[k], outer_lo[j], outer_hi[j], outer_hi[k]), (outer_hi[k], outer_hi[j], inner_hi[j], inner_hi[k]),
                         (inner_lo[k], inner_lo[j], outer_lo[j], outer_lo[k]), (inner_hi[k], inner_hi[j], inner_lo[j], inner_lo[k])):
                try:
                    bm.faces.new(quad).smooth = False
                except ValueError:
                    continue
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    def box(self, name, mat, centre, size, turn=0.0):
        """A box (game space) of `size` (x, y, z) at `centre`, turned `turn` degrees about the vertical through its centre."""
        bm = self.mesh_for(name, mat)
        c, s = math.cos(math.radians(turn)), math.sin(math.radians(turn))
        verts = []
        for sx in (-0.5, 0.5):
            for sy in (-0.5, 0.5):
                for sz in (-0.5, 0.5):
                    x, z = sx * size[0], sz * size[2]
                    verts.append(bm.verts.new(to_blender((centre[0] + x * c + z * s, centre[1] + sy * size[1], centre[2] - x * s + z * c))))
        for quad in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            face = bm.faces.new([verts[i] for i in quad])
            face.smooth = False
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    def quad(self, name, mat, centre, width, height):
        """A flat picture quad facing +Z (game space), UV 0..1 over it."""
        bm = self.mesh_for(name, mat)
        uv = bm.loops.layers.uv.verify()
        points = [(-0.5, -0.5, 0.0, 0.0), (0.5, -0.5, 1.0, 0.0), (0.5, 0.5, 1.0, 1.0), (-0.5, 0.5, 0.0, 1.0)]
        verts = [bm.verts.new(to_blender((centre[0] + px * width, centre[1] + py * height, centre[2]))) for px, py, _, _ in points]
        face = bm.faces.new(verts)
        face.smooth = False
        for loop, (_, _, u, v) in zip(face.loops, points):
            loop[uv].uv = (u, v)

    def ball(self, name, mat, centre, radius, segments=10):
        rows = max(4, segments // 2)
        profile = [(0.0, centre[1] - radius)]
        for k in range(1, rows):
            angle = math.pi * k / rows - math.pi / 2
            profile.append((radius * math.cos(angle), centre[1] + radius * math.sin(angle)))
        profile.append((0.0, centre[1] + radius))
        self.lathe(name, mat, profile, at=(centre[0], centre[2]), segments=segments)

    def build(self, collection_name="Hero"):
        """Turns every part into a mesh object; returns the objects."""
        objects = []
        for name, (bm, mat) in self.meshes.items():
            mesh = bpy.data.meshes.new(name)
            bm.to_mesh(mesh)
            bm.free()
            mesh.materials.append(mat)
            obj = bpy.data.objects.new(name, mesh)
            bpy.context.scene.collection.objects.link(obj)
            objects.append(obj)
        return objects


def ring_of_balls(parts, name, mat, radius, y, count, ball_radius, skip=None):
    """Balls (pearls) on a circle about the vertical axis; `skip(angle degrees)` leaves gaps."""
    for i in range(count):
        angle = 360.0 * i / count
        if skip is not None and skip(angle):
            continue
        a = math.radians(angle)
        parts.ball(name, mat, (math.sin(a) * radius, y, math.cos(a) * radius), ball_radius, 8)


def front_plaque(parts, mats, centre_y, surface_z, size, border):
    """The logo plaque on the front (+Z) of the bottom tier: a rim, a cream plate and the logo picture on it."""
    parts.box("plaque_rim", mats["rim"], (0.0, centre_y, surface_z), (size + border * 2.0, size + border * 2.0, 0.07))
    parts.box("plaque_plate", mats["plate"], (0.0, centre_y, surface_z + 0.01), (size, size, 0.08))
    parts.quad("plaque_logo", mats["logo"], (0.0, centre_y, surface_z + 0.055), size * 0.94, size * 0.94)


def logo_image(path, plate_rgb, size=512):
    """The logo composited onto the plate colour as an opaque `size` px picture (None without a logo file)."""
    if not path or not os.path.exists(path):
        return None
    import numpy

    source = bpy.data.images.load(os.path.abspath(path))
    source.scale(size, size)
    pixels = numpy.empty(size * size * 4, dtype=numpy.float32)
    source.pixels.foreach_get(pixels)
    pixels = pixels.reshape(size, size, 4)
    plate = numpy.array([srgb_to_linear(v) for v in plate_rgb] + [1.0], dtype=numpy.float32)
    alpha = pixels[:, :, 3:4]
    out = numpy.empty_like(pixels)
    out[:, :, :3] = pixels[:, :, :3] * alpha + plate[:3] * (1.0 - alpha)
    out[:, :, 3] = 1.0
    image = bpy.data.images.new("hero_logo", size, size, alpha=False)
    image.pixels.foreach_set(out.reshape(-1))
    image.pack()
    bpy.data.images.remove(source)
    return image


def export(objects, out):
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in objects)
    folder = os.path.dirname(os.path.abspath(out))
    os.makedirs(folder, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(out), export_format="GLB", export_yup=True, export_apply=True,
                              export_cameras=False, export_lights=False, use_selection=True)
    print(f"HERO_PROP wrote {out} ({os.path.getsize(out) // 1024} KB), {sum(len(o.data.polygons) for o in objects)} faces")
