"""Creeaza clipurile Idle/Walk/Run pe armature-ul 'metarig' si exporta
models/characters/baiaat.glb cu animatii glTF.

Rulare:
    blender -b models/characters/baiaat.blend \
        --python cpp_port/tools/make_character_anims.py

Scriptul:
  * sterge animatiile vechi de pe metarig;
  * construieste actiunile Idle (4s), Walk (1s) si Run (0.67s) prin
    eșantionare pe fiecare cadru (24 fps), cu rotatii in jurul axelor
    globale (conversie automata in spatiul local al fiecarui os);
  * pune fiecare actiune pe cate un NLA track (necesar pentru export);
  * salveaza .blend-ul si exporta GLB-ul cu animatii.
"""

import math
import sys

import bpy
from mathutils import Quaternion, Vector

FPS = 24
ARM_NAME = "metarig"
MESH_NAME = "Cube_unwrapped_unwrapped_unwrapped"

ANIM_BONES = [
    "spine", "spine.001", "spine.002", "spine.003", "spine.004",
    "spine.005", "spine.006",
    "shoulder.L", "shoulder.R",
    "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R",
    "thigh.L", "thigh.R", "shin.L", "shin.R",
    "foot.L", "foot.R", "toe.L", "toe.R",
]

X = Vector((1.0, 0.0, 0.0))
Y = Vector((0.0, 1.0, 0.0))
Z = Vector((0.0, 0.0, 1.0))

PI = math.pi


def rest_quat(pb):
    return pb.bone.matrix_local.to_3x3().to_quaternion()


def local_of_world(pb, q_world):
    """Converteste o rotatie in spatiul armaturii in rotatia locala a osului."""
    q = rest_quat(pb)
    return q.inverted() @ q_world @ q


def world_rot(pb, q_world):
    pb.rotation_quaternion = local_of_world(pb, q_world)


def world_loc(pb, v_world):
    pb.location = rest_quat(pb).to_matrix().inverted() @ Vector(v_world)


def axis_rot(axis, angle):
    return Quaternion(axis, angle)


def arm_pose(arm, side, swing, elbow):
    """Arm base (coborat pe langa corp) + balans + flexie cot."""
    s = 1.0 if side == "L" else -1.0
    up = arm.pose.bones["upper_arm." + side]
    fore = arm.pose.bones["forearm." + side]
    # bratul coboara din A-pose: rotatie in jurul axei Y globale
    q_down = axis_rot(Y, s * 1.15)
    # balansul fata/spate: rotatie in jurul axei X globale (negativ = in fata)
    q_swing = axis_rot(X, -swing)
    q_world = q_swing @ q_down
    world_rot(up, q_world)
    # cotul: flexie in jurul axei din rest (rotita de parinte) - Z pentru L
    world_rot(fore, axis_rot(Z * -s, elbow))


def leg_pose(arm, side, thigh_fwd, knee, ankle, toe):
    th = arm.pose.bones["thigh." + side]
    sh = arm.pose.bones["shin." + side]
    ft = arm.pose.bones["foot." + side]
    to = arm.pose.bones["toe." + side]
    world_rot(th, axis_rot(X, -thigh_fwd))
    world_rot(sh, axis_rot(X, knee))
    world_rot(ft, axis_rot(X, ankle))
    world_rot(to, axis_rot(X, toe))


def reset_pose(arm):
    for name in ANIM_BONES:
        pb = arm.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


# ---------------------------------------------------------------- clipuri


def pose_idle(arm, t):
    p = 2.0 * PI * t
    breathe = math.sin(p * 2.0)
    sway = math.sin(p)
    sp = arm.pose.bones
    world_rot(sp["spine"], axis_rot(X, 0.008 * breathe))
    world_rot(sp["spine.001"], axis_rot(Y, 0.012 * sway))
    world_rot(sp["spine.002"], axis_rot(X, 0.018 * breathe))
    world_rot(sp["spine.003"],
              axis_rot(X, 0.022 * breathe) @ axis_rot(Z, 0.03 * sway))
    world_rot(sp["spine.005"], axis_rot(X, 0.015 * math.sin(p * 1.5)))
    world_rot(sp["spine.006"],
              axis_rot(Z, 0.05 * math.sin(p * 0.75)) @
              axis_rot(X, 0.015 * math.sin(p * 1.5 + 0.7)))
    arm_pose(arm, "L", 0.02 * sway, 0.14 + 0.02 * breathe)
    arm_pose(arm, "R", -0.02 * sway, 0.14 + 0.02 * breathe)
    leg_pose(arm, "L", 0.0, 0.03, -0.02, 0.0)
    leg_pose(arm, "R", 0.0, 0.03, -0.02, 0.0)
    world_loc(sp["spine"], (0.006 * sway, 0.0, 0.006 * breathe))


