# rbx_pipeline.py — RBlox Asset Pipeline (Blender headless, siap MCP/AI)
#
# Otomatisasi "Roblox Modern": import GLB hasil AI generator (Meshy/Tripo/CSM)
# → decimate ke budget tris → bevel otomatis sudut tajam (plastik Roblox)
# → material dasar → pivot dasar-tengah + fit ke unit grid → audit budget
# → export GLB siap import Godot/RBlox.
#
# Pakai (CLI):
#   blender --background --python rbx_pipeline.py -- \
#       --input raw_sword.glb --output sword_game.glb \
#       --category small_prop --bevel 0.02 --color "#8f9aa6"
#
# Pakai (GLM + MCP): agent menjalankan command di atas via tool eksekusi
# shell/Blender-MCP, lalu membaca baris "RBX_REPORT {...}" (JSON) dari stdout
# untuk keputusan lanjut (lolos budget atau perlu decimate ulang).
#
# Kategori budget (triangles) = docs/PERFORMANCE.md:
#   avatar 5000 | npc 2500 | hero_prop 4000 | small_prop 1000 | environment 500

import argparse
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

RBLOX_BUDGETS = {
    "avatar": 5000,
    "npc": 2500,
    "hero_prop": 4000,
    "small_prop": 1000,
    "environment": 500,
}


# ------------------------------------------------------------- helpers ----

def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser(description="RBlox asset pipeline")
    p.add_argument("--input", required=True, help="GLB/FBX/OBJ mentah dari AI")
    p.add_argument("--output", required=True, help="path output .glb")
    p.add_argument("--category", default="small_prop", choices=sorted(RBLOX_BUDGETS),
                   help="kategori budget polygon RBlox")
    p.add_argument("--decimate", type=float, default=0.0,
                   help="ratio decimate 0.1-1.0; 0 = otomatis ke budget")
    p.add_argument("--bevel", type=float, default=0.02,
                   help="lebar bevel (unit Blender); 0 = tanpa bevel")
    p.add_argument("--segments", type=int, default=2, help="segmen bevel")
    p.add_argument("--angle", type=float, default=40.0,
                   help="batas sudut tajam (derajat) untuk bevel & auto-smooth")
    p.add_argument("--color", default="#9aa0a6", help="warna dasar hex")
    p.add_argument("--roughness", type=float, default=0.9)
    p.add_argument("--metallic", type=float, default=0.0)
    p.add_argument("--material", default="rbx_plastic", help="nama material")
    p.add_argument("--fit", type=float, default=0.0,
                   help="skala seragam agar dimensi terbesar = N unit; 0 = off")
    p.add_argument("--grid", type=float, default=0.25,
                   help="snap pivot lokasi ke kelipatan grid ini")
    p.add_argument("--no-join", action="store_true",
                   help="jangan gabungkan mesh hasil import jadi satu objek")
    return p.parse_args(argv)


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def import_any(path):
    lower = path.lower()
    if lower.endswith((".glb", ".gltf")):
        bpy.ops.import_scene.gltf(filepath=path)
    elif lower.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    elif lower.endswith(".obj"):
        bpy.ops.import_scene.obj(filepath=path)
    else:
        raise ValueError("format tidak didukung: %s" % path)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def apply_modifier(obj, mod_name):
    with bpy.context.temp_override(object=obj, active_object=obj,
                                   selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=mod_name)


def mesh_tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def shade_auto_smooth(obj, angle_deg):
    data = obj.data
    if hasattr(data, "use_auto_smooth"):          # Blender <= 4.0
        data.use_auto_smooth = True
        data.auto_smooth_angle = math.radians(angle_deg)
        return
    try:                                          # Blender >= 4.1
        select_only([obj])
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle_deg))
        return
    except Exception:
        pass
    with bpy.context.temp_override(object=obj, active_object=obj,
                                   selected_objects=[obj]):
        bpy.ops.object.shade_smooth()


def hex_to_rgba(hexstr):
    h = hexstr.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


def make_material(name, color, roughness, metallic):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hex_to_rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


# ---------------------------------------------------------------- steps ----

