"""Rebuild the P6 ruins kit in a private background Blender process.

Run: blender --background --factory-startup --python tools/build_environment_assets.py
All authored locations use Godot coordinates (X right, Y up, -Z north).
No generated object supplies collision or navigation geometry.
"""

import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "godot/assets/models/environment"
SOURCE = ROOT / "blender/environments"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)

# This process starts with factory startup; never touch the interactive scene.
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
bpy.context.preferences.filepaths.save_version = 0
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE"
scene.world.color = (0.16, 0.20, 0.27)


def xyz(v):
    return (v[0], -v[2], v[1])


def material(name, color, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    if not mat.use_nodes:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.95
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


stone = material("RuinStone", (0.25, 0.34, 0.42))
stone_alt = material("RuinStoneAlt", (0.28, 0.37, 0.44))
dark = material("RuinDark", (0.075, 0.12, 0.18))
edge = material("RuinEdge", (0.43, 0.52, 0.58))
inlay = material("RuinInlay", (0.12, 0.35, 0.39), 0.05)
crystal_mat = material("CrystalCyan", (0.12, 0.73, 0.78), 0.30)
gold = material("RuinBronze", (0.44, 0.39, 0.27))
groups = {}


def remember(obj, group, mat):
    obj.data.materials.append(mat)
    groups.setdefault(group, []).append(obj)
    return obj


def box(name, center, size, mat=stone, bevel=0.02, group="Walls"):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(center))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new("CarvedEdges", "BEVEL")
        modifier.width = min(bevel, min(size) * 0.24)
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return remember(obj, group, mat)


def cylinder(name, center, radius, depth, mat, vertices=8, group="Pillars"):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                      location=xyz(center), rotation=(0, 0, math.pi / 8))
    obj = bpy.context.object
    obj.name = name
    return remember(obj, group, mat)


