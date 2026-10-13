"""Build Ari from the local MPFB CC0 base, without modifying its source project.

Run with Blender 5.2 --background --python this_file -- OUTPUT_DIRECTORY.
Requires the installed MPFB extension and the source paths recorded below.
"""
import importlib.util
import sys
import math
import json
import hashlib
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

SOURCE = Path(r'C:/repos/HumanLife2/tools/build_human.py')
BUNDLE = Path(r'C:/repos/MediEvalBattle/external/makehuman-assets')
OUT = Path(sys.argv[sys.argv.index('--') + 1])
OUT.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('source_builder', SOURCE)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
base.OUTPUT_GLB = OUT / 'ari.glb'
base.PREVIEW_PNG = OUT / 'ari.png'
base.clear_scene()
# Keep the exposed legs when the original trousers become shorts. The helper
# mask is still baked; clothes deletion masks are removed before body export.
original_bake = base.ExportService.bake_modifiers_remove_helpers
def bake(body, **kwargs):
    for mod in list(body.modifiers):
        if mod.type == 'MASK' and 'shoe' in mod.vertex_group.lower():
            group = body.vertex_groups.get(mod.vertex_group)
            for v in body.data.vertices:
                if v.co.z > .09:
                    group.add([v.index], 0 if mod.invert_vertex_group else 1, 'REPLACE')
            continue
        if mod.type == 'MASK' and mod.vertex_group != 'body' and 'shoe' not in mod.vertex_group.lower():
            group = body.vertex_groups.get(mod.vertex_group)
            for v in body.data.vertices:
                co = v.co.copy()
                if body.data.shape_keys:
                    keys = body.data.shape_keys.key_blocks
                    for key in list(keys)[1:]:
                        co += (key.data[v.index].co - keys[0].data[v.index].co) * key.value
                if co.z < .67:
                    group.add([v.index], 0 if mod.invert_vertex_group else 1, 'REPLACE')
    return original_bake(body, **kwargs)
base.ExportService.bake_modifiers_remove_helpers = bake
body, old_rig, meshes = base.build_character()
outfit = bpy.data.objects['CasualOutfit']
bm = bmesh.new()
bm.from_mesh(outfit.data)
bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces), plane_co=(0,0,.66), plane_no=(0,0,1), clear_inner=True)
bm.to_mesh(outfit.data)
bm.free()
outfit.name = 'FootballKit'
for v in outfit.data.vertices:
    v.co += v.normal * .02
base.assign_outfit_materials(outfit, bpy.data.materials['TShirt'], bpy.data.materials['Denim'])
for face in outfit.data.polygons:
    face.material_index = 0 if face.center.z > .97 else 1
bpy.data.materials['TShirt'].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.045, .27, .58, 1)
bpy.data.materials['Denim'].name = 'FootballShorts'
sock = base.make_material('FootballSocks', (.82, .89, .93, 1), .8)
shoes = bpy.data.objects['Shoes']
shoes.data.materials.append(sock)
for face in shoes.data.polygons:
    if sum(shoes.data.vertices[i].co.z for i in face.vertices) / len(face.vertices) > .11:
        face.material_index = len(shoes.data.materials) - 1
if body.data.shape_keys:
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
bm = bmesh.new()
bm.from_mesh(body.data)
for z in (.09,.45):
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces), plane_co=(0,0,z), plane_no=(0,0,1))
bm.to_mesh(body.data)
bm.free()
body.data.materials.append(sock)
for face in body.data.polygons:
    z = sum(body.data.vertices[i].co.z for i in face.vertices) / len(face.vertices)
    if .09 < z < .45:
        face.material_index = len(body.data.materials) - 1

# Collapse finger weights into the forearm while preserving their sculpted
# shape. Bake each major segment into the game's actual contact-anchor rest.
# A shared weighted deformation, rather than disconnected body primitives,
# retains blended knees/elbows and continuous anatomy.
positions = [(0,0,0),(0,.88,0),(0,1.52,0),(-.105,.88,0),(-.105,.47,0),(-.105,.13,0),(.105,.88,0),(.105,.47,0),(.105,.13,0),(-.245,1.4,0),(-.28535,1.13303,0),(.245,1.4,0),(.28535,1.13303,0)]
C = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1))) # Godot to Blender
rests = []
for i, p in enumerate(positions):
    rot = Matrix.Rotation(-.15 if i in (9,10) else .15 if i in (11,12) else 0, 4, 'Z')
    rests.append(C @ Matrix.Translation(Vector(p)) @ rot)