def step_decimate(objs, ratio_mode, budget):
    """ratio_mode: 0 = otomatis (turunkan hingga ~budget), else ratio manual."""
    for obj in objs:
        tris = mesh_tris(obj)
        if ratio_mode <= 0.0:
            if tris <= budget:
                continue
            ratio = max(0.1, min(0.95, budget * 1.1 / float(tris)))
        else:
            ratio = min(1.0, ratio_mode)
            if ratio >= 0.999:
                continue
        mod = obj.modifiers.new("RBX_Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        apply_modifier(obj, mod.name)


def step_bevel(objs, width, segments, angle_deg):
    if width <= 0.0:
        return
    for obj in objs:
        mod = obj.modifiers.new("RBX_Bevel", "BEVEL")
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(angle_deg)
        mod.width = width
        mod.segments = max(1, segments)
        mod.miter_outer = "MITER_ARC"
        apply_modifier(obj, mod.name)


def step_material(objs, mat):
    for obj in objs:
        if obj.data.materials:
            obj.data.materials[0] = mat
        else:
            obj.data.materials.append(mat)


def step_fit(objs, target):
    """Skala seragam agar dimensi terbesar gabungan mesh = target unit."""
    if target <= 0.0:
        return
    apply_transforms(objs, rotation_scale_only=True)
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    for obj in objs:
        for corner in obj.bound_box:
            wc = obj.matrix_world @ Vector(corner)
            mn = Vector(map(min, mn, wc))
            mx = Vector(map(max, mx, wc))
    dims = mx - mn
    largest = max(dims.x, dims.y, dims.z)
    if largest <= 0.0:
        return
    scale = target / largest
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(scale=True)
    for obj in objs:
        obj.scale = (scale, scale, scale)
        bpy.ops.object.transform_apply(scale=True)


def apply_transforms(objs, rotation_scale_only=True):
    select_only(objs)
    bpy.ops.object.transform_apply(
        location=False, rotation=True, scale=True)


def step_origin_grid(objs, grid):
    """Pivot ke dasar-tengah bbox lalu snap lokasi ke kelipatan grid."""
    for obj in objs:
        bb = obj.bound_box
        xs = [c[0] for c in bb]
        ys = [c[1] for c in bb]
        zs = [c[2] for c in bb]
        cx = (min(xs) + max(xs)) * 0.5
        cy = (min(ys) + max(ys)) * 0.5
        obj.data.transform(Matrix.Translation(Vector((-cx, -cy, -min(zs)))))
        obj.location = (0.0, 0.0, 0.0)
    for obj in objs:
        obj.location = Vector(
            round(v / grid) * grid for v in obj.location) if grid > 0 else obj.location


# ----------------------------------------------------------------- main ----

def main():
    args = parse_args()
    budget = RBLOX_BUDGETS[args.category]

    clean_scene()
    objs = import_any(args.input)
    if not objs:
        print("RBX_REPORT " + json.dumps({"error": "no mesh imported"}))
        sys.exit(1)

    if not args.no_join and len(objs) > 1:
        select_only(objs)
        bpy.ops.object.join()
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    apply_transforms(objs)

    tris_before = sum(mesh_tris(o) for o in objs)
    step_decimate(objs, args.decimate, budget)
    step_bevel(objs, args.bevel, args.segments, args.angle)
    for o in objs:
        shade_auto_smooth(o, args.angle)
    step_fit(objs, args.fit)
    step_origin_grid(objs, args.grid)
    step_material(objs, make_material(
        args.material, args.color, args.roughness, args.metallic))

    tris_after = sum(mesh_tris(o) for o in objs)
    bpy.ops.export_scene.gltf(
        filepath=args.output, export_format="GLB",
        export_apply=True, export_yup=True)

    report = {
        "input": args.input,
        "output": args.output,
        "category": args.category,
        "budget": budget,
        "tris_before": tris_before,
        "tris_after": tris_after,
        "within_budget": tris_after <= budget,
        "objects": len(objs),
        "material": args.material,
    }
    print("RBX_REPORT " + json.dumps(report, indent=None))
    sys.exit(0 if report["within_budget"] else 2)


if __name__ == "__main__":
    main()