def crystal(name, center, radius, height, mat=crystal_mat, group="Crystals"):
    # A hexagonal shaft with an asymmetric pointed termination.
    verts = []
    for y, r in [(0, radius * 0.78), (height * 0.64, radius)]:
        for i in range(6):
            a = math.tau * i / 6
            verts.append(xyz((center[0] + math.cos(a) * r,
                              center[1] + y,
                              center[2] + math.sin(a) * r)))
    verts.append(xyz((center[0] + radius * 0.25, center[1] + height,
                      center[2] - radius * 0.12)))
    faces = [tuple(range(6))]
    faces += [(i + 6, (i + 1) % 6 + 6, (i + 1) % 6, i) for i in range(6)]
    faces += [(12, 6 + (i + 1) % 6, 6 + i) for i in range(6)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return remember(obj, group, mat)


def ring(name, cx, cz, radius, width, mat, group="FloorInlay", segments=64):
    verts, faces = [], []
    for i in range(segments):
        a = math.tau * i / segments
        for r in (radius - width / 2, radius + width / 2):
            verts.append(xyz((cx + math.cos(a) * r, 0.009, cz + math.sin(a) * r)))
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((j * 2, j * 2 + 1, i * 2 + 1, i * 2))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return remember(obj, group, mat)


# Forty-metre tile floor. The physical floor remains exactly at y=0.
box("ENV_Ruins_FloorFoundation", (0, -0.51, 0), (40, 1, 40), dark, group="Floor")
for x in range(10):
    for z in range(10):
        box("ENV_Ruins_FloorTile", (-18 + x * 4, -0.045, -18 + z * 4),
            (3.975, 0.098, 3.975), stone if (x + z) % 3 else stone_alt,
            bevel=0.018, group="Floor")

# Quiet inlaid map language: no bright grid competing with orange danger zones.
ring("SealOuter", 0, 0, 6.8, 0.07, inlay)
ring("SealInner", 0, 0, 6.1, 0.035, edge)
ring("SealCore", 0, 0, 1.8, 0.05, inlay, segments=8)
for sign in (-1, 1):
    box("LongBorder", (sign * 17.6, 0.007, 0), (0.055, 0.006, 35.2), inlay,
        bevel=0, group="FloorInlay")
    box("CrossBorder", (0, 0.007, sign * 17.6), (35.2, 0.006, 0.055), inlay,
        bevel=0, group="FloorInlay")
for i in range(8):
    a = math.tau * i / 8
    obj = box("SealRadial", (math.cos(a) * 6.45, 0.007, math.sin(a) * 6.45),
              (0.50, 0.006, 0.08), edge, bevel=0, group="FloorInlay")
    obj.rotation_euler.z = -a

# Each wall keeps the original four-metre silhouette and exact collision extent.
for direction in range(4):
    def place(local):
        x, y, z = local
        for _ in range(direction):
            x, z = -z, x
        return x, y, z

    def wall_box(name, c, s, m=stone, b=0.02):
        dimensions = s if direction % 2 == 0 else (s[2], s[1], s[0])
        return box(name, place(c), dimensions, m, b)

    wall_box("WallBacking", (0, 2, -19.65), (40, 4, 0.7), dark)
    for col in range(10):
        x = -18 + col * 4
        for row in range(3):
            wall_box("ENV_Ruins_WallPanel_A", (x, 0.72 + row * 1.10, -19.25),
                     (3.92, 1.03, 0.49), stone if (col + row) % 3 else stone_alt)
        wall_box("CrownFrieze", (x, 3.80, -19.42), (3.96, 0.32, 0.83), edge, 0.035)
        wall_box("WallFooting", (x, 0.16, -19.45), (3.96, 0.30, 0.89), edge, 0.02)
    for col in range(9):
        x = -16 + col * 4
        wall_box("WallSpine", (x, 2.0, -19.15), (0.22, 3.46, 0.27), dark)
        wall_box("WallSpineCore", (x, 2.3, -19.007), (0.045, 1.2, 0.012), inlay, 0)
    # Crystals sit inside existing wall bounds, not on open walkable floor.
    for x in (-12, 12):
        crystal("ENV_Ruins_Crystal_A", place((x, 3.42, -19.48)), 0.19, 1.05)
        crystal("ENV_Ruins_Crystal_B", place((x + 0.27, 3.45, -19.48)), 0.11, 0.59)

# Exactly matching the two low blocks and large north-east platform.
for name, cx, cz, sx, sy, sz in [("LowBlock", -5, 0, 3, 1, 3),
                                 ("Step", 5, -0.5, 3, 1, 3),
                                 ("HighPlatform", 5, -4.5, 6, 2, 5)]:
    box("ENV_Ruins_" + name, (cx, sy / 2, cz), (sx, sy, sz), stone, 0.045,
        group="Platforms")
    box(name + "Top", (cx, sy - 0.025, cz), (sx - 0.04, 0.05, sz - 0.04),
        edge, 0.015, group="Platforms")
    for sign in (-1, 1):
        box(name + "Inset", (cx, sy * 0.58, cz + sign * (sz / 2 - 0.006)),
            (sx * 0.72, 0.085, 0.014), dark, 0, group="Platforms")
        box(name + "Glyph", (cx - sx * 0.24, sy * 0.58,
                              cz + sign * (sz / 2 + 0.002)),
            (0.07, 0.27, 0.008), inlay, 0, group="Platforms")

# Pillars have a square load-bearing volume matching the 1.5 x 5 x 1.5 collider.
# Corner facets, collars and cap fragments stay inside that horizontal footprint.
for side, x in (("West", -9), ("East", 9)):
    box("ENV_Ruins_Pillar_A_" + side, (x, 2.5, -7), (1.48, 5, 1.48), stone,
        0.13, group="Pillars")
    for y, h in ((0.18, 0.36), (1.35, 0.12), (3.55, 0.18), (4.80, 0.4)):
        box("PillarCollar", (x, y, -7), (1.5, h, 1.5), edge, 0.04, group="Pillars")
    box("PillarInset", (x, 2.5, -6.253), (0.52, 1.55, 0.012), dark, 0.002,
        group="Pillars")
    box("PillarGlyph", (x, 2.5, -6.244), (0.08, 1.18, 0.008), crystal_mat, 0,
        group="Pillars")
    crystal("PillarCrownCrystal", (x, 4.95, -7), 0.25, 0.85)
    crystal("PillarCrownShard", (x + 0.33, 4.95, -6.93), 0.11, 0.48)
    # Broken rim blocks are above existing tops; none enters the navigable plane.
    box("BrokenCap", (x - 0.38, 5.08, -7.35), (0.50, 0.18, 0.45), stone, 0.06,
        group="Pillars")

# Carved portal skin uses the existing z=-16 exit frame; opening stays 4.2 m.
for x in (-2.25, 2.25):
    box("ENV_Ruins_GatePost", (x, 2.5, -16), (0.30, 5, 0.50), dark,
        0.035, group="GateArch")
    box("GatePostInlay", (x, 2.5, -15.741), (0.08, 4.4, 0.012), inlay, 0,
        group="GateArch")
    crystal("GateFinial", (x, 4.93, -16), 0.17, 0.58, group="GateArch")
box("ENV_Ruins_GateLintel", (0, 5, -16), (4.8, 0.3, 0.50), stone, 0.04,
    group="GateArch")
box("GateCrest", (0, 5.22, -16), (0.72, 0.22, 0.50), gold, 0.035,
    group="GateArch")
crystal("GateCrestCrystal", (0, 5.28, -16), 0.16, 0.55, group="GateArch")

# Join by semantic module, preserving the material surfaces. This keeps the kit
# editable and import hierarchy small without baking material colors into textures.
root = bpy.data.objects.new("ENV_Ruins_Kit", None)
scene.collection.objects.link(root)
for name, objects in groups.items():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = "ENV_Ruins_" + name
    # Origins at zero make every module independently reusable at kit coordinates.
    scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.parent = root
    obj["visual_only"] = True

bpy.context.view_layer.update()
mesh_objects = [obj for obj in scene.objects if obj.type == "MESH"]
authored_materials = {stone, stone_alt, dark, edge, inlay, crystal_mat, gold}
for mat in list(bpy.data.materials):
    if mat not in authored_materials:
        bpy.data.materials.remove(mat, do_unlink=True)
for obj in mesh_objects:
    assert all(abs(value - 1) < 1e-5 for value in obj.scale), obj.name
    assert all(math.isfinite(v) for vertex in obj.data.vertices for v in vertex.co)
    assert len(obj.data.polygons) > 0


def godot_bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    values = [(p.x, p.z, -p.y) for p in points]
    return {"min": [round(min(v[i] for v in values), 5) for i in range(3)],
            "max": [round(max(v[i] for v in values), 5) for i in range(3)]}

glb_path = OUT / "ruins_kit.glb"
bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format="GLB",
                          export_yup=True, export_apply=True,
                          export_cameras=False, export_lights=False,
                          export_extras=True, export_animations=False)