major = {'Root':0,'pelvis':1,'spine_01':1,'spine_02':1,'spine_03':1,'neck_01':2,'head':2,'thigh_l':3,'calf_l':4,'foot_l':5,'ball_l':5,'thigh_r':6,'calf_r':7,'foot_r':8,'ball_r':8,'upperarm_l':9,'lowerarm_l':10,'upperarm_r':11,'lowerarm_r':12,'clavicle_r':1,'clavicle_l':1}
source_names = ['Root','pelvis','head','thigh_l','calf_l','foot_l','thigh_r','calf_r','foot_r','upperarm_l','lowerarm_l','upperarm_r','lowerarm_r']
transforms = []
for i, name in enumerate(source_names):
    bone = old_rig.data.bones[name]
    # Orient the original long-bone axis to the target downward limb direction.
    direction = Vector((0,-1,0)) if i >= 3 and i not in (5,8) else Vector((0,1,0))
    if i in (1,2,5,8):
        rotation = Matrix.Rotation(math.pi, 4, 'Z')
    elif i == 0:
        rotation = Matrix.Rotation(math.pi, 4, 'Z')
    else:
        target = rests[i].to_3x3() @ direction
        facing = Matrix.Rotation(math.pi, 4, 'Z')
        rotation = (facing.to_3x3() @ (bone.tail_local - bone.head_local)).rotation_difference(target).to_matrix().to_4x4() @ facing
    transforms.append(Matrix.Translation(rests[i].translation) @ rotation @ Matrix.Translation(-bone.head_local))
for bone in old_rig.data.bones:
    if bone.name not in major:
        major[bone.name] = 10 if bone.name.endswith('_l') else 12

data = bpy.data.armatures.new('ContactAnchorRig')
rig = bpy.data.objects.new('AriRig', data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for i in range(13):
    b = data.edit_bones.new('A' + str(i))
    b.matrix = rests[i]
    b.length = .05
    if i:
        b.parent = data.edit_bones['A0']
bpy.ops.object.mode_set(mode='OBJECT')
vertices = 0
for obj in meshes:
    if obj.data.shape_keys:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    names = {g.index:g.name for g in obj.vertex_groups}
    weights = []
    for v in obj.data.vertices:
        combined = {}
        for g in v.groups:
            name = names[g.group]
            if name in major:
                i = major[name]
                combined[i] = combined.get(i,0) + g.weight
        total = sum(combined.values())
        combined = {i:w/total for i,w in combined.items()} if total else {1:1}
        # Shoes and the exposed ankle must share the same foot deformation.
        # Imported toe/calf mixtures separated them during physical falls.
        if obj.name in ('Shoes', 'HumanBody') and v.co.z < .12:
            combined = {5 if v.co.x > 0 else 8:1}
        if obj.name == 'Shoes':
            v.co += v.normal * .004
        v.co = sum((transforms[i] @ v.co * w for i,w in combined.items()), Vector())
        weights.append(combined)
    for mod in list(obj.modifiers):
        obj.modifiers.remove(mod)
    obj.vertex_groups.clear()
    groups = [obj.vertex_groups.new(name='A'+str(i)) for i in range(13)]
    for v, combined in zip(obj.data.vertices, weights):
        for i,w in combined.items():
            groups[i].add([v.index], w, 'REPLACE')
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)
    mod = obj.modifiers.new('FootballSkin','ARMATURE')
    mod.object = rig
    vertices += len(obj.data.vertices)
    obj.data.update()
bpy.data.objects.remove(old_rig, do_unlink=True)
# Embedded, deterministic cloth weave. Generated locally; no provider cost.
y,x = np.mgrid[0:2048,0:2048]
weave = 1 + .025 * np.sin(x * math.pi / 2) * np.cos(y * math.pi / 2)
for name, color in [('TShirt',(1,1,1)),('FootballShorts',(1,1,1))]:
    image = bpy.data.images.new(name+'Weave', width=2048, height=2048)
    pixels = np.ones((2048,2048,4),dtype=np.float32)
    pixels[:,:,:3] = weave[:,:,None] * np.array(color)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(OUT / (name+'.png'))
    image.file_format = 'PNG'
    image.save()
    material = bpy.data.materials[name]
    tex = material.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    material.node_tree.links.new(tex.outputs['Color'], material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
base.export_glb(rig, meshes)
base.add_preview_stage()
camera = bpy.context.scene.camera
camera.location.x *= -1
camera.location.y *= -1
camera.rotation_euler = (Vector((0,0,.94)) - camera.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'ari.blend'))
base.render_preview()
(OUT / 'provenance.json').write_text(json.dumps({'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'asset_bundle':str(BUNDLE),'license':'CC0-1.0','license_url':'https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md','transformations':['football kit and exposed leg masks','weighted contact-anchor rest retarget','13 deformation bones; sculpted fingers'],'vertices':vertices}, indent=2))
print('ARI_EXPORT=' + str(OUT / 'ari.glb'))
