"""Create an editable, compact game caliper. Run in isolated Blender background."""
import bpy
import math
from mathutils import Vector
from pathlib import Path

root = Path.cwd()
out = root / 'assets/3d/imported'
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat

body = material('Graphite painted aluminium', (0.09, 0.105, 0.12), .72, .28)
steel = material('Machined fasteners', (.46, .49, .52), .85, .28)
pad = material('Brake pad material', (.12, .105, .085), .05, .7)
rubber = material('Bleeder cap', (.025, .027, .03), 0, .65)
accent = material('Cast face detail', (.17, .19, .21), .65, .35)

parts = []
def finish(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj

def beveled_box(name, center, size, mat, bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new('Edge highlights', 'BEVEL')
    mod.width = bevel
    mod.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, mat)

def shell(name, y):
    # Silhouette of a two-piston opposed caliper, with rounded shoulders.
    outline = [(-.84,-.23),(-.78,.20),(-.59,.40),(-.28,.43),(-.12,.34),
               (.16,.34),(.30,.43),(.61,.42),(.78,.27),(.83,-.23),(.68,-.38),(-.68,-.38)]
    depth = .20
    vertices = [(x, y + dy, z) for dy in (-depth/2, depth/2) for x,z in outline]
    n=len(outline)
    faces = [tuple(range(n-1,-1,-1)), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    mod=obj.modifiers.new('Rounded housing edges','BEVEL')
    mod.width=.065
    mod.segments=2
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj,name,body)

def cylinder(name, center, radius, depth, mat, axis='Y', vertices=12):
    rotation=(math.pi/2,0,0) if axis=='Y' else (0,0,0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=center, rotation=rotation)
    obj=bpy.context.object
    return finish(obj,name,mat)

shell('Outer housing', -.25)
shell('Inner housing', .25)
beveled_box('Upper bridge', (0,0,.31), (1.35,.54,.16), body, .045)
for y in [-.125,.125]:
    beveled_box('Friction pad', (0,y,-.12), (1.25,.045,.34), pad, .025)
for x in [-.48,.46]:
    cylinder('Piston cover', (x,-.37,.03), .235,.045, accent, vertices=16)
    cylinder('Cover fastener', (x,-.405,.03), .073,.04, steel, vertices=8)
for x in [-.7,.68]:
    cylinder('Housing bolt', (x,-.365,.23), .085,.075, steel, vertices=8)
    cylinder('Mount lug', (x,.02,.37), .14,.52, body, vertices=12)
    cylinder('Mount bolt', (x,-.26,.37), .055,.04, steel, vertices=8)
cylinder('Hydraulic inlet', (.49,.02,.47), .10,.25, steel, axis='Z', vertices=12)
cylinder('Bleeder nipple', (.17,.05,.47), .06,.20, steel, axis='Z', vertices=10)
cylinder('Bleeder cap', (.17,.05,.59), .075,.07, rubber, axis='Z', vertices=10)

# The model spans 1.66 scene units across its long axis; the pad gap is .205.
triangles = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in parts)
print('CALIPER_TRIANGLES', triangles, 'OBJECTS', len(parts))
bpy.ops.object.select_all(action='DESELECT')
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.export_scene.gltf(filepath=str(out/'caliper_simple.glb'), export_format='GLB', use_selection=True)

# An isolated Blender preview; camera and lighting are kept in the editable file.
world=bpy.context.scene.world
world.color=(.09,.10,.12)
bpy.ops.object.camera_add(location=(3.2,-6.6,3.1))
camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,.02))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
camera.data.ortho_scale=3.0
bpy.context.scene.camera=camera
for name,loc,energy,size in [('Key',(1,-4,5),600,4),('Fill',(-4,-1,2),400,4),('Rim',(1,4,3),500,3)]:
    bpy.ops.object.light_add(type='AREA', location=loc)
    lamp=bpy.context.object
    lamp.name=name
    lamp.data.energy=energy
    lamp.data.shape='DISK'
    lamp.data.size=size
    lamp.rotation_euler=(-lamp.location).to_track_quat('-Z','Y').to_euler()
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=32
scene.render.resolution_x=1200
scene.render.resolution_y=800
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(root/'tools/diagnostics/out/caliper_simple_blender.png')
bpy.ops.wm.save_as_mainfile(filepath=str(out/'caliper_simple.blend'))
bpy.ops.render.render(write_still=True)