# Preview-only camera and lights remain in the source file, excluded from GLB.
def aim(obj, target):
    obj.rotation_euler = (Vector(xyz(target)) - obj.location).to_track_quat("-Z", "Y").to_euler()

bpy.ops.object.camera_add(location=xyz((28, 26, 31)))
camera = bpy.context.object
camera.name = "PreviewCamera"
camera.data.type = "ORTHO"
camera.data.ortho_scale = 55
aim(camera, (0, 1, 0))
scene.camera = camera
for name, location, energy, size in [("PreviewKey", (0, 18, 4), 6500, 18),
                                     ("PreviewFill", (-15, 10, -10), 3500, 15)]:
    bpy.ops.object.light_add(type="AREA", location=xyz(location))
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    aim(light, (0, 0, 0))

scene.render.resolution_x = 1280
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
scene.render.filepath = str(SOURCE / "ruins_kit_preview.png")
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "ruins_kit.blend"))

manifest = {
    "units": "meters", "godot_up": "+Y", "godot_north": "-Z",
    "visual_only": True, "floor_top": 0.004, "inlay_top_max": 0.010,
    "mesh_modules": [obj.name for obj in mesh_objects],
    "bounds_godot": {obj.name: godot_bounds(obj) for obj in mesh_objects},
    "vertices": sum(len(obj.data.vertices) for obj in mesh_objects),
    "triangles": sum(sum(len(p.vertices) - 2 for p in obj.data.polygons) for obj in mesh_objects),
    "materials": [m.name for m in bpy.data.materials if m.users],
    "source": str(SOURCE / "ruins_kit.blend"), "export": str(glb_path),
    "geometry_unchanged": "Original arena colliders and navigation remain authoritative",
}
(SOURCE / "ruins_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print("ENVIRONMENT_ASSET_RESULT " + json.dumps(manifest))
bpy.ops.render.render(write_still=True)