def pose_walk(arm, t):
    p = 2.0 * PI * t
    sp = arm.pose.bones
    a_th, a_arm = 0.55, 0.45
    th_l = a_th * math.sin(p)
    th_r = a_th * math.sin(p + PI)
    knee_l = 0.9 * max(0.0, math.cos(p)) + 0.05
    knee_r = 0.9 * max(0.0, math.cos(p + PI)) + 0.05
    ankle_l = 0.18 * math.sin(p + 0.7) - 0.05
    ankle_r = 0.18 * math.sin(p + PI + 0.7) - 0.05
    toe_l = 0.25 * max(0.0, math.sin(p + 0.4))
    toe_r = 0.25 * max(0.0, math.sin(p + PI + 0.4))
    leg_pose(arm, "L", th_l, knee_l, ankle_l, toe_l)
    leg_pose(arm, "R", th_r, knee_r, ankle_r, toe_r)
    arm_pose(arm, "L", -a_arm * math.sin(p),
             0.15 + 0.30 * max(0.0, -math.sin(p)))
    arm_pose(arm, "R", -a_arm * math.sin(p + PI),
             0.15 + 0.30 * max(0.0, math.sin(p)))
    world_rot(sp["spine"], axis_rot(Z, 0.06 * math.sin(p)) @
              axis_rot(X, 0.05))
    world_rot(sp["spine.001"], axis_rot(Z, 0.05 * math.sin(p)))
    world_rot(sp["spine.003"], axis_rot(Z, -0.07 * math.sin(p)))
    world_rot(sp["spine.006"], axis_rot(Z, 0.03 * math.sin(p)))
    world_loc(sp["spine"],
              (0.018 * math.sin(p), 0.0, -0.015 + 0.02 * math.cos(2.0 * p)))


def pose_run(arm, t):
    p = 2.0 * PI * t
    sp = arm.pose.bones
    a_th, a_arm = 0.95, 0.85
    th_l = a_th * math.sin(p)
    th_r = a_th * math.sin(p + PI)
    knee_l = 1.35 * max(0.0, math.cos(p)) + 0.18
    knee_r = 1.35 * max(0.0, math.cos(p + PI)) + 0.18
    ankle_l = 0.30 * math.sin(p + 0.9) - 0.08
    ankle_r = 0.30 * math.sin(p + PI + 0.9) - 0.08
    toe_l = 0.35 * max(0.0, math.sin(p + 0.4))
    toe_r = 0.35 * max(0.0, math.sin(p + PI + 0.4))
    leg_pose(arm, "L", th_l, knee_l, ankle_l, toe_l)
    leg_pose(arm, "R", th_r, knee_r, ankle_r, toe_r)
    arm_pose(arm, "L", -a_arm * math.sin(p),
             0.75 + 0.25 * max(0.0, -math.sin(p)))
    arm_pose(arm, "R", -a_arm * math.sin(p + PI),
             0.75 + 0.25 * max(0.0, math.sin(p)))
    world_rot(sp["spine"], axis_rot(Z, 0.10 * math.sin(p)) @
              axis_rot(X, 0.16))
    world_rot(sp["spine.001"], axis_rot(Z, 0.08 * math.sin(p)) @
              axis_rot(X, 0.06))
    world_rot(sp["spine.003"], axis_rot(Z, -0.10 * math.sin(p)) @
              axis_rot(X, 0.04))
    world_rot(sp["spine.006"], axis_rot(X, -0.18))
    world_loc(sp["spine"],
              (0.025 * math.sin(p), 0.0, -0.03 + 0.045 * math.cos(2.0 * p)))


CLIPS = [
    ("Idle", 96, pose_idle),
    ("Walk", 24, pose_walk),
    ("Run", 16, pose_run),
]


def action_fcurves(act):
    """Blender 5.x: fcurves traiesc in layers/strips/channelbags."""
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


def build_action(arm, name, frames, pose_fn):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for f in range(frames + 1):
        t = f / float(frames)
        reset_pose(arm)
        pose_fn(arm, t)
        for bone in ANIM_BONES:
            pb = arm.pose.bones[bone]
            pb.keyframe_insert("rotation_quaternion", frame=f)
        arm.pose.bones["spine"].keyframe_insert("location", frame=f)
    for fc in action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    arm.animation_data.action = None
    return act


def main():
    arm = bpy.data.objects.get(ARM_NAME)
    mesh = bpy.data.objects.get(MESH_NAME)
    if arm is None or mesh is None:
        print("ERROR: missing metarig/mesh in the blend")
        sys.exit(1)

    bpy.context.scene.render.fps = FPS
    if arm.animation_data:
        arm.animation_data_clear()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    arm.animation_data_create()

    actions = []
    for name, frames, fn in CLIPS:
        act = build_action(arm, name, frames, fn)
        actions.append(act)
        print("ACTION %s: %d frames" % (name, frames))

    # NLA tracks (un strip per actiune) pentru exportul in modul ACTIONS
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)
    for act in actions:
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, 0, act)
        st.name = act.name
        if hasattr(st, "action_slot") and len(act.slots):
            st.action_slot = act.slots[0]
        tr.mute = True

    reset_pose(arm)
    bpy.context.scene.frame_set(0)

    blend_path = bpy.data.filepath
    glb_path = bpy.path.abspath("//baiaat.glb")
    bpy.ops.wm.save_mainfile(filepath=blend_path)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_anim_single_armature=True,
    )
    print("EXPORTED", glb_path)


main()
