// ============================================================
// Runtime texture baking
//
// Rasterises a model's UV triangles into an albedo atlas and
// shades every texel procedurally from its 3D position, normal
// and dominant skin bone. Used to texture the character and the
// arrow, which ship without materials in their .glb files.
//
// The result is deterministic and needs no external assets, so
// re-exporting the .glb from Blender keeps working unchanged.
// ============================================================

#pragma once

#include <functional>
#include <string>
#include <vector>

#include "model.h"

namespace bake {

struct Image {
    int w = 0;
    int h = 0;
    std::vector<uint8_t> rgba; // w*h*4
    bool ok() const { return w > 0 && h > 0 && rgba.size() == (size_t)w * h * 4; }
};

// pos/normal are in the model's render space, bone is the dominant
// joint index (-1 for static meshes)
using ShadeFn = std::function<glm::vec3(const glm::vec3& pos,
                                        const glm::vec3& normal, int bone)>;

// maps a joint index to a colour region; islands that mix regions are
// split before packing so the baked atlas never bleeds between parts
using BoneGroupFn = std::function<int(int bone)>;

// Repacks the scene's UV islands in place (see bake.cpp) so the mesh
// that is rendered and the baked atlas use the same mapping. Call this
// once after loading, before uploading the vertex buffers.
void repackSceneUVs(model::Scene& sc);

// bakes all objects of the scene into one square atlas; the scene must
// already have been through repackSceneUVs()
Image bake(const model::Scene& sc, int size, const ShadeFn& shade);

// character palette: hood, jacket, pants, boots, gloves, skin, eyes
Image characterTexture(const model::Scene& sc, int size = 1024);

// arrow: wooden shaft, metal head, feather fletching
Image arrowTexture(const model::Scene& sc, int size = 512);

} // namespace bake
