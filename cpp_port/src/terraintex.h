// ============================================================
// Terrain PBR textures
//
// Generates tileable albedo/normal/roughness layers for the
// terrain materials (sand, grass, dirt, rock, grey rock, snow).
// Real texture files can be dropped into
// assets/textures/terrain/<name>_{albedo,normal,rough}.png and
// they take precedence over the procedural generation.
//
// albedoRough: RGB = base colour, A = roughness
// normalAo:    RGB = tangent-space normal (x -> world X,
//              y -> world Z, z -> up), A = ambient occlusion
// extra:       R = metallic, G = height (displacement),
//              B = reflectance, A = unused
// ============================================================

#pragma once

#include <string>
#include <vector>

#include "bake.h"

namespace terraintex {

struct Layer {
    std::string name;
    std::string source; // "file" or "procedural"
    bake::Image albedoRough;
    bake::Image normal; // normalAo
    bake::Image extra;  // metallic / height / reflectance
};

// material order must match the shader weights
enum Material { SAND = 0, GRASS = 1, DIRT = 2, ROCK = 3, GREY = 4, SNOW = 5 };

// builds all layers: real texture sets from the project assets
// (`root/assets/textures/...`) when present, otherwise procedural;
// `root` may be empty to force procedural generation
std::vector<Layer> generate(int size = 256, const std::string& root = "");

} // namespace terraintex
