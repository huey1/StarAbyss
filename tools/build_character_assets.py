"""Rebuild the original Star Abyss P6 character library with local Blender.

Run: blender --background --factory-startup --python tools/build_character_assets.py
No external assets, operators, add-ons, textures or runtime dependencies are used.
Meters, Blender +Y forward / glTF-Godot -Z forward, stationary Root bone.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector, Matrix, Euler

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'godot/assets/models/characters'
OUT.mkdir(parents=True, exist_ok=True)
FPS = 100
MANIFEST = {'units': 'meters', 'blender_forward': '+Y', 'godot_forward': '-Z',
            'root_motion': 'stationary Root; controller provides all displacement',
            'weapon_direction': 'Godot -Z from grip origin', 'characters': {}, 'weapons': {}}


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for store in [bpy.data.meshes, bpy.data.armatures, bpy.data.materials]:
        for block in list(store):
            if block.users == 0:
                store.remove(block)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1.0


def material(name, color, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = .86
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return mat


def palette(enemy=False):
    return {
        'ink': material('abyss_ink', (.025, .048, .09)),
        'dark': material('midnight_fabric', (.075, .12, .20)),
        'stone': material('storm_blue_armor', (.19, .29, .39)),
        'light': material('ivory_armor', (.73, .82, .85)),
        'skin': material('warm_porcelain', (.94, .68, .51)),
        'hair': material('silver_hair', (.76, .86, .92)),
        'accent': material('amber_crystal' if enemy else 'star_cyan',
                           (.98, .30, .055) if enemy else (.04, .72, .83), .35),
        'gold': material('brushed_gold', (.81, .49, .15)),
        'eye': material('lit_amber' if enemy else 'lit_cyan',
                        (1, .52, .12) if enemy else (.10, .90, 1), 1.0),
    }


PARTS = []


def finish(obj, name, mat, bone=None, bevel=0):
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('crafted_edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    if bone:
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    PARTS.append(obj)
    return obj


def cube(name, pos, dims, mat, bone=None, bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.dimensions = dims
    return finish(obj, name, mat, bone, bevel)


def sphere(name, pos, size, mat, bone=None, seg=12, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=pos)
    obj = bpy.context.object
    obj.scale = size
    return finish(obj, name, mat, bone)


def cone(name, a, b, r1, r2, mat, bone=None, vertices=6):
    mid = (Vector(a) + Vector(b)) / 2
    delta = Vector(b) - Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2,
                                  depth=delta.length, location=mid)
    obj = bpy.context.object
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta)
    return finish(obj, name, mat, bone)


def custom(name, verts, faces, mat, bone=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, bone)


def ring_body(name, layers, mat, bone):
    verts = []
    n = 8
    for z, rx, ry, cy in layers:
        for i in range(n):
            a = math.tau * i / n + math.pi / 8
            verts.append((rx * math.cos(a), cy + ry * math.sin(a), z))
    faces = [tuple(reversed(range(n)))]
    for k in range(len(layers)-1):
        for j in range(n):
            a = k*n+j
            b = k*n+(j+1)%n
            faces.append((a,b,b+n,a+n))
    faces.append(tuple(range((len(layers)-1)*n,len(layers)*n)))
    return custom(name, verts, faces, mat, bone)


def make_rig(height, broad=1):
    s = height / 1.75
    arm = bpy.data.armatures.new('AbyssRig')
    rig = bpy.data.objects.new('Armature', arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    spec = {
        'Root': ((0,0,0),(0,0,.15),None),
        'Hips': ((0,0,.88),(0,0,1.03),'Root'),
        'Spine': ((0,0,1.03),(0,0,1.26),'Hips'),
        'Chest': ((0,0,1.26),(0,0,1.43),'Spine'),
        'Head': ((0,0,1.43),(0,0,1.70),'Chest'),
    }
    for side, x in [('R',1),('L',-1)]:
        spec[f'UpperArm_{side}'] = ((x*.24*broad,0,1.37),(x*.35*broad,0,1.11),'Chest')
        spec[f'Forearm_{side}'] = ((x*.35*broad,0,1.11),(x*.39*broad,.035,.91),f'UpperArm_{side}')
        spec[f'Hand_{side}'] = ((x*.39*broad,.035,.91),(x*.39*broad,.075,.83),f'Forearm_{side}')
        spec[f'Thigh_{side}'] = ((x*.115,0,.90),(x*.13,0,.50),'Hips')
        spec[f'Shin_{side}'] = ((x*.13,0,.50),(x*.13,0,.12),f'Thigh_{side}')
        spec[f'Foot_{side}'] = ((x*.13,0,.12),(x*.13,.18,.08),f'Shin_{side}')
    # A Blender +Z bone becomes a Godot +Y bone with identity global rest
    # rotation. This keeps the weapon's exported -Z direction forward when a
    # BoneAttachment3D instantiates it with identity local transform.
    spec['WeaponSocket'] = ((.39*broad,.075,.87),(.39*broad,.075,1.045),'Hand_R')
    for name,(head,tail,parent) in spec.items():
        b=arm.edit_bones.new(name)
        b.head=Vector(head)*s
        b.tail=Vector(tail)*s
        if parent:
            b.parent=arm.edit_bones[parent]
        b.use_deform=name!='Root' and name!='WeaponSocket'
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.select_set(False)
    return rig,s


def player(rig,s,p):
    # Tailored explorer silhouette: split coat, tall boots, asymmetric cape,
    # layered silver fringe and a faceted star clasp instead of generic boxes.
    ring_body('Explorer_tunic',[(.88,.17,.12,0),(1.03,.19,.13,0),(1.28,.24,.145,0),(1.40,.21,.12,0)],p['dark'],'Chest')
    ring_body('Coat_waist',[(.72,.235,.15,-.015),(.95,.20,.14,-.015),(1.03,.18,.13,0)],p['stone'],'Hips')
    cube('Utility_belt',(0,.005,.98),(.39,.29,.065),p['ink'],'Hips')
    cube('Gold_buckle',(0,.159,.98),(.065,.025,.052),p['gold'],'Hips')
    for x in [-1,1]:
        custom('Coat_lapel',[(x*.025,.149,1.09),(x*.055,.17,1.37),(x*.19,.135,1.38),(x*.13,.158,1.17)],[(0,1,2,3)],p['light'],'Chest')
        cube('Coat_tail',(x*.15,-.09,.73),(.16,.08,.40),p['stone'],'Hips').rotation_euler[1]=x*-.12
    # Neck and head have clear face plane looking Blender +Y.
    cone('Neck',(0,0,1.39),(0,0,1.49),.065,.065,p['skin'],'Head',8)
    sphere('Face',(0,.015,1.575),(.135,.117,.157),p['skin'],'Head')
    sphere('Hair_cap',(0,-.018,1.645),(.145,.124,.112),p['hair'],'Head')
    for i,(x,z,l) in enumerate([(-.11,1.70,.13),(-.055,1.72,.18),(.005,1.725,.12),(.065,1.71,.15),(.115,1.68,.11)]):
        cone('Silver_fringe_'+str(i),(x,.075,z),(x-.028,.137,z-l),.055,.006,p['hair'],'Head',5)
    for x in [-1,1]:
        cone('Hair_side',(x*.125,-.01,1.65),(x*.13,.015,1.46),.059,.009,p['hair'],'Head',5)
        cube('Eye_ink',(x*.052,.123,1.587),(.051,.013,.029),p['ink'],'Head',.002)
        cube('Eye_cyan',(x*.049,.132,1.586),(.026,.008,.019),p['eye'],'Head',0)
        cube('Brow',(x*.051,.128,1.615),(.052,.01,.012),p['dark'],'Head',0).rotation_euler[1]=x*-.09
    cone('Nose',(0,.117,1.57),(0,.151,1.557),.014,.003,p['skin'],'Head',4)
    cube('Mouth',(0,.122,1.52),(.031,.009,.006),p['dark'],'Head',0)
    ring_body('Scarf_collar',[(1.40,.13,.12,0),(1.46,.135,.13,0)],p['accent'],'Chest')
    custom('Scarf_tail',[(-.11,-.125,1.43),(.10,-.125,1.43),(.17,-.22,.98),(-.02,-.24,1.03),(-.08,-.23,.94)],[(0,1,2,3,4)],p['accent'],'Chest')
    cone('Star_clasp',(.13,.157,1.34),(.13,.183,1.34),.042,0,p['gold'],'Chest',4)
    for side,x in [('R',1),('L',-1)]:
        upper=f'UpperArm_{side}';fore=f'Forearm_{side}';hand=f'Hand_{side}'
        cone('Sleeve',(x*.245,0,1.36),(x*.344,0,1.12),.101,.074,p['stone'],upper,8)
        sphere('Shoulder_plate',(x*.25,-.008,1.365),(.135,.14,.085),p['light'],upper,8,4)
        cone('Arm_cuff',(x*.352,0,1.105),(x*.39,.025,.935),.077,.064,p['dark'],fore,8)
        cube('Wrist_guard',(x*.39,.065,.99),(.108,.061,.135),p['light'],fore)
        sphere('Gloved_hand',(x*.39,.055,.875),(.063,.067,.071),p['ink'],hand,8,4)
        cone('Trousers',(x*.115,0,.87),(x*.13,0,.50),.089,.073,p['dark'],f'Thigh_{side}',8)
        cone('Boot',(x*.13,0,.49),(x*.13,.005,.13),.081,.067,p['ink'],f'Shin_{side}',8)
        cube('Boot_shin',(x*.13,.061,.35),(.111,.052,.24),p['stone'],f'Shin_{side}')
        cube('Boot_foot',(x*.13,.06,.085),(.145,.30,.145),p['ink'],f'Foot_{side}',.028)
        cube('Boot_toe',(x*.13,.17,.11),(.139,.086,.071),p['light'],f'Foot_{side}')
    scale_parts(s)


def robot(rig,s,p,guardian=False):
    b=1.45 if guardian else 1.08
    ring_body('Core_chassis',[(.91,.18*b,.13,0),(1.06,.22*b,.16,0),(1.31,.27*b,.18,0),(1.42,.20*b,.13,0)],p['stone'],'Chest')
    ring_body('Waist_segments',[(.82,.16*b,.13,0),(.96,.18*b,.13,0),(1.02,.15*b,.12,0)],p['ink'],'Hips')
    cube('Floating_chest_plate',(0,.164,1.24),(.33*b,.07,.29),p['light'],'Chest',.035)
    cone('Crystal_core',(0,.20,1.235),(0,.27,1.235),.102 if guardian else .073,.01,p['accent'],'Chest',6)
    cone('Neck_piston',(0,0,1.40),(0,0,1.48),.068,.068,p['gold'],'Head',8)
    ring_body('Helmet',[(1.45,.115,.105,0),(1.58,.145,.12,0),(1.69,.105,.10,0)],p['stone'],'Head')
    cube('Dark_faceplate',(0,.116,1.575),(.22,.048,.10),p['ink'],'Head',.023)
    cube('Luminous_visor',(0,.145,1.59),(.19,.018,.026),p['eye'],'Head',.006)
    cone('Crest',(0,-.015,1.67),(0,.015,1.79 if guardian else 1.76),.082,.008,p['accent'],'Head',4)
    for side,x in [('R',1),('L',-1)]:
        upper=f'UpperArm_{side}';fore=f'Forearm_{side}';hand=f'Hand_{side}'
        cone('Armature_upper',(x*.24*b,0,1.36),(x*.35*b,0,1.11),.085,.065,p['ink'],upper,8)
        cube('Pauldron',(x*.27*b,0,1.385),(.24*b,.31,.175),p['light'],upper,.035)
        cube('Shoulder_inlay',(x*.27*b,.165,1.395),(.13*b,.03,.06),p['accent'],upper)
        if guardian:
            cone('Shoulder_crystal',(x*.32*b,-.02,1.46),(x*.40*b,-.03,1.69),.09,.003,p['accent'],upper,5)
        sphere('Elbow_joint',(x*.35*b,0,1.10),(.079,.079,.079),p['gold'],fore,8,4)
        cone('Heavy_bracer',(x*.36*b,0,1.075),(x*.39*b,.028,.93),.105,.083,p['stone'],fore,8)
        cube('Bracer_panel',(x*.38*b,.088,1.01),(.12,.05,.13),p['light'],fore)
        cube('Gauntlet',(x*.39*b,.055,.875),(.15,.15,.14),p['ink'],hand,.025)
        cube('Hip_guard',(x*.155,.015,.88),(.16,.27,.18),p['stone'],'Hips',.025)
        cone('Thigh_frame',(x*.115,0,.82),(x*.13,0,.51),.09,.068,p['ink'],f'Thigh_{side}',8)
        cube('Thigh_plate',(x*.12,.069,.69),(.14,.10,.23),p['stone'],f'Thigh_{side}')
        sphere('Knee_pivot',(x*.13,.015,.49),(.087,.087,.087),p['gold'],f'Shin_{side}',8,4)
        cone('Greave',(x*.13,0,.43),(x*.13,.01,.13),.088,.073,p['stone'],f'Shin_{side}',8)
        cube('Greave_front',(x*.13,.075,.29),(.14,.075,.25),p['light'],f'Shin_{side}')
        cube('Foot',(x*.13,.07,.085),(.18,.31,.15),p['ink'],f'Foot_{side}',.03)
        cube('Foot_plate',(x*.13,.155,.15),(.17,.14,.055),p['stone'],f'Foot_{side}')
    scale_parts(s)


def scale_parts(s):
    for obj in PARTS:
        obj.location *= s
        # Geometry local scale is already applied. Scale data instead of object
        # to keep exported asset transforms identity.
        for v in obj.data.vertices:
            v.co *= s


def skin_and_join(rig,name):
    bpy.ops.object.select_all(action='DESELECT')
    for p in PARTS:
        p.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]
    bpy.ops.object.join()
    mesh=bpy.context.object
    mesh.name=name+'_Mesh'
    mod=mesh.modifiers.new('Abyss_skin','ARMATURE')
    mod.object=rig
    mesh.parent=rig
    # Every vertex has an explicit deform weight. Segment armor intentionally
    # uses rigid skin weights, avoiding rubbery metal at elbow/knee joints.
    assert all(v.groups for v in mesh.data.vertices)
    return mesh


def pose(rig,values):
    for p in rig.pose.bones:
        p.rotation_mode='XYZ'
        p.rotation_euler=(0,0,0)
        p.location=(0,0,0)
        p.scale=(1,1,1)
    for bone,angles in values.items():
        if not bone.startswith('_'):
            rig.pose.bones[bone].rotation_euler=tuple(math.radians(a) for a in angles)
    if '_hips_drop' in values:
        rig.pose.bones['Hips'].location.y=-values['_hips_drop']*rig.data.bones['Hips'].head_local.z/.88
    if '_weapon' in values:
        # Solve socket orientation in model space while the articulated arm
        # supplies its position. Metal gloves are deliberately near-spherical;
        # the small grip twist remains visually clean during a horizontal cut.
        # This also avoids compounding the forearm's pitch into sword direction.
        bpy.context.view_layer.update()
        socket=rig.pose.bones['WeaponSocket']
        local_rest=socket.parent.bone.matrix_local.inverted() @ socket.bone.matrix_local
        yaw,pitch,roll=values['_weapon']
        desired=(Matrix.Rotation(math.radians(yaw),3,'Z') @
                 Matrix.Rotation(math.radians(pitch),3,'X') @
                 Matrix.Rotation(math.radians(roll),3,'Y') @
                 socket.bone.matrix_local.to_3x3())
        basis=local_rest.to_3x3().inverted() @ socket.parent.matrix.to_3x3().inverted() @ desired
        socket.rotation_euler=basis.to_euler('XYZ')


def key(rig,t,values):
    pose(rig,values)
    frame=round(t*FPS)
    for p in rig.pose.bones:
        p.keyframe_insert('rotation_euler',frame=frame,group=p.name)
        # Root translation stays exactly zero; key it explicitly for QA.
        p.keyframe_insert('location',frame=frame,group=p.name)


def add_action(rig,name,duration,keys):
    action=bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action=action
    for t,values in keys:
        key(rig,t,values)
    track=rig.animation_data.nla_tracks.new()
    track.name=name
    strip=track.strips.new(name,0,action)
    strip.action_frame_start=0
    strip.action_frame_end=round(duration*FPS)
    strip.frame_start=0
    strip.frame_end=round(duration*FPS)
    track.mute=True
    rig.animation_data.action=None
    return duration


def animations(rig,kind):
    clips={}
    def add(n,d,k): clips[n]=add_action(rig,n,d,k)
    neutral={}
    ready={'UpperArm_R':(12,0,-15),'Forearm_R':(18,0,0),'UpperArm_L':(5,0,8),'_weapon':(10,-32,0)}
    add('Idle',1.6,[(0,ready),(.8,dict(ready,Chest=(0,0,2),Head=(0,0,-2))),(1.6,ready)])
    run_a={'Thigh_R':(34,0,0),'Shin_R':(-20,0,0),'Thigh_L':(-30,0,0),'Shin_L':(-44,0,0),'UpperArm_R':(-22,0,-10),'UpperArm_L':(30,0,10),'Chest':(-5,0,-5),'_weapon':(10,-32,0)}
    run_b={'Thigh_L':(34,0,0),'Shin_L':(-20,0,0),'Thigh_R':(-30,0,0),'Shin_R':(-44,0,0),'UpperArm_L':(-22,0,10),'UpperArm_R':(30,0,-10),'Chest':(-5,0,5),'_weapon':(10,-32,0)}
    add('Run',.64,[(0,run_a),(.16,ready),(.32,run_b),(.48,ready),(.64,run_a)])
    jump={'Thigh_R':(25,0,0),'Thigh_L':(12,0,0),'Shin_R':(-48,0,0),'Shin_L':(-25,0,0),'UpperArm_R':(35,0,-25),'UpperArm_L':(35,0,25),'Chest':(-8,0,0),'_weapon':(10,-15,0)}
    add('Jump',.36,[(0,ready),(.12,jump),(.36,jump)])
    fall=dict(jump,UpperArm_R=(5,0,-40),UpperArm_L=(5,0,40),Thigh_R=(-10,0,0),Shin_R=(-20,0,0))
    add('Fall',.4,[(0,fall),(.4,fall)])
    dodge={'Hips':(-52,0,0),'Chest':(-20,0,0),'Thigh_R':(60,0,0),'Thigh_L':(45,0,0),'Shin_R':(-72,0,0),'Shin_L':(-60,0,0),'UpperArm_R':(35,0,-20),'UpperArm_L':(35,0,20),'_weapon':(30,-15,0)}
    add('Dodge',.45,[(0,ready),(.08,dodge),(.30,dodge),(.45,ready)])
    hurt={'Chest':(20,0,-8),'Head':(12,0,5),'UpperArm_R':(20,0,-25),'UpperArm_L':(20,0,25),'_weapon':(10,-35,0)}
    add('Hurt',.25,[(0,ready),(.06,hurt),(.25,ready)])
    dead={'Hips':(79,0,0),'Chest':(12,0,0),'Head':(-15,0,0),'UpperArm_R':(0,0,-40),'UpperArm_L':(0,0,40),'Thigh_R':(-10,0,0),'Thigh_L':(10,0,0),'_hips_drop':.65,'_weapon':(60,0,0)}
    add('Death',.85,[(0,ready),(.30,hurt),(.85,dead)])
    # Exact Resource hit boundaries are explicit pose keys. The weapon moves
    # through the forward sector only during the corresponding active window.
    configs=[('Attack_01',.48,.16,.28,False),('Attack_02',.56,.20,.34,True),('Attack_03',.72,.25,.44,False),('Skill_01',.70,.25,.40,False)]
    for n,d,hs,he,rev in configs:
        sign=-1 if rev else 1
        sweep_angle=30 if n=='Skill_01' else 55
        wind={'Chest':(0,0,-25*sign),'UpperArm_R':(60,0,-65*sign),'Forearm_R':(35,0,0),'UpperArm_L':(0,0,25),'_weapon':(-80*sign,45,0)}
        start={'Chest':(0,0,-20*sign),'UpperArm_R':(70,0,-60*sign),'Forearm_R':(18,0,0),'_weapon':(-sweep_angle*sign,0,0)}
        end={'Chest':(0,0,28*sign),'UpperArm_R':(75,0,65*sign),'Forearm_R':(12,0,0),'_weapon':(sweep_angle*sign,0,0)}
        add(n,d,[(0,ready),(hs*.6,wind),(hs,start),(he,end),(d,ready)])
    enemy_angle=65 if kind=='guardian' else 50
    wind={'Chest':(0,0,-25),'UpperArm_R':(50,0,-70),'Forearm_R':(45,0,0),'_weapon':(-enemy_angle,0,0)}
    strike={'Chest':(0,0,30),'UpperArm_R':(70,0,70),'Forearm_R':(10,0,0),'_weapon':(enemy_angle,0,0)}
    tele=.55;active=.18;recover=.55
    add('Telegraph',tele,[(0,ready),(tele*.7,wind),(tele,wind)])
    add('Attack',tele+active+recover,[(0,ready),(tele*.7,wind),(tele,wind),(tele+active,strike),(tele+active+recover,ready)])
    add('Recover',recover,[(0,strike),(recover,ready)])
    if kind=='guardian':
        add('Telegraph_Sweep',.8,[(0,ready),(.65,wind),(.8,wind)])
        add('Attack_Sweep',1.67,[(0,ready),(.65,wind),(.8,wind),(1.02,strike),(1.67,ready)])
        add('Recover_Sweep',.65,[(0,strike),(.65,ready)])
        high={'Chest':(8,0,0),'UpperArm_R':(155,0,-10),'Forearm_R':(25,0,0),'UpperArm_L':(115,0,20),'Thigh_R':(10,0,0),'Thigh_L':(10,0,0),'Shin_R':(-15,0,0),'Shin_L':(-15,0,0),'_weapon':(0,65,0)}
        smash={'Chest':(-30,0,0),'UpperArm_R':(90,0,-15),'Forearm_R':(5,0,0),'UpperArm_L':(60,0,15),'Thigh_R':(80,0,0),'Thigh_L':(80,0,0),'Shin_R':(-150,0,0),'Shin_L':(-150,0,0),'_hips_drop':.55,'_weapon':(0,-48,0)}
        add('Telegraph_Shockwave',1.2,[(0,ready),(.9,high),(1.2,high)])
        add('Attack_Shockwave',2.2,[(0,ready),(.9,high),(1.10,high),(1.2,smash),(1.4,smash),(2.2,ready)])
        add('Recover_Shockwave',.8,[(0,smash),(.8,ready)])
    pose(rig,{})
    return clips


def export(path):
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',
        export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',
        export_force_sampling=True,export_frame_range=False,
        export_def_bones=False,export_nla_strips=True,
        export_skins=True,export_apply=False)


def character(kind,name,height,broad,folder):
    reset();PARTS.clear()
    p=palette(kind!='player')
    rig,s=make_rig(height,broad)
    if kind=='player': player(rig,s,p)
    else: robot(rig,s,p,kind=='guardian')
    mesh=skin_and_join(rig,name)
    root=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(root)
    rig.parent=root
    clips=animations(rig,kind)
    bpy.context.scene.frame_set(0)
    source=ROOT/'blender'/folder/(kind+'.blend')
    source.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    filename='core_guardian' if kind=='guardian' else kind
    target=OUT/(filename+'.glb')
    export(target)
    tris=sum(len(p.vertices)-2 for p in mesh.data.polygons)
    MANIFEST['characters'][filename]={
        'root':name,'source':str(source.relative_to(ROOT)).replace('\\','/'),
        'glb':str(target.relative_to(ROOT)).replace('\\','/'),
        'height_target':height,'vertices':len(mesh.data.vertices),'triangles':tris,
        'bones':[b.name for b in rig.data.bones],'socket_bone':'WeaponSocket',
        'animations':clips,'skin':'explicit rigid weights for articulated armor segments',
        'socket_orientation':'global rest identity; animated grip orientation solved in model space',
        'attack_pose_keys':{n:{'hit_start':a,'hit_end':b} for n,a,b in [('Attack_01',.16,.28),('Attack_02',.20,.34),('Attack_03',.25,.44),('Skill_01',.25,.40),('Attack',.55,.73)]+([('Attack_Sweep',.8,1.02),('Attack_Shockwave',1.2,1.4)] if kind=='guardian' else [])},
    }
    print('ASSET_OK',filename,'triangles',tris,'animations',len(clips))


def weapon(kind):
    reset();PARTS.clear();p=palette(kind!='sword')
    if kind in ['sword','sentinel_blade']:
        length=.88 if kind=='sword' else .72
        cone('Grip',(0,-.14,0),(0,.06,0),.028,.028,p['ink'],vertices=8)
        cone('Pommel',(0,-.17,0),(0,-.13,0),.045,.028,p['gold'],vertices=6)
        cube('Crossguard',(0,.07,0),(.25,.06,.06),p['gold'])
        # Diamond-section blade, point forward along Blender +Y.
        w=.065 if kind=='sword' else .085
        custom('Forged_blade',[(0,.10,.026),(-w,.10,0),(0,.10,-.026),(w,.10,0),
                             (0,length*.78,.020),(-w*.62,length*.78,0),(0,length*.78,-.020),(w*.62,length*.78,0),(0,length,0)],
               [(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,8),(5,6,8),(6,7,8),(7,4,8),(3,2,1,0)],p['light'])
        custom('Crystal_edge',[(-w*.65,.15,.027),(-w*.37,length*.73,.024),(0,length*.9,.013),(w*.34,length*.73,.024),(w*.65,.15,.027)],[(0,1,2,3,4)],p['accent'])
    else:
        cone('Hammer_haft',(0,-.25,0),(0,1.0,0),.043,.055,p['ink'],vertices=8)
        for y in [.05,.25,.45,.65]: cube('Grip_band',(0,y,0),(.095,.035,.095),p['gold'])
        cube('Hammer_core',(0,.93,0),(.72,.32,.30),p['stone'],bevel=.045)
        for x in [-1,1]:
            cube('Hammer_strike_face',(x*.40,.93,0),(.14,.39,.38),p['light'],bevel=.035)
            cube('Amber_face',(x*.48,.93,0),(.027,.22,.22),p['accent'],bevel=.012)
        cone('Hammer_crystal',(0,1.10,0),(0,1.34,0),.15,.005,p['accent'],vertices=6)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in PARTS: obj.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name={'sword':'WPN_StarBlade_01','sentinel_blade':'WPN_SentinelBlade_01','guardian_hammer':'WPN_CoreHammer_01'}[kind]
    # The first joined cone has a rotated local axis. Bake that rotation so
    # glTF root -Z really is the visible blade/haft direction at the grip.
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    folder=ROOT/'blender/characters' if kind=='sword' else ROOT/'blender/enemies'
    folder.mkdir(parents=True,exist_ok=True)
    source=folder/(kind+'.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    export(OUT/(kind+'.glb'))
    MANIFEST['weapons'][kind]={'grip_origin':[0,0,0],'forward_godot':'-Z',
        'source':str(source.relative_to(ROOT)).replace('\\','/'),
        'triangles':sum(len(p.vertices)-2 for p in obj.data.polygons)}
    print('ASSET_OK',kind)


if '--weapons-only' in sys.argv:
    MANIFEST['characters']=json.loads((ROOT/'docs/character_asset_manifest.json').read_text(encoding='utf8'))['characters']
else:
    character('player','CHR_Player_01',1.75,1.0,'characters')
    character('sentinel','ENM_Sentinel_01',1.65,1.08,'enemies')
    character('guardian','BOS_CoreGuardian_01',2.60,1.45,'enemies')
for kind in ['sword','sentinel_blade','guardian_hammer']: weapon(kind)
(ROOT/'docs/character_asset_manifest.json').write_text(json.dumps(MANIFEST,indent=2,ensure_ascii=False),encoding='utf8')
print('CHARACTER_LIBRARY_COMPLETE')
