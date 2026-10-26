"""The investor's hand of the SMASH item (modes/show/items_ui/smash_view.gd): a big cartoon glove, palm down, ready to flatten whatever is under it.

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/item_models/hand_glove.py -- --out demo/modes/show/items_ui/hand.glb

Procedural: the script is the source, the .glb its output (no downloaded or generated mesh). Metres, +Y up, the fingers point to -Z (the way the game's characters face), a right
hand seen from above: the thumb is on the -X side. The origin is the centre of the palm's underside; the underside is flat and lies on y = 0, so the game rests it on whatever it
presses. The glove is about 3 m from the wrist to the middle fingertip, the palm 1.8 m wide, the cuff rises behind it. Four materials of flat clean colour: `glove` (white), `ink`
(the cuff and the three stitch lines on the back of the hand, the show's ink), `band` (the thin accent band on the cuff; the game paints it in the cast's brand accent).
The hand is a union of ellipsoids and chains of balls that a voxel remesh welds into one skin, smoothed and thinned out; the stitch lines are laid on that skin by ray casts.
"""
import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

INK = (0.04, 0.06, 0.16)
WHITE = (0.97, 0.97, 0.96)
ACCENT = (0.24, 0.48, 1.0)
SEGMENTS = 36                     # round sections of the cuff
WRIST_AT = Vector((0.0, 0.34, 0.50))  # where the wrist axis leaves the palm (game space)
WRIST_TILT = math.radians(26.0)   # the cuff rises behind the hand
VOXEL = 0.03
FINAL_FACES = 9000


def arguments():
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    return parser.parse_args(rest)


