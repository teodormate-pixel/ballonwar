// ============================================================
// GLB structure loader + automatic fragmentation
//
// Loads glTF 2.0 binary (.glb) meshes that carry a base-color
// texture (the house) - untextured helper objects are skipped.
// The mesh is split into N breakable parts via spatial
// clustering so a house can be destroyed piece by piece.
//
// Vertex layout: pos3 + nrm3 + uv2 (8 floats per vertex).
// ============================================================

#pragma once

#include <glm/glm.hpp>
#include <string>
#include <vector>

namespace model {

struct Mesh {
    // 8 floats / vertex: pos(3) nrm(3) uv(2)
    std::vector<float> verts;
    std::vector<uint32_t> indices;
    glm::vec3 bmin{0};
    glm::vec3 bmax{0};

    // base-colour texture (embedded PNG/JPEG), ready for stb_image
    std::vector<uint8_t> texture;
    glm::vec4 tint{1, 1, 1, 1};
    bool textured = false;

    bool empty() const { return indices.empty(); }
};

struct Part {
    uint32_t indexBegin = 0;
    uint32_t indexCount = 0;
    glm::vec3 centroid{0};
    glm::vec3 pmin{0};
    glm::vec3 pmax{0};
};

// loads the textured house parts of a .glb file
bool loadGLB(const std::string& path, Mesh& out);

// decodes the embedded PNG/JPEG into RGBA8 (for GL upload)
bool decodeTexture(const std::vector<uint8_t>& png, int& w, int& h,
                   std::vector<uint8_t>& rgba);

// splits the mesh into `parts` spatially coherent chunks; the caller
// must render `reordered` indices (each part = one contiguous range)
void splitIntoParts(const Mesh& mesh, int n, std::vector<Part>& out,
                    std::vector<uint32_t>* reordered);

} // namespace model

namespace model {

// ============================================================
// GLTF SCENE support (hierarchical models like the tank)
// ============================================================

struct SceneImage {
    int w = 0, h = 0;
    std::vector<uint8_t> rgba;
    bool ok = false;
};

struct SceneGeom {
    std::vector<float> verts; // pos3 nrm3 uv2
    std::vector<uint32_t> indices;
    glm::vec3 bmin{0}, bmax{0};
    int texImage = -1; // base color image (or -1)
    glm::vec4 tint{1, 1, 1, 1};

    // skeletal skinning (glTF JOINTS_0 / WEIGHTS_0)
    bool skinned = false;
    std::vector<uint8_t> joints;  // 4 indices per vertex
    std::vector<float> weights;   // 4 weights per vertex
};

// one glTF skin: joint node indices + inverse bind matrices
struct Skin {
    std::vector<int> joints;
    std::vector<glm::mat4> inverseBind;
};

// one glTF animation sampler: keyframe times + values
// (xyz for translation/scale, xyzw for rotation)
struct AnimSampler {
    std::vector<float> times;
    std::vector<glm::vec4> values;
    bool step = false;
};

// channel: target node + path (0=T, 1=R, 2=S) + sampler index
struct AnimChannel {
    int node = -1;
    int path = 0;
    int sampler = -1;
};

struct Animation {
    std::string name;
    std::vector<AnimSampler> samplers;
    std::vector<AnimChannel> channels;
    float duration = 0.0f;
};

// runtime tags for animated parts
enum ObjTag { TAG_HULL = 0, TAG_TURRET = 1, TAG_BARREL = 2, TAG_TRACK = 3 };

struct SceneObj {
    glm::mat4 base{1.0f};
    glm::mat4 baseInv{1.0f};
    int mesh = -1;
    int node = -1; // glTF node index (for the node hierarchy)
    int skin = -1; // glTF skin index (-1 = static)
    std::string name;
    ObjTag tag = TAG_HULL;
    glm::vec3 pivotLocal{0}; // rotation pivot in tank frame
    // barrel muzzle measurement (tank frame)
    glm::vec3 muzzleDirLocal{0, 0, 1};
    glm::vec3 muzzleLocal{0}; // exact muzzle vertex in mesh-local space
    float muzzleLen = 0.0f;
};

struct Scene {
    std::vector<SceneImage> images;
    std::vector<SceneGeom> geoms;
    std::vector<SceneObj> objs;
    glm::vec3 bmin{0}, bmax{0};
    float minY = 0.0f; // lowest point (tank frame)
    bool ok = false;

    // full glTF node hierarchy (needed to pose skinned characters)
    std::vector<glm::mat4> nodeLocal;
    std::vector<int> nodeParent;
    std::vector<std::vector<int>> nodeChildren;
    std::vector<int> nodeMesh;
    std::vector<std::string> nodeNames;
    std::vector<Skin> skins;
    std::vector<Animation> animations;

    bool skinned() const {
        for (const auto& g : geoms)
            if (g.skinned)
                return true;
        return false;
    }
};

// loads the scene; picks the root that contains `rootHint` (e.g. "Corp")
bool loadGLBScene(const std::string& path, Scene& out,
                  const char* rootHint = "Corp");

// exact node index by name, or -1
int findNode(const Scene& sc, const std::string& name);

// global matrices from a set of local matrices (identity when locals empty)
void computeNodeGlobals(const Scene& sc, const std::vector<glm::mat4>& locals,
                        std::vector<glm::mat4>& out);

// joint matrices = globalJoint * inverseBind, ready for the vertex shader
void computeSkinMatrices(const Scene& sc,
                         const std::vector<glm::mat4>& globals, int skinIndex,
                         std::vector<glm::mat4>& out);

} // namespace model
