"""Shared helpers for the rover kit part generators (see tools/blender/ROVER_KIT.md).

Run part scripts headless from the repo root, e.g.:
    blender -b --factory-startup -P tools/blender/scripts/make_wheel.py
Previews go to tools/blender/previews/<part>/ unless `-- --previews <dir>` or `-- --no-previews`.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PARTS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "parts")
EXPORT_DIR = os.path.join(REPO_ROOT, "game", "res", "models", "rover_kit")
# Preview renders, one folder per part (git-ignored)
PREVIEWS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "previews")

# ROVER_KIT.md 6.3. The only four materials allowed in the kit.
PALETTE = {
    "rover_body": "E6E2D8",
    "rover_metal": "4A4D52",
    "rover_dark": "1C1D20",
    "rover_gold": "C9A227",
}
# Lighter stand-ins used only while rendering previews, so dark parts show their shape.
PREVIEW_COLORS = {
    "rover_body": "F2F0EA",
    "rover_metal": "9DA3AB",
    "rover_dark": "5A5D63",
    "rover_gold": "E0B83A",
}
MATERIAL_SETTINGS = {
    "rover_body": (0.0, 0.6),
    "rover_metal": (0.6, 0.45),
    "rover_dark": (0.0, 0.8),
    "rover_gold": (0.9, 0.35),
}


def script_args() -> list:
    """Arguments after `--` on the Blender command line."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def preview_dir(part: str):
    """Preview folder from the command line: default tools/blender/previews/<part>/,
    `--previews DIR` to override, `--no-previews` to skip (returns None)."""
    args = script_args()
    if "--no-previews" in args:
        return None
    path = args[args.index("--previews") + 1] if "--previews" in args else os.path.join(PREVIEWS_DIR, part)
    os.makedirs(path, exist_ok=True)
    return path


def srgb_to_linear(hex_color: str) -> tuple:
    def channel(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    rgb = [int(hex_color[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(channel(c) for c in rgb) + (1.0,)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def get_material(name: str) -> bpy.types.Material:
    """Creates (or returns) one of the four kit materials."""
    if name not in PALETTE:
        raise ValueError("Not a rover kit material: " + name)
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    color = srgb_to_linear(PALETTE[name])
    metallic, roughness = MATERIAL_SETTINGS[name]
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    material.diffuse_color = color  # viewport / workbench colour
    material.metallic = metallic
    material.roughness = roughness
    return material


def set_preview_colors(enabled: bool) -> None:
    source = PREVIEW_COLORS if enabled else PALETTE
    for name in PALETTE:
        material = bpy.data.materials.get(name)
        if material:
            material.diffuse_color = srgb_to_linear(source[name])


def mesh_object(name: str, bm: bmesh.types.BMesh, materials: list) -> bpy.types.Object:
    """Creates a flat-shaded mesh object from a bmesh (which is freed)."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    for material in materials:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def triangle_count(obj: bpy.types.Object) -> int:
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def mirror_bmesh_x(bm: bmesh.types.BMesh) -> None:
    """Mirrors geometry across the YZ plane in place (for _L from _R) and fixes the winding."""
    bmesh.ops.scale(bm, vec=(-1.0, 1.0, 1.0), verts=bm.verts)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)


def make_collision_child(parent: bpy.types.Object, bm: bmesh.types.BMesh) -> bpy.types.Object:
    """Adds the `<part>-convcolonly` collision mesh (ROVER_KIT.md 7) as a child of the part root."""
    obj = mesh_object(parent.name + "-convcolonly", bm, [])
    obj.parent = parent
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


def export_part(root: bpy.types.Object, path: str) -> None:
    """Exports the part root and its children as GLB with the root at the origin, as
    swappable parts are instanced on their own (ROVER_KIT.md 8)."""
    saved_location = root.location.copy()
    root.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root

    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_animations=False,
        export_materials="EXPORT",
    )
    root.location = saved_location
    bpy.context.view_layer.update()


def save_blend(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def render_view(target: bpy.types.Object, path: str, direction: tuple, ortho_scale: float,
                perspective: bool = False, distance: float = 1.0, focus: tuple = (0.0, 0.0, 0.0),
                size: int = 640) -> None:
    """Renders `target` alone with Workbench from `direction` (a vector from the target
    toward the camera). Orthographic views fit `ortho_scale` metres; perspective views sit
    `distance` metres away, aimed at `focus` (an offset from the target's origin).
    World +Z is up in the image (+Y for straight-down views).
    Backface culling is on, so flipped normals show as holes."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_backface_culling = True
    shading.show_cavity = True
    shading.cavity_type = "WORLD"
    shading.show_object_outline = True
    shading.show_specular_highlight = True
    shading.background_type = "VIEWPORT"
    shading.background_color = (0.82, 0.84, 0.88)

    others = [o for o in scene.objects if o.type == "MESH" and o != target and o.parent != target]
    saved = {o: o.hide_render for o in others}
    for o in others:
        o.hide_render = True

    camera_data = bpy.data.cameras.new("preview_camera")
    camera = bpy.data.objects.new("preview_camera", camera_data)
    scene.collection.objects.link(camera)
    center = target.matrix_world.translation + Vector(focus)
    view = Vector(direction).normalized()
    location = center + view * (distance if perspective else 2.0)
    # The camera looks down its -Z with +Y as image up: aim it at the target, world +Z up
    forward = -view
    up_hint = Vector((0.0, 0.0, 1.0)) if abs(view.z) < 0.99 else Vector((0.0, 1.0, 0.0))
    right = forward.cross(up_hint).normalized()
    up = right.cross(forward)
    camera.matrix_world = Matrix((
        (right.x, up.x, -forward.x, location.x),
        (right.y, up.y, -forward.y, location.y),
        (right.z, up.z, -forward.z, location.z),
        (0.0, 0.0, 0.0, 1.0),
    ))
    if perspective:
        camera_data.type = "PERSP"
        camera_data.lens = 85.0
    else:
        camera_data.type = "ORTHO"
        camera_data.ortho_scale = ortho_scale
    scene.camera = camera

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

    bpy.data.objects.remove(camera)
    bpy.data.cameras.remove(camera_data)
    for o, hidden in saved.items():
        o.hide_render = hidden


def polar(r: float, phi: float) -> tuple:
    """(y, z) on a circle around the X axis. phi = 90 degrees is the top (+Z)."""
    return (r * math.cos(phi), r * math.sin(phi))