def srgb_to_linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def material(name, rgb, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[srgb_to_linear(v) for v in rgb], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def to_blender(point):
    """Game space (x right, y up, -z forward) to Blender's Z-up space; the glTF exporter turns it back."""
    return Vector((point[0], -point[2], point[1]))


def from_blender(point):
    return Vector((point[0], point[2], -point[1]))


# ------------------------------------------------------------------ the skin: ellipsoids and ball chains, welded by a voxel remesh

def ellipsoid(bm, centre, half, segments=24, rings=14):
    made = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    verts = made["verts"]
    for v in verts:
        v.co = to_blender((centre[0] + v.co.x * half[0], centre[1] + v.co.z * half[1], centre[2] - v.co.y * half[2]))


def chain(bm, points, radii):
    """Balls along a path (game points) with the radius easing from radii[0] to radii[-1]; a ball every third of its radius, so the union is a smooth sausage."""
    path = [Vector(p) for p in points]
    lengths = [(b - a).length for a, b in zip(path, path[1:])]
    total = sum(lengths)
    at, k = 0.0, 0
    while at <= total + 1e-6:
        while k < len(lengths) - 1 and at > sum(lengths[:k + 1]):
            k += 1
        start = sum(lengths[:k])
        t = (at - start) / max(lengths[k], 1e-6)
        centre = path[k].lerp(path[k + 1], min(max(t, 0.0), 1.0))
        along = at / max(total, 1e-6)
        radius = radii[0] + (radii[-1] - radii[0]) * along
        ellipsoid(bm, centre, (radius, radius, radius), 14, 8)
        at += max(radius * 0.32, 0.02)


def finger_path(root, length, spread, curl):
    """Root, joint, joint, tip: fanned `spread` degrees, curling down `curl` degrees by the tip."""
    heading = math.radians(spread)
    points = [Vector(root)]
    bend = 0.0
    for k, share in enumerate((0.40, 0.33, 0.27)):
        bend += math.radians(curl) * (0.4 + 0.6 * k)
        step = Vector((math.sin(heading) * math.cos(bend), -math.sin(bend), -math.cos(heading) * math.cos(bend))) * length * share
        points.append(points[-1] + step)
    return points


def axis_frame():
    """The wrist axis (pointing back and up), and the two directions across it."""
    d = Vector((0.0, math.sin(WRIST_TILT), math.cos(WRIST_TILT)))
    u = Vector((1.0, 0.0, 0.0))
    v = Vector((0.0, math.cos(WRIST_TILT), -math.sin(WRIST_TILT)))
    return d, u, v


def tube(bm, profile, smooth=True):
    """A surface of revolution about the wrist axis. profile = [(radius, along)]; a radius of 0 closes the end to a point. """
    d, u, v = axis_frame()
    rings = []
    for radius, t in profile:
        if radius <= 1e-6:
            rings.append([bm.verts.new(to_blender(WRIST_AT + d * t))])
            continue
        ring = []
        for i in range(SEGMENTS):
            a = math.tau * i / SEGMENTS
            ring.append(bm.verts.new(to_blender(WRIST_AT + d * t + (u * math.cos(a) + v * math.sin(a)) * radius)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(SEGMENTS):
            j = (i + 1) % SEGMENTS
            if len(a) == 1:
                corners = [a[0], b[j], b[i]]
            elif len(b) == 1:
                corners = [a[i], a[j], b[0]]
            else:
                corners = [a[i], a[j], b[j], b[i]]
            bm.faces.new(corners).smooth = smooth
    return rings


def hand_mesh():
    bm = bmesh.new()
    # the palm: a rounded slab with a gentle dome on the back, thicker over the knuckles
    ellipsoid(bm, (0.0, 0.30, 0.00), (0.92, 0.36, 0.64), 32, 18)
    ellipsoid(bm, (0.0, 0.33, -0.20), (0.90, 0.34, 0.46), 32, 18)
    # the wrist: a white cone from the palm into the cuff, closed at the palm end
    tube(bm, [(0.0, -0.30), (0.30, -0.22), (0.44, 0.0), (0.50, 0.30), (0.52, 0.50), (0.0, 0.52)])
    # four fingers: root, reach, fan, curl, radius at the root and at the tip
    for root, length, spread, curl, r0, r1 in (
        ((-0.66, 0.23, -0.42), 1.62, -4.0, 2.5, 0.255, 0.225),   # index
        ((-0.22, 0.23, -0.56), 1.82, -1.2, 2.5, 0.265, 0.235),   # middle
        ((0.22, 0.23, -0.52), 1.68, 2.0, 2.5, 0.26, 0.23),       # ring
        ((0.64, 0.22, -0.38), 1.32, 7.0, 2.5, 0.235, 0.205)):    # little
        path = finger_path(root, length, spread, curl)
        chain(bm, path, (r0, r1))
    # the thumb: out to the -X side and forward, fatter
    chain(bm, [(-0.74, 0.26, 0.05), (-1.18, 0.27, -0.22), (-1.50, 0.28, -0.66)], (0.31, 0.25))
    mesh = bpy.data.meshes.new("hand_union")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def evaluated(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    return bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))


def weld_and_smooth(mesh):
    """Voxel-remesh the union into one skin, round the creases, cut the underside flat on y = 0 and thin the mesh out."""
    obj = bpy.data.objects.new("union", mesh)
    bpy.context.scene.collection.objects.link(obj)
    remesh = obj.modifiers.new("remesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = VOXEL
    smooth = obj.modifiers.new("smooth", "SMOOTH")
    smooth.factor = 0.8
    smooth.iterations = 14
    skin = evaluated(obj)
    bpy.data.objects.remove(obj)
    bm = bmesh.new()
    bm.from_mesh(skin)
    geometry = list(bm.verts) + list(bm.edges) + list(bm.faces)
    cut = bmesh.ops.bisect_plane(bm, geom=geometry, plane_co=(0.0, 0.0, 0.0), plane_no=(0.0, 0.0, 1.0), clear_inner=True, clear_outer=False)
    edges = [e for e in cut["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(skin)
    bm.free()
    obj = bpy.data.objects.new("thin", skin)
    bpy.context.scene.collection.objects.link(obj)
    decimate = obj.modifiers.new("decimate", "DECIMATE")
    decimate.ratio = min(1.0, FINAL_FACES / max(len(skin.polygons), 1))
    result = evaluated(obj)
    bpy.data.objects.remove(obj)
    for poly in result.polygons:
        poly.use_smooth = True
    return result


def object_of(name, mesh, mat):
    mesh.materials.clear()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def cuff_mesh():
    """The cuff: a hollow flared ring seen from behind, rim rounded; the open end shows its thickness."""
    bm = bmesh.new()
    t0, t1 = 0.60, 1.22
    profile = [(0.0, t0 - 0.05), (0.50, t0 - 0.05), (0.60, t0), (0.62, 0.74), (0.67, t1 - 0.06), (0.70, t1 - 0.02), (0.70, t1), (0.67, t1 + 0.03), (0.60, t1 + 0.02), (0.56, t1 - 0.04), (0.53, 0.86), (0.50, t0 + 0.02), (0.0, t0 + 0.02)]
    tube(bm, profile)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    mesh = bpy.data.meshes.new("cuff")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def band_mesh():
    """The thin accent band round the cuff, at its mouth side of the wrist."""
    bm = bmesh.new()
    tube(bm, [(0.6, 0.0), (0.64, 0.01), (0.652, 0.04), (0.652, 0.10), (0.64, 0.13), (0.6, 0.14)], smooth=True)
    bmesh.ops.translate(bm, verts=bm.verts, vec=to_blender(axis_frame()[0] * 0.67) - to_blender(Vector((0, 0, 0))))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    mesh = bpy.data.meshes.new("band")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def stitch_mesh(skin):
    """Three raised stitch lines on the back of the hand: rays from above onto the skin, a thin ridge a hair above it."""
    tree = BVHTree.FromBMesh(bmesh_of(skin))
    bm = bmesh.new()
    for x0, x1 in ((-0.34, -0.40), (0.0, 0.0), (0.34, 0.40)):
        samples = []
        for k in range(11):
            t = k / 10.0
            x = x0 + (x1 - x0) * t
            z = -0.42 + 0.92 * t
            hit = tree.ray_cast(to_blender((x, 3.0, z)), Vector((0.0, 0.0, -1.0)))
            if hit[0] is None:
                continue
            samples.append((from_blender(hit[0]), from_blender(hit[1])))
        for (p0, n0), (p1, n1) in zip(samples, samples[1:]):
            along = (p1 - p0).normalized()
            for_width = Vector((along.z, 0.0, -along.x)).normalized() * 0.028 if abs(along.y) < 0.99 else Vector((0.028, 0.0, 0.0))
            raise_by = 0.012
            quad = [p0 - for_width + n0 * raise_by, p1 - for_width + n1 * raise_by, p1 + for_width + n1 * raise_by, p0 + for_width + n0 * raise_by]
            bm.faces.new([bm.verts.new(to_blender(p)) for p in quad]).smooth = True
    mesh = bpy.data.meshes.new("stitches")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def bmesh_of(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    return bm


def main():
    options = arguments()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    glove, ink, band = material("glove", WHITE, 0.62), material("ink", INK, 0.5), material("band", ACCENT, 0.4)
    skin = weld_and_smooth(hand_mesh())
    parts = [object_of("Hand", skin, glove)]
    parts.append(object_of("Cuff", cuff_mesh(), ink))
    parts.append(object_of("Band", band_mesh(), band))
    parts.append(object_of("Stitches", stitch_mesh(skin), ink))
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in parts)
    folder = os.path.dirname(os.path.abspath(options.out))
    os.makedirs(folder, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(options.out), export_format="GLB", export_yup=True, export_apply=True, export_cameras=False, export_lights=False, use_selection=True)
    print(f"HAND_GLOVE wrote {options.out} ({os.path.getsize(options.out) // 1024} KB), {len(skin.polygons)} faces in the glove")


main()
