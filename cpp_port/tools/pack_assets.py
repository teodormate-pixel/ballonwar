#!/usr/bin/env python3
"""Stage the runtime assets for a release package.

  pack_assets.py <repo-root> <out-dir> [--terrain-size N]

Copies only what the game loads at runtime and (when Pillow is
available) downscales the 2K terrain textures to `terrain-size`
(default 512) so the release archive stays reasonable. Blender
sources, archives and Godot .import files are skipped.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys

MODELS = [
    "models/balloon/ballon.glb",
    "models/arrow/arrow.glb",
    "models/spawner/Meshy_AI_a_ballon_spawner_mine_0526161540_texture.glb",
    "models/characters/baiaat.glb",
]

AUDIO = [
    "assets/audio/rele.wav",
    "assets/audio/arrowhit.wav",
    "assets/images/assest/balloon-pop-48030 (1).wav",
    "assets/images/assest/background_music.mp3",
]

# terrain PBR sets loaded by terraintex.cpp
TERRAIN = {
    "assets/textures/GroundSand005/GroundSand005_COL_2K.jpg": "sand_albedo.jpg",
    "assets/textures/GroundSand005/GroundSand005_NRM_2K.jpg": "sand_normal.jpg",
    "assets/textures/GroundSand005/GroundSand005_GLOSS_2K.jpg": "sand_gloss.jpg",
    "assets/textures/GroundSand005/GroundSand005_AO_2K.jpg": "sand_ao.jpg",
    "assets/textures/GroundSand005/GroundSand005_DISP_2K.jpg": "sand_disp.jpg",
    "assets/textures/GroundSand005/GroundSand005_REFL_2K.jpg": "sand_refl.jpg",
    "assets/textures/GroundDirtWeedsPatchy004/GroundDirtWeedsPatchy004_COL_2K.jpg": "dirt_albedo.jpg",
    "assets/textures/GroundDirtWeedsPatchy004/GroundDirtWeedsPatchy004_NRM_2K.jpg": "dirt_normal.jpg",
    "assets/textures/GroundDirtWeedsPatchy004/GroundDirtWeedsPatchy004_GLOSS_2K.jpg": "dirt_gloss.jpg",
    "assets/textures/GroundDirtWeedsPatchy004/GroundDirtWeedsPatchy004_AO_2K.jpg": "dirt_ao.jpg",
    "assets/textures/GroundDirtWeedsPatchy004/GroundDirtWeedsPatchy004_DISP_2K.jpg": "dirt_disp.jpg",
    "assets/textures/GroundDirtWeedsPatchy004/GroundDirtWeedsPatchy004_REFL_2K.jpg": "dirt_refl.jpg",
    "assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_BaseColor.jpg": "grass_albedo.jpg",
    "assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Normal.png": "grass_normal.png",
    "assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Roughness.jpg": "grass_rough.jpg",
    "assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_AmbientOcclusion.jpg": "grass_ao.jpg",
    "assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Displacement.png": "grass_disp.png",
    "assets/textures/Poliigon_GrassPatchyGround_4585/2K/Poliigon_GrassPatchyGround_4585_Metallic.jpg": "grass_metallic.jpg",
    "assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_diff_2k.jpg": "rock_albedo.jpg",
    "assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_nor_gl_2k.png": "rock_normal.png",
    "assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_rough_2k.jpg": "rock_rough.jpg",
    "assets/textures/rocks_ground_04_2k.blend/textures/rocks_ground_04_disp_2k.png": "rock_disp.png",
    "assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_Color.jpg": "snow_albedo.jpg",
    "assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_NormalGL.jpg": "snow_normal.jpg",
    "assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_Roughness.jpg": "snow_rough.jpg",
    "assets/textures/Snow004_2K-JPG/Snow004_2K-JPG_Displacement.jpg": "snow_disp.jpg",
}


def copy_file(root: str, rel: str, out: str, new_name: str | None = None) -> int:
    src = os.path.join(root, rel)
    if not os.path.exists(src):
        print(f"  missing: {rel}")
        return 0
    dst = os.path.join(out, new_name or rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    return os.path.getsize(dst)


def copy_downscaled(root: str, rel: str, out: str, size: int) -> int:
    """keeps the original path (the game looks textures up by it)"""
    src = os.path.join(root, rel)
    if not os.path.exists(src):
        print(f"  missing: {rel}")
        return 0
    dst = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    try:
        from PIL import Image

        with Image.open(src) as img:
            if max(img.size) > size:
                ratio = size / max(img.size)
                img = img.resize(
                    (max(1, int(img.width * ratio)),
                     max(1, int(img.height * ratio))),
                    Image.LANCZOS)
            if rel.lower().endswith((".jpg", ".jpeg")):
                img.convert("RGB").save(dst, quality=88)
            else:
                img.save(dst)
    except Exception as exc:  # Pillow missing or decode error
        print(f"  (copying {rel}: {exc})")
        shutil.copy2(src, dst)
    return os.path.getsize(dst)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--terrain-size", type=int, default=512)
    args = ap.parse_args()

    root, out = args.root, args.out
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out, exist_ok=True)

    total = 0
    for rel in MODELS:
        total += copy_file(root, rel, out)
    for rel in AUDIO:
        total += copy_file(root, rel, out)

    # terrain textures: the game looks them up by their original
    # paths, so the release keeps the directory structure
    for rel in TERRAIN:
        total += copy_downscaled(root, rel, out, args.terrain_size)

    # user overrides (if any)
    overrides = os.path.join(root, "assets/textures/terrain")
    if os.path.isdir(overrides):
        dst = os.path.join(out, "assets/textures/terrain")
        shutil.copytree(overrides, dst, dirs_exist_ok=True)

    print(f"staged {total / 1e6:.1f} MB into {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
