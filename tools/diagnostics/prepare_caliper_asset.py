"""Build a lighter game mesh from nika23's CC BY 4.0 KALIPER GLB.

Run with Blender in background mode from the project root. Keep the original
asset alongside the derivative for attribution and future editing.
"""
import bpy
from pathlib import Path

root = Path(bpy.path.abspath("//")) if bpy.data.filepath else Path.cwd()
source = root / "assets/3d/imported/kaliper_nika23.glb"
output = root / "assets/3d/imported/kaliper_nika23_mobile.glb"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(source))
for obj in list(bpy.data.objects):
    if obj.name.startswith("Text.001"):
        bpy.data.objects.remove(obj, do_unlink=True)
        continue
    if obj.type == "MESH":
        modifier = obj.modifiers.new("Mobile reduction", "DECIMATE")
        modifier.ratio = 0.25
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB")
print("Prepared", output)
