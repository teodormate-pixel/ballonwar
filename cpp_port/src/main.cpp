// ============================================================
// BalloonWar - C++ port (OpenGL 3.3 / GLFW)
//
// Terrain and water are the C++ implementations from the
// "23 august 1944" project. Everything else (gameplay, blocks,
// balloons, arrows, crafting, saves, menus, editor, network,
// HUD) is a port of the BalloonWar Python/Godot runtime.
// ============================================================

#include "glloader.h"
#include <GLFW/glfw3.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <glm/gtx/matrix_decompose.hpp>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "anim.h"
#include "platform.h"
#include "bake.h"
#include "terraintex.h"
#include "debug.h"
#include "font_data.h"
#include "game.h"
#include "model.h"
#include "net.h"
#include "ui.h"

namespace {

// set from SIGINT/SIGTERM/SIGHUP so the game shuts down cleanly
// (stops the music helper before exiting)
volatile std::sig_atomic_t g_quitRequested = 0;
void onQuitSignal(int) { g_quitRequested = 1; }

constexpr int WINDOW_WIDTH = 1280;
constexpr int WINDOW_HEIGHT = 720;
constexpr int64_t R_PAGES = 6;
constexpr double FOG_END = 1400.0;

const glm::vec3 FOG_COLOR(0.68f, 0.75f, 0.82f);
const glm::vec3 SUN_DIR = glm::normalize(glm::vec3(-0.52f, 0.78f, -0.35f));

// ============================================================
// shaders
// ============================================================

const char* kTerrainVert = R"GLSL(
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNrm;
uniform mat4 uMvp;
out vec3 vWorld;
out vec3 vNrm;
void main() {
    gl_Position = uMvp * vec4(aPos, 1.0);
    vWorld = aPos;
    vNrm = aNrm;
}
)GLSL";

const char* kTerrainFrag = R"GLSL(
#version 330 core
in vec3 vWorld;
in vec3 vNrm;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uFogColor;
uniform float uFogStart;
uniform float uFogEnd;
uniform float uRelief;
uniform sampler2DArray uAlbedoRough; // rgb albedo, a roughness
uniform sampler2DArray uNormalTex;   // rgb normal, a ambient occlusion
uniform sampler2DArray uExtraTex;    // r metallic, g height, b reflectance
uniform float uTexScale;
uniform float uParallax;
uniform float uPbr;
out vec4 outColor;

const float PI = 3.14159265;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float rawRelief(float h) {
    const float VTOP = 25.0;
    const float RAMP = 40.0;
    float FULL = VTOP + RAMP * uRelief; // uniform -> not a const expression
    if (h <= VTOP) return h;
    if (h >= FULL) return VTOP + (h - VTOP) / uRelief;
    float r = VTOP + (h - VTOP) / uRelief;
    for (int i = 0; i < 6; ++i) {
        r = max(r, VTOP);
        float t = clamp((r - VTOP) / RAMP, 0.0, 1.0);
        float s = t * t * (3.0 - 2.0 * t);
        float f = r + (r - VTOP) * (uRelief - 1.0) * s;
        float df = 1.0 + (uRelief - 1.0) *
                             (s + (r - VTOP) * 6.0 * t * (1.0 - t) / RAMP);
        r -= (f - h) / df;
    }
    return r;
}

void main() {
    vec3 n = normalize(vNrm);
    float y = rawRelief(vWorld.y);
    float slope = 1.0 - n.y;

    // material blend weights: sand, grass, dirt, rock, grey rock, snow
    float t1 = smoothstep(2.0, 16.0, y);
    float t2 = smoothstep(22.0, 46.0, y);
    float t3 = smoothstep(55.0, 130.0, y);
    float t4 = smoothstep(170.0, 320.0, y);
    float t5 = smoothstep(330.0, 440.0, y);
    float w[6];
    w[0] = 1.0 - t1;
    w[1] = t1 * (1.0 - t2);
    w[2] = t2 * (1.0 - t3);
    w[3] = t3 * (1.0 - t4);
    w[4] = t4 * (1.0 - t5);
    w[5] = t5;
    float rockAmt = smoothstep(0.28, 0.60, slope) * smoothstep(0.0, 40.0, y);
    for (int i = 0; i < 6; ++i) w[i] *= 1.0 - rockAmt;
    w[3] += rockAmt;

    vec3 albedo;
    float rough;
    float ao = 1.0;
    float metallic = 0.0;
    float refl = 0.5;
    vec3 nrmPerturb = vec3(0.0, 0.0, 1.0); // world-space normal offset
    if (uPbr > 0.5) {
        // two projections: top-down (XZ) for flat ground and a side
        // projection along the dominant axis for cliffs, so the
        // textures do not stretch on steep slopes
        vec2 uvY = vWorld.xz * uTexScale;
        vec3 an = abs(n);
        float wSide = smoothstep(0.75, 0.35, an.y);
        bool alongX = an.x > an.z;
        vec2 uvS = (alongX ? vWorld.zy : vWorld.xy) * uTexScale;

        // parallax from the displacement map of the dominant material
        int domLayer = 0;
        float domW = -1.0;
        for (int i = 0; i < 6; ++i)
            if (w[i] > domW) {
                domW = w[i];
                domLayer = i;
            }
        vec3 Vv = normalize(uCamPos - vWorld);
        float hPar =
            texture(uExtraTex, vec3(uvY, float(domLayer))).g - 0.5;
        uvY += vec2(Vv.x, Vv.z) * hPar * uParallax;
        uvS += (alongX ? vec2(Vv.z, Vv.y) : vec2(Vv.x, Vv.y)) * hPar *
               uParallax;

        vec3 albedoY = vec3(0.0), albedoS = vec3(0.0);
        float roughY = 0.0, roughS = 0.0;
        float aoY = 0.0, aoS = 0.0;
        float metY = 0.0, metS = 0.0;
        float reflY = 0.0, reflS = 0.0;
        vec3 nY = vec3(0.0), nS = vec3(0.0);
        float sumY = 0.0, sumS = 0.0;
        for (int i = 0; i < 6; ++i) {
            if (w[i] < 0.004) continue;
            vec4 a = texture(uAlbedoRough, vec3(uvY, float(i)));
            vec4 nn = texture(uNormalTex, vec3(uvY, float(i)));
            vec4 ex = texture(uExtraTex, vec3(uvY, float(i)));
            vec3 nm = nn.xyz * 2.0 - 1.0;
            albedoY += a.rgb * w[i];
            roughY += a.a * w[i];
            aoY += nn.a * w[i];
            metY += ex.r * w[i];
            reflY += ex.b * w[i];
            nY += vec3(nm.x, 0.0, nm.y) * w[i];
            sumY += w[i];
            if (wSide > 0.001) {
                vec4 a2 = texture(uAlbedoRough, vec3(uvS, float(i)));
                vec4 nn2 = texture(uNormalTex, vec3(uvS, float(i)));
                vec4 ex2 = texture(uExtraTex, vec3(uvS, float(i)));
                vec3 nm2 = nn2.xyz * 2.0 - 1.0;
                albedoS += a2.rgb * w[i];
                roughS += a2.a * w[i];
                aoS += nn2.a * w[i];
                metS += ex2.r * w[i];
                reflS += ex2.b * w[i];
                nS += (alongX ? vec3(0.0, nm2.y, nm2.x)
                              : vec3(nm2.x, nm2.y, 0.0)) *
                      w[i];
                sumS += w[i];
            }
        }
        if (sumY > 1e-4) {
            albedoY /= sumY;
            roughY /= sumY;
            aoY /= sumY;
            metY /= sumY;
            reflY /= sumY;
        }
        if (sumS > 1e-4) {
            albedoS /= sumS;
            roughS /= sumS;
            aoS /= sumS;
            metS /= sumS;
            reflS /= sumS;
        }
        albedo = mix(albedoY, albedoS, wSide);
        rough = mix(roughY, roughS, wSide);
        ao = mix(aoY, aoS, wSide);
        metallic = mix(metY, metS, wSide);
        refl = mix(reflY, reflS, wSide);
        nrmPerturb = normalize(mix(nY, nS, wSide) + vec3(0.0, 0.0, 1.0));
        if (sumY < 1e-4 && sumS < 1e-4) {
            albedo = vec3(0.4);
            rough = 0.8;
            ao = 1.0;
            metallic = 0.0;
            refl = 0.5;
            nrmPerturb = vec3(0.0, 0.0, 1.0);
        }
    } else {
        vec3 sand  = vec3(0.78, 0.72, 0.53);
        vec3 grass = vec3(0.37, 0.50, 0.20);
        vec3 dirt  = vec3(0.48, 0.39, 0.27);
        vec3 rock  = vec3(0.50, 0.47, 0.44);
        vec3 grey  = vec3(0.62, 0.62, 0.62);
        vec3 snow  = vec3(0.93, 0.95, 0.98);
        albedo = sand * w[0] + grass * w[1] + dirt * w[2] + rock * w[3] +
                 grey * w[4] + snow * w[5];
        rough = 0.85;
        nrmPerturb = vec3(0.0, 0.0, 1.0);
    }

    float jit = (hash12(floor(vWorld.xz * 0.05)) - 0.5) * 0.06;
    albedo *= 1.0 + jit;

    // world-space normal perturbation (projection-aware)
    vec3 N = normalize(n + nrmPerturb * 0.75);
    if (N.y < 0.0) N = n;

    // Cook-Torrance GGX (dielectric, F0 = 0.04)
    vec3 V = normalize(uCamPos - vWorld);
    vec3 L = uSunDir;
    vec3 H = normalize(L + V);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 1e-4);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);
    float a = max(0.04, rough * rough);
    float a2 = a * a;
    float dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / max(1e-6, PI * dd * dd);
    float k = a * 0.5;
    float G = (NdotL / (NdotL * (1.0 - k) + k)) *
              (NdotV / (NdotV * (1.0 - k) + k));
    vec3 F0 = mix(vec3(0.04), albedo, metallic) * (0.6 + 0.8 * refl);
    vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
    vec3 spec = D * G * F / max(4.0 * NdotV * NdotL, 1e-4);

    vec3 sunColor = vec3(1.0, 0.97, 0.90);
    vec3 direct = (albedo / PI + spec) * sunColor * NdotL * 2.6;
    direct *= mix(1.0, ao, 0.25);

    vec3 sky = vec3(0.55, 0.68, 0.86);
    vec3 ambient = albedo * mix(vec3(0.40), sky, N.y * 0.5 + 0.5) * 0.85;
    ambient *= ao;

    vec3 lit = direct + ambient;

    float dist = distance(uCamPos, vWorld);
    float fog = clamp((dist - uFogStart) / (uFogEnd - uFogStart), 0.0, 1.0);
    outColor = vec4(mix(lit, uFogColor, fog), 1.0);
}
)GLSL";

const char* kWaterVert = R"GLSL(
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNrm;
layout(location = 2) in vec4 aCol;
uniform mat4 uMvp;
out vec3 vWorld;
out vec3 vNrm;
out vec4 vCol;
void main() {
    gl_Position = uMvp * vec4(aPos, 1.0);
    vWorld = aPos;
    vNrm = aNrm;
    vCol = aCol;
}
)GLSL";

const char* kWaterFrag = R"GLSL(
#version 330 core
in vec3 vWorld;
in vec3 vNrm;
in vec4 vCol;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uFogColor;
uniform float uFogEnd;
out vec4 outColor;
void main() {
    vec3 n = normalize(vNrm);
    vec3 viewDir = normalize(uCamPos - vWorld);
    float diff = max(dot(n, uSunDir), 0.0);
    float fres = pow(1.0 - max(dot(viewDir, n), 0.0), 3.0);
    vec3 col = vCol.rgb * (0.55 + 0.45 * diff);
    col = mix(col, vec3(0.9, 0.93, 0.97), fres * 0.35);
    float alpha = vCol.a;
    float dist = distance(uCamPos, vWorld);
    float fog = clamp(dist / uFogEnd, 0.0, 1.0);
    col = mix(col, uFogColor, fog);
    alpha *= 1.0 - fog * 0.7;
    outColor = vec4(col, alpha);
}
)GLSL";

const char* kBlockVert = R"GLSL(
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNrm;
layout(location = 2) in vec3 aOff;
layout(location = 3) in vec3 aCol;
uniform mat4 uMvp;
out vec3 vWorld;
out vec3 vNrm;
out vec3 vCol;
void main() {
    vec3 wp = aPos + aOff;
    gl_Position = uMvp * vec4(wp, 1.0);
    vWorld = wp;
    vNrm = aNrm;
    vCol = aCol;
}
)GLSL";

const char* kBlockFrag = R"GLSL(
#version 330 core
in vec3 vWorld;
in vec3 vNrm;
in vec3 vCol;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uFogColor;
uniform float uFogEnd;
out vec4 outColor;
void main() {
    vec3 n = normalize(vNrm);
    float diff = max(dot(n, uSunDir), 0.0);
    float hemi = max(n.y, 0.0) * 0.15;
    vec3 col = vCol * (0.42 + 0.58 * diff + hemi);
    float dist = distance(uCamPos, vWorld);
    float fog = clamp(dist / uFogEnd, 0.0, 1.0);
    col = mix(col, uFogColor, fog);
    outColor = vec4(col, 1.0);
}
)GLSL";

const char* kModelVert = R"GLSL(
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNrm;
layout(location = 2) in vec2 aUv;
uniform mat4 uMvp;
uniform mat4 uModel;
out vec3 vWorld;
out vec3 vNrm;
out vec2 vUv;
void main() {
    vec4 w = uModel * vec4(aPos, 1.0);
    gl_Position = uMvp * w;
    vWorld = w.xyz;
    vNrm = mat3(transpose(inverse(uModel))) * aNrm;
    vUv = aUv;
}
)GLSL";

const char* kModelFrag = R"GLSL(
#version 330 core
in vec3 vWorld;
in vec3 vNrm;
in vec2 vUv;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uFogColor;
uniform vec3 uColor;
uniform sampler2D uTex;
uniform float uFogEnd;
uniform float uUnlit;
out vec4 outColor;
void main() {
    vec3 n = normalize(vNrm);
    float diff = max(dot(n, uSunDir), 0.0);
    vec3 tex = texture(uTex, vUv).rgb;
    float light = 0.64 + 0.36 * diff + max(n.y, 0.0) * 0.08;
    vec3 col = uColor * tex * light;
    if (uUnlit > 0.5)
        col = uColor * tex;
    float dist = distance(uCamPos, vWorld);
    float fog = clamp(dist / uFogEnd, 0.0, 1.0);
    col = mix(col, uFogColor, fog);
    outColor = vec4(col, 1.0);
}
)GLSL";

const char* kSkinVert = R"GLSL(
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNrm;
layout(location = 2) in vec2 aUv;
layout(location = 3) in vec4 aJoints;
layout(location = 4) in vec4 aWeights;
uniform mat4 uMvp;
uniform mat4 uModel;
uniform mat4 uBones[32];
out vec3 vWorld;
out vec3 vNrm;
out vec2 vUv;
void main() {
    mat4 skin = uBones[int(aJoints.x)] * aWeights.x +
                uBones[int(aJoints.y)] * aWeights.y +
                uBones[int(aJoints.z)] * aWeights.z +
                uBones[int(aJoints.w)] * aWeights.w;
    vec4 lp = skin * vec4(aPos, 1.0);
    vec4 w = uModel * lp;
    gl_Position = uMvp * w;
    vWorld = w.xyz;
    vNrm = mat3(transpose(inverse(uModel))) * mat3(skin) * aNrm;
    vUv = aUv;
}
)GLSL";

const char* kUIVert = R"GLSL(
#version 330 core
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec4 aCol;
uniform vec2 uRes;
out vec4 vCol;
void main() {
    vec2 ndc = (aPos / uRes) * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
    vCol = aCol;
}
)GLSL";

const char* kUIFrag = R"GLSL(
#version 330 core
in vec4 vCol;
out vec4 outColor;
void main() { outColor = vCol; }
)GLSL";

const char* kTextVert = R"GLSL(
#version 330 core
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUv;
layout(location = 2) in vec4 aCol;
uniform vec2 uRes;
out vec2 vUv;
out vec4 vCol;
void main() {
    vec2 ndc = (aPos / uRes) * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
    vUv = aUv;
    vCol = aCol;
}
)GLSL";

const char* kTextFrag = R"GLSL(
#version 330 core
in vec2 vUv;
in vec4 vCol;
uniform sampler2D uTex;
out vec4 outColor;
void main() {
    float a = texture(uTex, vUv).r;
    outColor = vec4(vCol.rgb, vCol.a * a);
}
)GLSL";

const char* kPuffVert = R"GLSL(
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec4 aCol;
uniform mat4 uMvp;
uniform float uSize;
out vec4 vCol;
void main() {
    gl_Position = uMvp * vec4(aPos, 1.0);
    gl_PointSize = uSize;
    vCol = aCol;
}
)GLSL";

const char* kPuffFrag = R"GLSL(
#version 330 core
in vec4 vCol;
out vec4 outColor;
void main() {
    vec2 c = gl_PointCoord - 0.5;
    if (dot(c, c) > 0.25) discard;
    outColor = vCol;
}
)GLSL";

const char* kCrossVert = R"GLSL(
#version 330 core
layout(location = 0) in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }
)GLSL";

const char* kCrossFrag = R"GLSL(
#version 330 core
out vec4 outColor;
uniform vec3 uColor;
void main() { outColor = vec4(uColor, 1.0); }
)GLSL";

// ============================================================
// GL helpers
// ============================================================

void glCheckErrors(const char* where) {
    for (int i = 0; i < 8; ++i) {
        const GLenum err = glGetError();
        if (err == GL_NO_ERROR)
            break;
        const char* name = "GL_UNKNOWN";
        switch (err) {
            case GL_INVALID_ENUM: name = "GL_INVALID_ENUM"; break;
            case GL_INVALID_VALUE: name = "GL_INVALID_VALUE"; break;
            case GL_INVALID_OPERATION: name = "GL_INVALID_OPERATION"; break;
            case GL_OUT_OF_MEMORY: name = "GL_OUT_OF_MEMORY"; break;
            case GL_INVALID_FRAMEBUFFER_OPERATION:
                name = "GL_INVALID_FRAMEBUFFER_OPERATION";
                break;
            default: break;
        }
        bw::dbg::warn("OpenGL error %s (0x%04x) at %s", name, (unsigned)err,
                      where);
    }
}

GLuint compileShader(GLenum type, const char* src) {
    GLuint sh = glCreateShader(type);
    glShaderSource(sh, 1, &src, nullptr);
    glCompileShader(sh);
    GLint ok = 0;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[4096];
        glGetShaderInfoLog(sh, sizeof(log), nullptr, log);
        std::fprintf(stderr, "Shader error:\n%s\n", log);
        std::exit(1);
    }
    return sh;
}

GLuint makeProgram(const char* vs, const char* fs) {
    GLuint p = glCreateProgram();
    glAttachShader(p, compileShader(GL_VERTEX_SHADER, vs));
    glAttachShader(p, compileShader(GL_FRAGMENT_SHADER, fs));
    glLinkProgram(p);
    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[4096];
        glGetProgramInfoLog(p, sizeof(log), nullptr, log);
        std::fprintf(stderr, "Link error:\n%s\n", log);
        std::exit(1);
    }
    return p;
}

struct PageGL {
    GLuint vao = 0;
    GLuint vbo = 0;
    GLsizei vertexCount = 0;
};

struct WaterGL {
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint ebo = 0;
    GLsizei indexCount = 0;
};

struct SceneGL {
    std::unordered_map<int, GLuint> geom;
    std::unordered_map<int, GLuint> skinGeom; // skinned VAOs (geom index)
    std::unordered_map<int, GLsizei> tris;
    std::unordered_map<int, GLuint> tex;
    GLuint white = 0;
    glm::vec3 bmin{0}, bmax{0};
    bool ok = false;
};

GLuint makeWhiteTexture() {
    GLuint t = 0;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    const unsigned char one[4] = {255, 255, 255, 255};
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, one);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);
    return t;
}

GLuint makeFontTexture() {
    GLuint t = 0;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, bw::kFontAtlasW, bw::kFontAtlasH, 0,
                 GL_RED, GL_UNSIGNED_BYTE, bw::kFontAtlas);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);
    return t;
}

// ============================================================
// audio (mpv / paplay subprocesses - non-blocking)
// ============================================================

struct Audio {
    std::string root;
    bool enabled = true;
    bool musicEnabled = true;
    plat::ProcessHandle musicProc = 0;
    double musicRetry = 0.0;

    void play(const std::string& relative, int volume) const {
        if (!enabled)
            return;
        const std::string path = root + "/" + relative;
        if (!plat::fileReadable(path))
            return;
        const std::string vol = std::to_string(volume);
        // mpv first (with volume), paplay as a fallback; on platforms
        // without either the game simply stays silent
        if (plat::spawnDetached(
                {"mpv", "--no-video", "--really-quiet", "--volume=" + vol,
                 path}) == 0)
            plat::spawnDetached({"paplay", path});
    }

    void startMusic() {
        if (!enabled || !musicEnabled || musicProc != 0)
            return;
        const std::string path =
            root + "/assets/images/assest/background_music.mp3";
        if (!plat::fileReadable(path))
            return;
        musicProc = plat::spawnDetached({"mpv", "--no-video", "--really-quiet",
                                         "--loop-file=inf", "--volume=25",
                                         path});
    }

    void stopMusic() {
        if (musicProc == 0)
            return;
        plat::terminate(musicProc);
        if (!plat::waitExit(musicProc, 250)) {
#ifdef _WIN32
            plat::terminate(musicProc);
#else
            // escalate if the player ignored SIGTERM
            plat::terminate(musicProc);
#endif
        }
        plat::release(musicProc);
        musicProc = 0;
    }

    void update(double dt) {
        if (musicProc != 0 && !plat::alive(musicProc)) {
            plat::release(musicProc);
            musicProc = 0;
            musicRetry = 5.0; // no audio device: do not fork every frame
        }
        if (musicRetry > 0.0)
            musicRetry -= dt;
        if (enabled && musicEnabled && musicProc == 0 && musicRetry <= 0.0)
            startMusic();
    }

    void setMusic(bool on) {
        musicEnabled = on;
        if (on)
            startMusic();
        else
            stopMusic();
    }
};

// ============================================================
// app
// ============================================================

class App {
  public:
    int run();

  private:
    GLFWwindow* window_ = nullptr;
    std::unique_ptr<bw::Game> game_;
    bw::ui::MenuController menu_;
    bw::net::NetworkClient network_;
    bw::ui::Painter ui_;

    GLuint progTerrain_ = 0, progWater_ = 0, progBlock_ = 0, progModel_ = 0;
    GLuint progSkin_ = 0;
    GLuint terrainAlbedo_ = 0, terrainNormal_ = 0, terrainExtra_ = 0;
    bool terrainPbr_ = false;
    GLuint progUI_ = 0, progText_ = 0, progPuff_ = 0, progCross_ = 0;
    GLuint sharedEbo_ = 0, dummyVao_ = 0;
    GLuint cubeVao_ = 0, cubeVbo_ = 0, cubeIbo_ = 0, instVbo_ = 0;
    GLuint editorInstVbo_ = 0;
    GLuint uiVao_ = 0, uiVbo_ = 0, textVao_ = 0, textVbo_ = 0;
    GLuint puffVao_ = 0, puffVbo_ = 0;
    GLuint crossVao_ = 0, crossVbo_ = 0;
    GLuint fontTex_ = 0, whiteTex_ = 0;

    std::unordered_map<int64_t, PageGL> pageGL_;
    std::unordered_map<int64_t, WaterGL> waterGL_;

    model::Scene balloonScene_, arrowScene_, spawnerScene_, charScene_;
    SceneGL balloonGL_, arrowGL_, spawnerGL_, charGL_;

    // character animation: baked clip playback + procedural layers
    anim::Rig charRig_;
    std::vector<glm::mat4> poseLocals_, poseGlobals_, poseBones_;

    // baked glTF clip playback (Idle/Walk/Run)
    struct ClipPlayer {
        int clip = -1;
        int prev = -1;
        float time = 0.0f;
        float prevTime = 0.0f;
        float fade = 1.0f; // 0 -> 1 crossfade from prev to clip
    };
    struct PoseBuf {
        std::vector<glm::vec3> t, s;
        std::vector<glm::quat> r;
    };
    ClipPlayer playerClip_;
    std::unordered_map<int, ClipPlayer> remoteClips_;
    PoseBuf restPose_, poseA_, poseB_, poseMix_;
    int clipIdle_ = -1, clipWalk_ = -1, clipRun_ = -1;
    bool clipsReady_ = false;
    double animDt_ = 1.0 / 60.0;

    // state machines (player + remotes) and combat animation timers
    anim::Driver playerDriver_;
    std::unordered_map<int, anim::Driver> remoteDrivers_;
    double hitTimer_ = 0.0;
    double prevHealth_ = 100.0;

    bw::StructureEditorState editor_;
    bw::BlueprintLibrary blueprints_;
    int blueprintIndex_ = -1;

    struct Puff {
        glm::dvec3 pos{0};
        double life = 0.0;
    };
    std::vector<Puff> puffs_;
    bw::PlayerInput input_;
    uint64_t blocksVersion_ = ~0ULL;

    Audio audio_;

    bool menuOpen_ = true;
    bool mouseLocked_ = false;
    bool debugOverlay_ = false;
    double frameMs_ = 0.0;
    double frameMsPeak_ = 0.0;
    bool craftingOpen_ = false;
    int craftIndex_ = 0;
    bool chatActive_ = false;
    std::string chatInput_;
    bool chatJustOpened_ = false;
    std::string status_;
    double statusTimer_ = 0.0;
    double clickCooldown_ = 0.0;
    double buildCooldown_ = 0.0;
    double shootCooldown_ = 0.0;
    bool prevLmb_ = false;
    bool prevRmb_ = false;
    bool matchOver_ = false;
    bool editorMode_ = false;
    glm::ivec3 editorOrigin_{0, 0, 0};
    int editorPlane_ = 3;
    int editorBaseY_ = 0;

    struct RemotePlayer {
        int id = 0;
        std::string name;
        glm::dvec3 pos{0};
        glm::dvec3 targetPos{0};
        double yaw = 0;
        double targetYaw = 0;
        bool alive = true;
    };
    std::vector<RemotePlayer> remotes_;
    double netAccumulator_ = 0.0;
    bool networkGame_ = false;

    double lastTime_ = 0.0;
    double fpsTimer_ = 0.0;
    double elapsed_ = 0.0;
    int rPages_ = (int)R_PAGES;
    bool fastMode_ = false;
    int frames_ = 0;
    bool autoDigDone_ = false;
    bool autoBuildDone_ = false;
    bool autoShootDone_ = false;
    bool autoEditorDone_ = false;
    bool autoSaveDone_ = false;
    bool autoLoadDone_ = false;
    bool autoCraftDone_ = false;
    bool autoBlueprintDone_ = false;
    bool firstMouse_ = true;
    double lastMouseX_ = 0.0;
    double lastMouseY_ = 0.0;
    int fbW_ = WINDOW_WIDTH, fbH_ = WINDOW_HEIGHT;
    int winW_ = WINDOW_WIDTH, winH_ = WINDOW_HEIGHT;
    std::vector<std::pair<float, float>> menuHitboxes_;

    // ---- init ----
    bool initWindow();
    void initGL();
    void initGeometry();
    void initWorld(const bw::WorldConfig& cfg, const std::string& mode,
                   int characterId);
    void initModels();
    void initTerrainTextures();
    void initEditor();

    // ---- loop ----
    void frame(double dt);
    void handleContinuousInput(double dt);
    void handleKey(int key, int action, int mods);
    void handleMouseButton(int button, int action);
    void handleScroll(double yoff);
    void handleChar(unsigned int codepoint);
    void update(double dt);
    void render();

    void updatePages();
    void updateWater(double dt);
    void uploadDirtyPages();
    void updateBlockInstances();
    void pollNetwork(double dt);

    void renderTerrain();
    void renderBlocks();
    void renderEditor();
    void renderEntities();
    void renderWater();
    void renderPlayerModel();
    void renderViewmodel();
    void renderUI();

    void drawMenu();
    void drawHUD();
    void drawDebugOverlay();
    void drawCrafting();
    void drawEditorHUD();
    void drawMatchOver();
    std::string handleMenuAction(const std::string& action);

    // ---- helpers ----
    void tryDig();
    void tryBuild();
    void tryPlaceBlueprint();
    void cycleBlueprint();
    void tryAttack();
    void setStatus(const std::string& s);
    void loadGameFromDisk();
    void saveGameToDisk();
    void saveOnlineData();
    void applyOnlineSave(const nlohmann::json& data);
    void saveEditorToDisk();
    void loadEditorBlueprint();
    void cycleEditorGrid();
    void enterEditor();
    void leaveEditor();
    void applyRemoteState(const nlohmann::json& message);
    void drawSceneAt(const model::Scene& sc, const SceneGL& gl,
                     const glm::mat4& model, const glm::vec3& tint,
                     float unlit = 0.0f);
    void drawSkinned(const model::Scene& sc, const SceneGL& gl,
                     const glm::mat4& mvp, const glm::mat4& model,
                     const glm::vec3& tint,
                     const std::vector<glm::mat4>& bones);
    void initCharacterClips();
    void sampleClip(const model::Animation& anim, float time,
                    PoseBuf& out) const;
    void blendPose(const PoseBuf& a, const PoseBuf& b, float w,
                   PoseBuf& out) const;
    void applyPose(const PoseBuf& pose, std::vector<glm::mat4>& locals) const;
    void updateClipPlayer(ClipPlayer& cp, float dt, float speed01, bool running,
                          float rateScale = 1.0f);
    // base clip (or procedural fallback) + procedural layers -> bones
    void poseCharacter(ClipPlayer& cp, anim::Driver& driver,
                       const anim::Input& in, float speed01, bool running,
                       std::vector<glm::mat4>& bones);
    // fills the state machine inputs from the local player / a remote
    anim::Input playerAnimInput() const;
    anim::Input remoteAnimInput(const RemotePlayer& r) const;
    void setModelUniforms();
    glm::dvec3 cameraEye() const;
    glm::dvec3 cameraForward() const;

    static App* instance_;
    static void keyCallback(GLFWwindow*, int key, int, int action, int mods);
    static void charCallback(GLFWwindow*, unsigned int cp);
    static void mouseCallback(GLFWwindow*, double x, double y);
    static void mouseButtonCallback(GLFWwindow*, int button, int action, int);
    static void scrollCallback(GLFWwindow*, double, double yoff);
};

App* App::instance_ = nullptr;

// ============================================================
// init
// ============================================================

bool App::initWindow() {
    if (!glfwInit()) {
        std::fprintf(stderr, "GLFW init failed\n");
        return false;
    }
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    fastMode_ = std::getenv("BW_FAST") != nullptr;
    glfwWindowHint(GLFW_SAMPLES, fastMode_ ? 0 : 4);
    const int winW = fastMode_ ? 640 : WINDOW_WIDTH;
    const int winH = fastMode_ ? 360 : WINDOW_HEIGHT;
    window_ = glfwCreateWindow(winW, winH, "BalloonWar - C++ port", nullptr,
                               nullptr);
    if (!window_) {
        std::fprintf(stderr, "window creation failed\n");
        glfwTerminate();
        return false;
    }
    glfwMakeContextCurrent(window_);
    glfwSwapInterval(1);
    if (!glLoadFunctions()) {
        std::fprintf(stderr, "OpenGL function loading failed\n");
        return false;
    }
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_MULTISAMPLE);
    glDepthFunc(GL_LEQUAL);

    instance_ = this;
    glfwSetKeyCallback(window_, keyCallback);
    glfwSetCharCallback(window_, charCallback);
    glfwSetCursorPosCallback(window_, mouseCallback);
    glfwSetMouseButtonCallback(window_, mouseButtonCallback);
    glfwSetScrollCallback(window_, scrollCallback);
    glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    return true;
}

void App::initGL() {
    progTerrain_ = makeProgram(kTerrainVert, kTerrainFrag);
    progWater_ = makeProgram(kWaterVert, kWaterFrag);
    progBlock_ = makeProgram(kBlockVert, kBlockFrag);
    progModel_ = makeProgram(kModelVert, kModelFrag);
    progSkin_ = makeProgram(kSkinVert, kModelFrag);
    progUI_ = makeProgram(kUIVert, kUIFrag);
    progText_ = makeProgram(kTextVert, kTextFrag);
    progPuff_ = makeProgram(kPuffVert, kPuffFrag);
    progCross_ = makeProgram(kCrossVert, kCrossFrag);
    fontTex_ = makeFontTexture();
    whiteTex_ = makeWhiteTexture();
}

void App::initGeometry() {
    // shared page topology (65x65 grid)
    glGenVertexArrays(1, &dummyVao_);
    glGenBuffers(1, &sharedEbo_);
    glBindVertexArray(dummyVao_);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, sharedEbo_);
    {
        std::vector<uint32_t> idx;
        idx.reserve((size_t)world::PAGE_CELLS * world::PAGE_CELLS * 6);
        for (int z = 0; z < world::PAGE_CELLS; ++z)
            for (int x = 0; x < world::PAGE_CELLS; ++x) {
                const uint32_t a =
                    (uint32_t)(z * world::PAGE_VERTS + x);
                const uint32_t b = a + 1;
                const uint32_t c = a + world::PAGE_VERTS;
                const uint32_t d = c + 1;
                idx.push_back(a);
                idx.push_back(b);
                idx.push_back(d);
                idx.push_back(a);
                idx.push_back(d);
                idx.push_back(c);
            }
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx.size() * sizeof(uint32_t),
                     idx.data(), GL_STATIC_DRAW);
    }
    glBindVertexArray(0);

    // cube (2 m block) with pos/nrm/uv for model shader + instanced blocks
    const float s2 = (float)bw::BLOCK_CELL * 0.5f;
    const float p[24][3] = {
        {-s2, -s2, -s2}, {s2, -s2, -s2}, {s2, s2, -s2}, {-s2, s2, -s2},
        {-s2, -s2, s2},  {s2, -s2, s2},  {s2, s2, s2},  {-s2, s2, s2},
        {-s2, -s2, -s2}, {-s2, -s2, s2}, {-s2, s2, s2}, {-s2, s2, -s2},
        {s2, -s2, -s2},  {s2, -s2, s2},  {s2, s2, s2},  {s2, s2, -s2},
        {-s2, -s2, -s2}, {s2, -s2, -s2}, {s2, -s2, s2}, {-s2, -s2, s2},
        {-s2, s2, -s2},  {s2, s2, -s2},  {s2, s2, s2},  {-s2, s2, s2},
    };
    const float n[24][3] = {
        {0, 0, -1}, {0, 0, -1}, {0, 0, -1}, {0, 0, -1},
        {0, 0, 1},  {0, 0, 1},  {0, 0, 1},  {0, 0, 1},
        {-1, 0, 0}, {-1, 0, 0}, {-1, 0, 0}, {-1, 0, 0},
        {1, 0, 0},  {1, 0, 0},  {1, 0, 0},  {1, 0, 0},
        {0, -1, 0}, {0, -1, 0}, {0, -1, 0}, {0, -1, 0},
        {0, 1, 0},  {0, 1, 0},  {0, 1, 0},  {0, 1, 0},
    };
    const float uv[24][2] = {
        {0, 0}, {1, 0}, {1, 1}, {0, 1}, {0, 0}, {1, 0}, {1, 1}, {0, 1},
        {0, 0}, {1, 0}, {1, 1}, {0, 1}, {0, 0}, {1, 0}, {1, 1}, {0, 1},
        {0, 0}, {1, 0}, {1, 1}, {0, 1}, {0, 0}, {1, 0}, {1, 1}, {0, 1},
    };
    const uint32_t idx[36] = {0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4,
                              8, 9, 10, 10, 11, 8, 12, 13, 14, 14, 15, 12,
                              16, 17, 18, 18, 19, 16, 20, 21, 22, 22, 23, 20};
    glGenVertexArrays(1, &cubeVao_);
    glGenBuffers(1, &cubeVbo_);
    glGenBuffers(1, &cubeIbo_);
    glBindVertexArray(cubeVao_);
    glBindBuffer(GL_ARRAY_BUFFER, cubeVbo_);
    std::vector<float> vd;
    for (int i = 0; i < 24; ++i) {
        vd.insert(vd.end(), {p[i][0], p[i][1], p[i][2], n[i][0], n[i][1],
                             n[i][2], uv[i][0], uv[i][1]});
    }
    glBufferData(GL_ARRAY_BUFFER, vd.size() * sizeof(float), vd.data(),
                 GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, cubeIbo_);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(idx), idx, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)(3 * sizeof(float)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)(6 * sizeof(float)));
    glBindVertexArray(0);

    // instanced placed blocks (pos3 + col3)
    glGenBuffers(1, &instVbo_);
    glGenBuffers(1, &editorInstVbo_);

    // UI solid quads
    glGenVertexArrays(1, &uiVao_);
    glGenBuffers(1, &uiVbo_);
    glBindVertexArray(uiVao_);
    glBindBuffer(GL_ARRAY_BUFFER, uiVbo_);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                          (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                          (void*)(2 * sizeof(float)));
    glBindVertexArray(0);

    // UI text quads (pos2 + uv2 + rgba4)
    glGenVertexArrays(1, &textVao_);
    glGenBuffers(1, &textVbo_);
    glBindVertexArray(textVao_);
    glBindBuffer(GL_ARRAY_BUFFER, textVbo_);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)(2 * sizeof(float)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)(4 * sizeof(float)));
    glBindVertexArray(0);

    // points (balloon pops / arrow impacts)
    glGenVertexArrays(1, &puffVao_);
    glGenBuffers(1, &puffVbo_);
    glBindVertexArray(puffVao_);
    glBindBuffer(GL_ARRAY_BUFFER, puffVbo_);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 7 * sizeof(float),
                          (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 7 * sizeof(float),
                          (void*)(3 * sizeof(float)));
    glBindVertexArray(0);

    // crosshair
    {
        const float l = 0.012f, g = 0.0026f;
        const float v[8] = {-g, -l, g, -l, -l, -g, -l, g};
        glGenVertexArrays(1, &crossVao_);
        glGenBuffers(1, &crossVbo_);
        glBindVertexArray(crossVao_);
        glBindBuffer(GL_ARRAY_BUFFER, crossVbo_);
        glBufferData(GL_ARRAY_BUFFER, sizeof(v), v, GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
        glBindVertexArray(0);
    }
}

void App::initModels() {
    const std::string root = bw::findProjectRoot();
    audio_.root = root;
    audio_.enabled = std::getenv("BW_NO_AUDIO") == nullptr;
    struct ModelDef {
        const char* path;
        model::Scene* scene;
        SceneGL* gl;
    };
    const ModelDef defs[] = {
        {"models/balloon/ballon.glb", &balloonScene_, &balloonGL_},
        {"models/arrow/arrow.glb", &arrowScene_, &arrowGL_},
        {"models/spawner/Meshy_AI_a_ballon_spawner_mine_0526161540_texture.glb",
         &spawnerScene_, &spawnerGL_},
        {"models/characters/baiaat.glb", &charScene_, &charGL_},
    };
    for (const auto& def : defs) {
        const std::string path = root + "/" + def.path;
        if (!model::loadGLBScene(path, *def.scene, nullptr)) {
            std::printf("[model missing: %s]\n", def.path);
            bw::dbg::warn("model missing: %s", def.path);
            continue;
        }
        // the automatic UV unwrap of the shipped meshes overlaps; pack
        // the islands once so the rendered mesh and the baked texture
        // use the same mapping
        if (!std::getenv("BW_NO_BAKE")) {
            // only the untextured models (character, arrow) go through
            // the procedural baker; models with embedded textures keep
            // their own UVs
            bool needsBake = false;
            for (const auto& gm : def.scene->geoms)
                if (gm.texImage < 0)
                    needsBake = true;
            if (needsBake) {
                const auto t0 = std::chrono::steady_clock::now();
                bake::repackSceneUVs(*def.scene);
                bw::dbg::info("uv repack %s: %.0f ms", def.path,
                              std::chrono::duration<double, std::milli>(
                                  std::chrono::steady_clock::now() - t0)
                                  .count());
            }
        }
        SceneGL& gl = *def.gl;
        for (int g = 0; g < (int)def.scene->geoms.size(); ++g) {
            const auto& gm = def.scene->geoms[g];
            GLuint vao = 0, vbo = 0, ebo = 0;
            glGenVertexArrays(1, &vao);
            glGenBuffers(1, &vbo);
            glGenBuffers(1, &ebo);
            glBindVertexArray(vao);
            glBindBuffer(GL_ARRAY_BUFFER, vbo);
            glBufferData(GL_ARRAY_BUFFER,
                         (GLsizeiptr)(gm.verts.size() * sizeof(float)),
                         gm.verts.data(), GL_STATIC_DRAW);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
            glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                         (GLsizeiptr)(gm.indices.size() * sizeof(uint32_t)),
                         gm.indices.data(), GL_STATIC_DRAW);
            glEnableVertexAttribArray(0);
            glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                                  (void*)0);
            glEnableVertexAttribArray(1);
            glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                                  (void*)(3 * sizeof(float)));
            glEnableVertexAttribArray(2);
            glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                                  (void*)(6 * sizeof(float)));
            glBindVertexArray(0);
            gl.geom[g] = vao;
            gl.tris[g] = (GLsizei)gm.indices.size();
            if (gm.skinned) {
                GLuint svao = 0, svbo = 0, sebo = 0, jvbo = 0, wvbo = 0;
                glGenVertexArrays(1, &svao);
                glGenBuffers(1, &svbo);
                glGenBuffers(1, &sebo);
                glGenBuffers(1, &jvbo);
                glGenBuffers(1, &wvbo);
                glBindVertexArray(svao);
                glBindBuffer(GL_ARRAY_BUFFER, svbo);
                glBufferData(GL_ARRAY_BUFFER,
                             (GLsizeiptr)(gm.verts.size() * sizeof(float)),
                             gm.verts.data(), GL_STATIC_DRAW);
                glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, sebo);
                glBufferData(
                    GL_ELEMENT_ARRAY_BUFFER,
                    (GLsizeiptr)(gm.indices.size() * sizeof(uint32_t)),
                    gm.indices.data(), GL_STATIC_DRAW);
                glEnableVertexAttribArray(0);
                glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE,
                                      8 * sizeof(float), (void*)0);
                glEnableVertexAttribArray(1);
                glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE,
                                      8 * sizeof(float),
                                      (void*)(3 * sizeof(float)));
                glEnableVertexAttribArray(2);
                glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE,
                                      8 * sizeof(float),
                                      (void*)(6 * sizeof(float)));
                glBindBuffer(GL_ARRAY_BUFFER, jvbo);
                glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)gm.joints.size(),
                             gm.joints.data(), GL_STATIC_DRAW);
                glEnableVertexAttribArray(3);
                glVertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_FALSE, 0,
                                      nullptr);
                glBindBuffer(GL_ARRAY_BUFFER, wvbo);
                glBufferData(GL_ARRAY_BUFFER,
                             (GLsizeiptr)(gm.weights.size() * sizeof(float)),
                             gm.weights.data(), GL_STATIC_DRAW);
                glEnableVertexAttribArray(4);
                glVertexAttribPointer(4, 4, GL_FLOAT, GL_FALSE, 0, nullptr);
                glBindVertexArray(0);
                gl.skinGeom[g] = svao;
            }
        }
        for (int i = 0; i < (int)def.scene->images.size(); ++i) {
            if (!def.scene->images[i].ok)
                continue;
            GLuint t = 0;
            glGenTextures(1, &t);
            glBindTexture(GL_TEXTURE_2D, t);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                            GL_LINEAR_MIPMAP_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8,
                         def.scene->images[i].w, def.scene->images[i].h, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE,
                         def.scene->images[i].rgba.data());
            glGenerateMipmap(GL_TEXTURE_2D);
            gl.tex[i] = t;
        }
        gl.white = whiteTex_;
        gl.bmin = def.scene->bmin;
        gl.bmax = def.scene->bmax;
        gl.ok = true;
        std::printf("[model loaded: %s]\n", def.path);
    }
    if (charScene_.ok && charScene_.skinned()) {
        charRig_ = anim::Rig::map(charScene_);
        bw::dbg::info("character rig: %zu joints, %zu skins, bones %s",
                      charScene_.nodeNames.size(), charScene_.skins.size(),
                      charRig_.valid ? "mapped" : "incomplete");
    } else {
        bw::dbg::warn("character model has no skin; animation disabled");
    }
    initCharacterClips();
    playerDriver_.reset(0.0f);

    // the .glb files ship without materials: bake procedural albedo
    // textures from the mesh (deterministic, no external assets)
    if (!std::getenv("BW_NO_BAKE")) {
        auto upload = [&](SceneGL& gl, const bake::Image& img) {
            if (!img.ok())
                return;
            GLuint t = 0;
            glGenTextures(1, &t);
            glBindTexture(GL_TEXTURE_2D, t);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                            GL_LINEAR_MIPMAP_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, img.w, img.h, 0, GL_RGBA,
                         GL_UNSIGNED_BYTE, img.rgba.data());
            glGenerateMipmap(GL_TEXTURE_2D);
            // key -1 is the fallback used by drawSkinned/drawSceneAt for
            // geometries without a material texture
            gl.tex[-1] = t;
        };
        bool charHasTexture = false;
        for (const auto& gm : charScene_.geoms)
            if (gm.texImage >= 0)
                charHasTexture = true;
        bool arrowHasTexture = false;
        for (const auto& gm : arrowScene_.geoms)
            if (gm.texImage >= 0)
                arrowHasTexture = true;
        if (charGL_.ok && !charHasTexture) {
            const auto tb = std::chrono::steady_clock::now();
            const bake::Image img = bake::characterTexture(charScene_, 1024);
            bw::dbg::info("character bake: %.0f ms",
                          std::chrono::duration<double, std::milli>(
                              std::chrono::steady_clock::now() - tb)
                              .count());
            upload(charGL_, img);
            bw::dbg::info("character texture baked: %dx%d", img.w, img.h);
            if (std::getenv("BW_DUMP_TEX") && img.ok()) {
                std::FILE* f = std::fopen("/tmp/balloonwar_char_tex.ppm", "wb");
                if (f) {
                    std::fprintf(f, "P6\n%d %d\n255\n", img.w, img.h);
                    for (size_t i = 0; i < (size_t)img.w * img.h; ++i)
                        std::fwrite(&img.rgba[i * 4], 1, 3, f);
                    std::fclose(f);
                    std::printf("[char texture dumped]\n");
                }
            }
        }
        if (arrowGL_.ok && !arrowHasTexture) {
            const bake::Image img = bake::arrowTexture(arrowScene_, 512);
            upload(arrowGL_, img);
        }
    }
}

void App::initTerrainTextures() {
    terrainPbr_ = std::getenv("BW_TERRAIN_TEX") == nullptr;
    if (!terrainPbr_)
        return;
    const std::string root = bw::findProjectRoot();
    const int size = std::getenv("BW_TERRAIN_TEX_SIZE")
                         ? std::atoi(std::getenv("BW_TERRAIN_TEX_SIZE"))
                         : 256;
    const auto layers = terraintex::generate(size, root);

    auto uploadArray = [&](std::vector<bake::Image>& images) {
        GLuint tex = 0;
        glGenTextures(1, &tex);
        glBindTexture(GL_TEXTURE_2D_ARRAY, tex);
        glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RGBA8, size, size,
                     (GLsizei)images.size(), 0, GL_RGBA, GL_UNSIGNED_BYTE,
                     nullptr);
        for (size_t i = 0; i < images.size(); ++i)
            glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, (GLint)i, size, size,
                            1, GL_RGBA, GL_UNSIGNED_BYTE,
                            images[i].rgba.data());
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER,
                        GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_REPEAT);
        if (glfwExtensionSupported("GL_EXT_texture_filter_anisotropic")) {
            GLfloat maxAniso = 1.0f;
            glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &maxAniso);
            glTexParameterf(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_ANISOTROPY_EXT,
                            std::min(8.0f, maxAniso));
        }
        glGenerateMipmap(GL_TEXTURE_2D_ARRAY);
        return tex;
    };
    std::vector<bake::Image> albedo, normal, extra;
    for (const auto& l : layers) {
        albedo.push_back(l.albedoRough);
        normal.push_back(l.normal);
        extra.push_back(l.extra);
    }
    terrainAlbedo_ = uploadArray(albedo);
    terrainNormal_ = uploadArray(normal);
    terrainExtra_ = uploadArray(extra);
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0);
    int fromFile = 0;
    for (const auto& l : layers)
        if (l.source == "file")
            ++fromFile;
    bw::dbg::info("terrain PBR textures: %zu layers %dpx (%d from assets)",
                  layers.size(), size, fromFile);
}

void App::initWorld(const bw::WorldConfig& cfg, const std::string& mode,
                    int characterId) {
    terrain::SEED = cfg.world_seed;
    terrain::TERRAIN_SCALE =
        std::max(cfg.terrain_frequency, 0.0001) / 0.018;
    terrain::WARP_STRENGTH =
        250.0 * std::max(cfg.terrain_warp_strength, 0.0) / 5.0;
    terrain::LAND_CURVE = std::max(cfg.terrain_curve, 0.01) / 0.7;
    terrain::RIDGE_FACTOR = std::max(cfg.ridge_strength, 0.0) / 0.8;
    terrain::RELIEF_SCALE = std::clamp(cfg.relief_scale, 1.0, 50.0);
    if (cfg.custom_range) {
        terrain::CUSTOM_MIN = cfg.surface_min_height;
        terrain::CUSTOM_MAX = cfg.surface_max_height;
    } else {
        terrain::CUSTOM_MIN = -1e9;
        terrain::CUSTOM_MAX = 1e9;
    }
    std::printf("[generating terrain seed=%d...]\n", cfg.world_seed);
    bw::dbg::info("generating world: seed=%d mode=%s relief=%.2f", cfg.world_seed,
                  mode.c_str(), cfg.relief_scale);
    game_ = std::make_unique<bw::Game>(cfg, mode, characterId, cfg.world_seed);
    bw::dbg::info("world ready: blocks=%zu pages=%zu", game_->blocks.count(),
                  game_->terrain.pages().size());
    pageGL_.clear();
    waterGL_.clear();
    blocksVersion_ = ~0ULL;
    remotes_.clear();
    remoteClips_.clear();
    remoteDrivers_.clear();
    puffs_.clear();
    matchOver_ = false;
    std::printf("[world ready]\n");
}

void App::initEditor() {
    editor_ = bw::StructureEditorState();
    editorOrigin_ = glm::ivec3(
        (int)std::floor(game_->player.pos.x / bw::BLOCK_CELL), 0,
        (int)std::floor(game_->player.pos.z / bw::BLOCK_CELL));
    editorBaseY_ = (int)bw::blockCellOf(game_->terrain.heightAt(
                       editorOrigin_.x * bw::BLOCK_CELL,
                       editorOrigin_.z * bw::BLOCK_CELL)) +
                   3;
    const std::string home = std::getenv("HOME") ? std::getenv("HOME") : ".";
    const std::string root = bw::findProjectRoot();
    blueprints_.scan({
        root + "/resources/blueprints",
        root + "/src/balloonwar/data/blueprints",
        home + "/.local/share/balloonwar/blueprints",
    });
    blueprintIndex_ = -1;
    if (!blueprints_.list().empty()) {
        blueprintIndex_ = 0;
        menu_.editorBlueprint = blueprints_.list()[0].name;
    }
    editorMode_ = true;
    game_->sessionMode = "structure_editor";
    menu_.editorMode = true;
    menu_.saveLabel = "SALVEAZA STRUCTURA";
    game_->player.cameraMode = bw::CAMERA_FREECAM;
    game_->player.freecamPos =
        glm::dvec3(editorOrigin_.x * bw::BLOCK_CELL,
                   bw::blockCellMin(editorBaseY_ + 5), 
                   editorOrigin_.z * bw::BLOCK_CELL);
    game_->player.yaw = 0.0;
    game_->player.pitch = -0.5;
    menuOpen_ = true;
    mouseLocked_ = false;
    glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
}

void App::leaveEditor() {
    editorMode_ = false;
    game_->sessionMode = "singleplayer";
    menu_.editorMode = false;
    menu_.saveLabel = "SALVEAZA JOC";
    game_->player.cameraMode = bw::CAMERA_FIRST_PERSON;
}

// ============================================================
// input
// ============================================================

void App::keyCallback(GLFWwindow*, int key, int, int action, int mods) {
    if (instance_)
        instance_->handleKey(key, action, mods);
}

void App::charCallback(GLFWwindow*, unsigned int cp) {
    if (instance_)
        instance_->handleChar(cp);
}

void App::mouseCallback(GLFWwindow*, double x, double y) {
    App* app = instance_;
    if (!app)
        return;
    if (app->firstMouse_) {
        app->lastMouseX_ = x;
        app->lastMouseY_ = y;
        app->firstMouse_ = false;
    }
    const double dx = x - app->lastMouseX_;
    const double dy = y - app->lastMouseY_;
    app->lastMouseX_ = x;
    app->lastMouseY_ = y;
    if (app->mouseLocked_ && app->game_)
        app->game_->player.mouseMove(dx, dy);
}

void App::mouseButtonCallback(GLFWwindow*, int button, int action, int) {
    if (instance_)
        instance_->handleMouseButton(button, action);
}

void App::scrollCallback(GLFWwindow*, double, double yoff) {
    if (instance_)
        instance_->handleScroll(yoff);
}

void App::handleChar(unsigned int cp) {
    if (chatActive_ && cp >= 32 && cp < 127) {
        chatInput_.push_back((char)cp);
        return;
    }
    if (menuOpen_ && !menu_.activeField.empty() && cp >= 32 && cp < 127) {
        std::string s(1, (char)cp);
        menu_.inputText(s);
    }
}

void App::handleScroll(double yoff) {
    if (!game_)
        return;
    if (menuOpen_ && menu_.screen == "creator") {
        const auto items = menu_.items(false, false, false, false, {});
        menu_.adjustCreator(yoff > 0 ? 1 : -1, items);
        return;
    }
    if (editorMode_) {
        editorPlane_ = std::clamp(editorPlane_ + (yoff > 0 ? 1 : -1), 0, 30);
        return;
    }
    if (mouseLocked_) {
        auto& inv = game_->player.inventory;
        inv.selected = (inv.selected + (yoff > 0 ? -1 : 1) + bw::kInventorySlots) %
                       bw::kInventorySlots;
    }
}

void App::handleKey(int key, int action, int) {
    if (action != GLFW_PRESS && action != GLFW_REPEAT)
        return;
    if (!game_)
        return;

    if (chatActive_) {
        if (key == GLFW_KEY_ENTER) {
            network_.sendChat(chatInput_);
            chatInput_.clear();
            chatActive_ = false;
        } else if (key == GLFW_KEY_ESCAPE) {
            chatActive_ = false;
            chatInput_.clear();
        } else if (key == GLFW_KEY_BACKSPACE && !chatInput_.empty()) {
            chatInput_.pop_back();
        }
        return;
    }

    if (key == GLFW_KEY_ESCAPE) {
        if (menuOpen_ && menu_.screen != "main") {
            menu_.show("main");
            return;
        }
        menuOpen_ = !menuOpen_;
        mouseLocked_ = !menuOpen_;
        if (!menuOpen_)
            menu_.activeField.clear();
        glfwSetInputMode(window_, GLFW_CURSOR,
                         mouseLocked_ ? GLFW_CURSOR_DISABLED
                                      : GLFW_CURSOR_NORMAL);
        firstMouse_ = true;
        return;
    }

    if (menuOpen_) {
        const auto items = menu_.items(true, network_.state.loggedIn,
                                       network_.state.inRoom,
                                       network_.state.isHost,
                                       network_.state.roomList,
                                       network_.state.roomIds);
        if (!menu_.activeField.empty()) {
            if (key == GLFW_KEY_BACKSPACE)
                menu_.backspace();
            else if (key == GLFW_KEY_ENTER || key == GLFW_KEY_KP_ENTER)
                setStatus(handleMenuAction(menu_.activate(items)));
            else if (key == GLFW_KEY_ESCAPE) {
                menu_.activeField.clear();
                menuOpen_ = false;
                mouseLocked_ = true;
                glfwSetInputMode(window_, GLFW_CURSOR,
                                 GLFW_CURSOR_DISABLED);
                firstMouse_ = true;
            }
            return;
        }
        if (key == GLFW_KEY_UP || key == GLFW_KEY_W) {
            menu_.move(-1, items);
            return;
        }
        if (key == GLFW_KEY_DOWN || key == GLFW_KEY_S) {
            menu_.move(1, items);
            return;
        }
        if (key == GLFW_KEY_LEFT || key == GLFW_KEY_RIGHT) {
            if (menu_.screen == "creator")
                menu_.adjustCreator(key == GLFW_KEY_RIGHT ? 1 : -1, items);
            return;
        }
        if (key == GLFW_KEY_BACKSPACE) {
            menu_.backspace();
            return;
        }
        if (key == GLFW_KEY_ENTER || key == GLFW_KEY_KP_ENTER) {
            setStatus(handleMenuAction(menu_.activate(items)));
            return;
        }
        return;
    }

    if (matchOver_) {
        if (key == GLFW_KEY_ENTER) {
            matchOver_ = false;
            menuOpen_ = true;
            mouseLocked_ = false;
            glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
            menu_.show("main");
        }
        return;
    }

    auto& p = game_->player;
    if (key >= GLFW_KEY_1 && key <= GLFW_KEY_9)
        p.inventory.selected = key - GLFW_KEY_1;
    if (key == GLFW_KEY_0)
        p.inventory.selected = 9;
    if (key == GLFW_KEY_Q)
        p.weapon = (p.weapon + 1) % 2;
    if (key == GLFW_KEY_P)
        cycleBlueprint();
    if (key == GLFW_KEY_B)
        p.digMode = p.digMode == bw::DIG_MODE_CUBE ? bw::DIG_MODE_SPHERE
                                                   : bw::DIG_MODE_CUBE;
    if (key == GLFW_KEY_V)
        p.interactionMode = (p.interactionMode + 1) % 3;
    if (key == GLFW_KEY_M)
        p.interactionMode = bw::INTERACT_DIG;
    if (key == GLFW_KEY_Z)
        p.interactionMode = bw::INTERACT_BUILD;
    if (key == GLFW_KEY_X)
        p.interactionMode = bw::INTERACT_COMBAT;
    if (key == GLFW_KEY_C) {
        p.cameraMode = p.cameraMode == bw::CAMERA_FIRST_PERSON
                           ? bw::CAMERA_THIRD_PERSON
                           : bw::CAMERA_FIRST_PERSON;
    }
    if (key == GLFW_KEY_F) {
        if (p.cameraMode != bw::CAMERA_FREECAM) {
            p.cameraMode = bw::CAMERA_FREECAM;
            p.freecamPos = p.eye();
        } else {
            p.cameraMode = bw::CAMERA_FIRST_PERSON;
        }
    }
    if (key == GLFW_KEY_I)
        craftingOpen_ = !craftingOpen_;
    if (key == GLFW_KEY_T && networkGame_)
        chatActive_ = true;
    if (key == GLFW_KEY_R && p.dead)
        p.respawn();
    if (key == GLFW_KEY_F5)
        saveGameToDisk();
    if (key == GLFW_KEY_F3)
        debugOverlay_ = !debugOverlay_;

    if (craftingOpen_) {
        const auto& recipes = game_->crafting.recipes();
        if (key == GLFW_KEY_DOWN && !recipes.empty())
            craftIndex_ = (craftIndex_ + 1) % (int)recipes.size();
        if (key == GLFW_KEY_UP && !recipes.empty())
            craftIndex_ = (craftIndex_ + (int)recipes.size() - 1) %
                          (int)recipes.size();
        if (key == GLFW_KEY_ENTER && !recipes.empty()) {
            const auto& r = recipes[craftIndex_ % recipes.size()];
            if (game_->crafting.craft(r, p.inventory.counts))
                setStatus("CRAFTAT: " + r.name);
            else
                setStatus("NU AI RESURSE PENTRU " + r.name);
        }
        return;
    }
}

void App::handleMouseButton(int button, int action) {
    if (!game_)
        return;
    if (menuOpen_) {
        if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS) {
            double mx = 0, my = 0;
            glfwGetCursorPos(window_, &mx, &my);
            const double sx = winW_ > 0 ? (double)fbW_ / winW_ : 1.0;
            const double sy = winH_ > 0 ? (double)fbH_ / winH_ : 1.0;
            const float fx = (float)(mx * sx);
            const float fy = (float)(my * sy);
            const auto items = menu_.items(
                true, network_.state.loggedIn, network_.state.inRoom,
                network_.state.isHost, network_.state.roomList,
                network_.state.roomIds);
            for (size_t i = 0; i < menuHitboxes_.size() && i < items.size();
                 ++i) {
                const auto [x0, y0] = menuHitboxes_[i];
                const float w = std::min(520.0f, (float)fbW_ - 60.0f);
                const float h = menuHitboxes_.size() > 0
                                    ? 42.0f
                                    : 42.0f;
                if (items[i].enabled && fx >= x0 && fx <= x0 + w &&
                    fy >= y0 && fy <= y0 + h) {
                    menu_.selected = (int)i;
                    setStatus(handleMenuAction(menu_.activate(items)));
                    break;
                }
            }
        }
        return;
    }
    if (!mouseLocked_ || matchOver_)
        return;
    const bool pressed = action == GLFW_PRESS;
    if (button == GLFW_MOUSE_BUTTON_LEFT && pressed) {
        if (editorMode_) {
            // handled in handleContinuousInput via click flags
        } else if (game_->player.interactionMode == bw::INTERACT_DIG) {
            tryDig();
        } else if (game_->player.interactionMode == bw::INTERACT_BUILD) {
            tryBuild();
        } else {
            tryAttack();
        }
    } else if (button == GLFW_MOUSE_BUTTON_RIGHT && pressed) {
        if (!editorMode_ &&
            game_->player.interactionMode != bw::INTERACT_COMBAT) {
            if (!blueprints_.list().empty())
                tryPlaceBlueprint();
            else
                tryBuild();
        }
    }
}

// ============================================================
// actions
// ============================================================

void App::setStatus(const std::string& s) {
    if (s.empty())
        return;
    status_ = s;
    statusTimer_ = 4.0;
}

void App::tryDig() {
    if (clickCooldown_ > 0.0)
        return;
    const auto pick =
        game_->player.rayPick(game_->blocks, game_->terrain);
    if (game_->player.tryDig(game_->blocks, game_->terrain)) {
        clickCooldown_ = 0.18;
        audio_.play("assets/audio/arrowhit.wav", 45);
        if (networkGame_ && pick.hit)
            network_.sendTerrainModify(pick.cell.x, pick.cell.y, pick.cell.z,
                                       "dig", 0);
    }
}

void App::tryBuild() {
    if (buildCooldown_ > 0.0)
        return;
    if (game_->player.tryBuild(game_->blocks, game_->terrain)) {
        buildCooldown_ = 0.22;
        audio_.play("assets/audio/arrowhit.wav", 40);
        if (networkGame_) {
            const auto pick =
                game_->player.rayPick(game_->blocks, game_->terrain);
            if (pick.hit && pick.isBlock)
                network_.sendTerrainModify(
                    pick.cell.x, pick.cell.y, pick.cell.z, "build",
                    game_->blocks.idAt(pick.cell));
        }
    }
}

void App::cycleBlueprint() {
    const auto& list = blueprints_.list();
    if (list.empty()) {
        setStatus("NICIO STRUCTURA DISPONIBILA");
        return;
    }
    blueprintIndex_ = (blueprintIndex_ + 1) % (int)list.size();
    menu_.editorBlueprint = list[blueprintIndex_].name;
    setStatus("BLUEPRINT: " + list[blueprintIndex_].name);
}

void App::tryPlaceBlueprint() {
    const auto& list = blueprints_.list();
    if (list.empty() || blueprintIndex_ < 0 || blueprintIndex_ >= (int)list.size())
        return;
    std::map<bw::Cell, uint8_t> bp;
    if (!blueprints_.load(list[blueprintIndex_], bp) || bp.empty())
        return;
    const auto pick = game_->player.rayPick(game_->blocks, game_->terrain);
    if (!pick.hit)
        return;
    const bw::Cell origin = pick.placement;
    // every cell must be free
    for (const auto& [c, t] : bp) {
        (void)t;
        const bw::Cell w{origin.x + c.x, origin.y + c.y, origin.z + c.z};
        if (game_->blocks.has(w)) {
            setStatus("STRUCTURA INTERSECTEAZA BLOCURI");
            return;
        }
    }
    // consume the blocks from the inventory (unless unlimited)
    auto& inv = game_->player.inventory;
    if (!inv.unlimited) {
        std::array<int, bw::kBlockTypeCount> need{};
        for (const auto& [c, t] : bp) {
            (void)c;
            if (t > 0 && t < bw::kBlockTypeCount)
                need[t] += 1;
        }
        for (int i = 0; i < bw::kBlockTypeCount; ++i)
            if (need[i] > inv.counts[i]) {
                setStatus("NU AI DESTULE BLOCURI PENTRU STRUCTURA");
                return;
            }
        for (int i = 0; i < bw::kBlockTypeCount; ++i)
            inv.counts[i] -= need[i];
    }
    for (const auto& [c, t] : bp)
        game_->blocks.place(
            {origin.x + c.x, origin.y + c.y, origin.z + c.z}, t, true);
    buildCooldown_ = 0.4;
    setStatus("STRUCTURA PLASATA: " + list[blueprintIndex_].name);
}

void App::tryAttack() {
    auto& p = game_->player;
    if (p.weapon == bw::WEAPON_CROSSBOW) {
        if (shootCooldown_ > 0.0)
            return;
        shootCooldown_ = 0.45;
        game_->enemies.addArrow(p.shootArrow());
        audio_.play("assets/audio/rele.wav", 55);
    } else {
        p.attackSword(game_->enemies);
        audio_.play("assets/audio/arrowhit.wav", 50);
    }
}

void App::loadGameFromDisk() {
    const std::string path = bw::defaultSavePath();
    std::ifstream f(path);
    if (!f) {
        setStatus("NU EXISTA SALVARE");
        return;
    }
    nlohmann::json j;
    try {
        f >> j;
    } catch (...) {
        setStatus("SALVARE CORUPTA");
        return;
    }
    bw::WorldConfig cfg;
    cfg.world_seed = j.value("seed", 1337);
    if (j.contains("config")) {
        const auto& c = j["config"];
        cfg.surface_min_height = c.value("surface_min_height", 32.0);
        cfg.surface_max_height = c.value("surface_max_height", 96.0);
        cfg.terrain_frequency = c.value("terrain_frequency", 0.018);
        cfg.terrain_detail_frequency =
            c.value("terrain_detail_frequency", 0.03);
        cfg.terrain_warp_strength = c.value("terrain_warp_strength", 5.0);
        cfg.terrain_curve = c.value("terrain_curve", 0.7);
        cfg.biome_frequency = c.value("biome_frequency", 0.0035);
        cfg.biome_amplitude = c.value("biome_amplitude", 3.0);
        cfg.ridge_strength = c.value("ridge_strength", 0.8);
        cfg.ridge_mix = c.value("ridge_mix", 0.05);
        cfg.tree_density = c.value("tree_density", 1.0);
        cfg.relief_scale = c.value("relief_scale", 3.0);
        cfg.cave_enabled = c.value("cave_enabled", true);
        cfg.custom_range = c.value("custom_range", false);
    }
    const std::string mode = j.value("mode", "classic");
    initWorld(cfg, mode, menu_.selectedCharacter);
    if (!game_->load(path)) {
        setStatus("SALVAREA NU A PUTUT FI INCARCATA");
        return;
    }
    menu_.seedText = std::to_string(cfg.world_seed);
    menu_.inGame = true;
    menuOpen_ = false;
    mouseLocked_ = true;
    glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    firstMouse_ = true;
    setStatus("JOC INCARCAT");
}

void App::saveGameToDisk() {
    if (editorMode_) {
        saveEditorToDisk();
        return;
    }
    if (game_->save(bw::defaultSavePath())) {
        setStatus("JOC SALVAT");
        bw::dbg::info("game saved to %s", bw::defaultSavePath().c_str());
    } else {
        setStatus("SALVAREA A ESUAT");
        bw::dbg::error("save failed: %s", bw::defaultSavePath().c_str());
    }
    if (networkGame_ && network_.state.inRoom)
        saveOnlineData();
}

void App::saveOnlineData() {
    nlohmann::json data;
    data["version"] = 3;
    data["world_seed"] = game_->config.world_seed;
    data["world_config"] = {
        {"surface_min_height", game_->config.surface_min_height},
        {"surface_max_height", game_->config.surface_max_height},
        {"terrain_frequency", game_->config.terrain_frequency},
        {"terrain_warp_strength", game_->config.terrain_warp_strength},
        {"terrain_curve", game_->config.terrain_curve},
        {"ridge_strength", game_->config.ridge_strength},
        {"biome_frequency", game_->config.biome_frequency},
        {"tree_density", game_->config.tree_density},
        {"relief_scale", game_->config.relief_scale},
    };
    const auto& p = game_->player;
    data["player"] = {
        {"position", {p.pos.x, p.pos.y, p.pos.z}},
        {"spawn_position", {p.spawnPos.x, p.spawnPos.y, p.spawnPos.z}},
        {"yaw", p.yaw},
        {"pitch", p.pitch},
        {"health", p.health},
        {"score", p.score},
        {"kills", p.balloonsPopped},
        {"weapon", p.weapon},
        {"interaction_mode", p.interactionMode},
        {"dig_mode", p.digMode},
        {"selected_slot", p.inventory.selected},
        {"inventory", nlohmann::json::object()},
    };
    for (int i = 0; i < bw::kBlockTypeCount; ++i)
        data["player"]["inventory"][std::to_string(i)] =
            p.inventory.counts[i];
    nlohmann::json placed = nlohmann::json::array();
    for (const auto& [c, id] : game_->blocks.map())
        placed.push_back({c.x, c.y, c.z, (int)id});
    data["world"] = {{"overrides", nlohmann::json::array()},
                     {"placed_blocks", placed},
                     {"structure_chunks", nlohmann::json::array()}};
    network_.savePlayerData(data);
    setStatus("SALVAT LOCAL SI ONLINE");
}

void App::applyOnlineSave(const nlohmann::json& data) {
    bw::WorldConfig cfg;
    cfg.world_seed = data.value("world_seed", 1337);
    if (data.contains("world_config") && data["world_config"].is_object()) {
        const auto& c = data["world_config"];
        cfg.surface_min_height = c.value("surface_min_height", 32.0);
        cfg.surface_max_height = c.value("surface_max_height", 96.0);
        cfg.terrain_frequency = c.value("terrain_frequency", 0.018);
        cfg.terrain_warp_strength = c.value("terrain_warp_strength", 5.0);
        cfg.terrain_curve = c.value("terrain_curve", 0.7);
        cfg.ridge_strength = c.value("ridge_strength", 0.8);
        cfg.biome_frequency = c.value("biome_frequency", 0.0035);
        cfg.tree_density = c.value("tree_density", 1.0);
        cfg.relief_scale = c.value("relief_scale", 3.0);
    }
    initWorld(cfg, "sandbox", menu_.selectedCharacter);
    if (data.contains("player") && data["player"].is_object()) {
        const auto& pd = data["player"];
        auto vec3 = [&](const char* key, glm::dvec3 fallback) {
            if (!pd.contains(key) || !pd[key].is_array() ||
                pd[key].size() < 3)
                return fallback;
            return glm::dvec3(pd[key][0].get<double>(),
                              pd[key][1].get<double>(),
                              pd[key][2].get<double>());
        };
        game_->player.pos = vec3("position", game_->player.pos);
        game_->player.spawnPos = vec3("spawn_position", game_->player.pos);
        game_->player.yaw = pd.value("yaw", 0.0);
        game_->player.pitch = pd.value("pitch", 0.0);
        game_->player.health = std::clamp(
            pd.value("health", game_->player.maxHealth), 0.0,
            game_->player.maxHealth);
        game_->player.score = pd.value("score", 0);
        game_->player.balloonsPopped = pd.value("kills", 0);
        game_->player.weapon = std::clamp(pd.value("weapon", 0), 0, 1);
        game_->player.inventory.selected =
            std::clamp(pd.value("selected_slot", 0), 0, 9);
        if (pd.contains("inventory") && pd["inventory"].is_object()) {
            for (auto it = pd["inventory"].begin();
                 it != pd["inventory"].end(); ++it) {
                const int type = std::atoi(it.key().c_str());
                if (type >= 0 && type < bw::kBlockTypeCount)
                    game_->player.inventory.counts[type] =
                        it.value().get<int>();
            }
        }
    }
    if (data.contains("world") && data["world"].is_object() &&
        data["world"].contains("placed_blocks") &&
        data["world"]["placed_blocks"].is_array()) {
        for (const auto& b : data["world"]["placed_blocks"]) {
            if (!b.is_array() || b.size() < 4)
                continue;
            game_->blocks.place({b[0].get<int64_t>(), b[1].get<int64_t>(),
                                 b[2].get<int64_t>()},
                                (uint8_t)b[3].get<int>(), true);
        }
    }
    menuOpen_ = false;
    mouseLocked_ = true;
    glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    firstMouse_ = true;
    setStatus("SALVARE ONLINE INCARCATA");
}

void App::saveEditorToDisk() {
    const std::string home = std::getenv("HOME") ? std::getenv("HOME") : ".";
    std::string name = menu_.editorName.empty() ? "Structure" : menu_.editorName;
    for (char& c : name)
        if (c == '/' || c == '\\')
            c = '_';
    editor_.name = name;
    const std::string path =
        home + "/.local/share/balloonwar/blueprints/" + name + ".json";
    if (editor_.save(path)) {
        setStatus("STRUCTURA SALVATA: " + name);
        blueprints_.scan({
            bw::findProjectRoot() + "/resources/blueprints",
            bw::findProjectRoot() + "/src/balloonwar/data/blueprints",
            home + "/.local/share/balloonwar/blueprints",
        });
    } else {
        setStatus("SALVAREA STRUCTURII A ESUAT");
    }
}

void App::loadEditorBlueprint() {
    const auto& list = blueprints_.list();
    if (list.empty()) {
        setStatus("NICIO STRUCTURA DISPONIBILA");
        return;
    }
    if (blueprintIndex_ < 0)
        blueprintIndex_ = 0;
    std::map<bw::Cell, uint8_t> blocks;
    if (blueprints_.load(list[blueprintIndex_], blocks)) {
        editor_.pushUndo();
        editor_.blocks = std::move(blocks);
        editor_.name = list[blueprintIndex_].name;
        menu_.editorName = editor_.name;
        setStatus("STRUCTURA INCARCATA: " + editor_.name);
    }
}

void App::cycleEditorGrid() {
    if (editor_.grid == 9)
        editor_.grid = 15;
    else if (editor_.grid == 15)
        editor_.grid = 21;
    else
        editor_.grid = 9;
    menu_.editorGrid = editor_.grid;
}

void App::enterEditor() {
    initEditor();
}

void App::applyRemoteState(const nlohmann::json& message) {
    if (!message.contains("players") || !message["players"].is_array())
        return;
    std::vector<RemotePlayer> next;
    for (const auto& p : message["players"]) {
        if (!p.is_object())
            continue;
        const int id = p.value("player_id", p.value("id", 0));
        if (id == network_.state.playerId)
            continue;
        RemotePlayer r;
        r.id = id;
        r.name = p.value("name", "Player");
        if (p.contains("pos") && p["pos"].is_array() && p["pos"].size() >= 3)
            r.targetPos = {p["pos"][0].get<double>(),
                           p["pos"][1].get<double>(),
                           p["pos"][2].get<double>()};
        r.pos = r.targetPos;
        r.targetYaw = p.value("rot_x", 0.0);
        r.yaw = r.targetYaw;
        r.alive = p.value("alive", true);
        // keep the interpolated pose when the player already exists
        for (const auto& old : remotes_)
            if (old.id == id) {
                r.pos = old.pos;
                r.yaw = old.yaw;
                break;
            }
        next.push_back(std::move(r));
    }
    remotes_ = std::move(next);
}

// ============================================================
// game loop
// ============================================================

int App::run() {
    bw::dbg::init(std::getenv("BW_DEBUG") != nullptr);
    glfwSetErrorCallback([](int code, const char* desc) {
        bw::dbg::error("GLFW error %d: %s", code, desc ? desc : "?");
    });
    if (!initWindow())
        return 1;
    initGL();
    initGeometry();
    initModels();
    initTerrainTextures();
    debugOverlay_ = std::getenv("BW_DEBUG") != nullptr;

    // first world (menu background)
    bw::WorldConfig cfg;
    cfg.world_seed = 1337;
    menu_.seedText = "1337";
    initWorld(cfg, "classic", menu_.selectedCharacter);
    menu_.inGame = false;
    audio_.startMusic();

    // automated smoke helpers (screenshots / quick start)
    if (fastMode_)
        rPages_ = 2;
    {
        const std::string home = std::getenv("HOME") ? std::getenv("HOME") : ".";
        const std::string root = bw::findProjectRoot();
        blueprints_.scan({
            root + "/resources/blueprints",
            root + "/src/balloonwar/data/blueprints",
            home + "/.local/share/balloonwar/blueprints",
        });
        if (!blueprints_.list().empty()) {
            blueprintIndex_ = 0;
            menu_.editorBlueprint = blueprints_.list()[0].name;
            if (std::getenv("BW_BLUEPRINT")) {
                const int idx = std::atoi(std::getenv("BW_BLUEPRINT"));
                if (idx >= 0 && idx < (int)blueprints_.list().size()) {
                    blueprintIndex_ = idx;
                    menu_.editorBlueprint = blueprints_.list()[idx].name;
                }
            }
        }
    }
    {
        std::string user, pass;
        if (network_.credentials.load(user, pass)) {
            menu_.username = user;
            menu_.password = pass;
        }
    }
    if (const char* v = std::getenv("BW_TREES")) {
        // debug: tree density override for animation screenshots
        menu_.treeDensity = std::atof(v);
        if (game_)
            game_->config.tree_density = std::atof(v);
    }
    if (std::getenv("START_GAME")) {
        if (std::getenv("GAME_MODE"))
            menu_.selectSingleplayerMode(std::getenv("GAME_MODE"));
        menu_.show("main");
        setStatus(handleMenuAction("start_singleplayer"));
    }
    if (std::getenv("PLAYER_YAW_DEG"))
        game_->player.yaw =
            std::atof(std::getenv("PLAYER_YAW_DEG")) * 3.141592653589793 / 180.0;
    if (std::getenv("PLAYER_PITCH_DEG"))
        game_->player.pitch = std::atof(std::getenv("PLAYER_PITCH_DEG")) *
                              3.141592653589793 / 180.0;
    if (std::getenv("CAMERA_MODE"))
        game_->player.cameraMode = std::atoi(std::getenv("CAMERA_MODE"));
    if (std::getenv("WEAPON"))
        game_->player.weapon = std::atoi(std::getenv("WEAPON"));
    if (std::getenv("DIG_MODE"))
        game_->player.digMode = std::atoi(std::getenv("DIG_MODE"));
    if (std::getenv("INTERACT_MODE"))
        game_->player.interactionMode = std::atoi(std::getenv("INTERACT_MODE"));
    if (std::getenv("SPAWN_X") && std::getenv("SPAWN_Z")) {
        const double sx = std::atof(std::getenv("SPAWN_X"));
        const double sz = std::atof(std::getenv("SPAWN_Z"));
        game_->player.pos = {sx, game_->terrain.heightAt(sx, sz) + 1.0, sz};
        game_->player.spawnPos = game_->player.pos;
    }
    if (std::getenv("DEBUG_BALLOONS")) {
        for (int i = 0; i < 3; ++i) {
            bw::Balloon b;
            b.pos = game_->player.pos + glm::dvec3(i * 4.0 - 4.0, 6.0 + i, 8.0);
            b.type = i;
            b.speed = i == 1 ? 5.5 : (i == 2 ? 2.0 : 3.2);
            b.hp = b.maxHp = i == 1 ? 60.0 : (i == 2 ? 200.0 : 100.0);
            b.points = i == 1 ? 15.0 : (i == 2 ? 30.0 : 10.0);
            game_->enemies.balloons().push_back(std::move(b));
        }
        std::printf("[debug: 3 balloons spawned]\n");
    }
    if (std::getenv("BW_DEBUG_ARROW")) {
        // three stuck arrows to check the mesh orientation: forward,
        // up and sideways, placed in front of the player
        const glm::dvec3 fwd = game_->player.forward();
        glm::dvec3 right = glm::cross(fwd, glm::dvec3(0, 1, 0));
        if (glm::length(right) < 1e-5)
            right = glm::dvec3(1, 0, 0);
        right = glm::normalize(right);
        const glm::dvec3 base = game_->player.pos + fwd * 4.0 +
                                glm::dvec3(0, 1.5, 0) - right * 1.5;
        const glm::dvec3 dirs[3] = {fwd, glm::dvec3(0, 1, 0), -right};
        for (int i = 0; i < 3; ++i) {
            auto a = std::make_unique<bw::Arrow>();
            a->pos = base + right * (double)(i * 1.5);
            a->dir = dirs[i];
            a->stuck = true;
            game_->enemies.addArrow(std::move(a));
        }
        std::printf("[debug: 3 arrows spawned]\n");
    }
    const double shotTime = std::getenv("SHOT_AFTER_SECONDS")
                                ? std::atof(std::getenv("SHOT_AFTER_SECONDS"))
                                : 0.0;
    bool shotDone = false;

    std::signal(SIGINT, onQuitSignal);
    std::signal(SIGTERM, onQuitSignal);
#ifdef SIGHUP
    std::signal(SIGHUP, onQuitSignal); // not defined on Windows
#endif
    lastTime_ = glfwGetTime();
    fpsTimer_ = lastTime_;
    while (!glfwWindowShouldClose(window_) && !g_quitRequested) {
        const double now = glfwGetTime();
        double dt = now - lastTime_;
        lastTime_ = now;
        elapsed_ += dt;
        if (dt > 0.05)
            dt = 0.05;
        frame(dt);
        ++frames_;
        if (now - fpsTimer_ >= 1.0) {
            if (std::getenv("DEBUG_FPS"))
                std::printf("[fps %.1f elapsed=%.2f]\n",
                            frames_ / (now - fpsTimer_), elapsed_);
            fpsTimer_ = now;
            frames_ = 0;
        }
        if (shotTime > 0.0 && !shotDone && now >= shotTime) {
            shotDone = true;
            glfwGetFramebufferSize(window_, &fbW_, &fbH_);
            std::vector<unsigned char> px((size_t)fbW_ * fbH_ * 3);
            glReadPixels(0, 0, fbW_, fbH_, GL_RGB, GL_UNSIGNED_BYTE, px.data());
            const char* path = std::getenv("SHOT_PATH")
                                   ? std::getenv("SHOT_PATH")
                                   : "/tmp/balloonwar_shot.ppm";
            std::FILE* f = std::fopen(path, "wb");
            if (f) {
                std::fprintf(f, "P6\n%d %d\n255\n", fbW_, fbH_);
                std::fwrite(px.data(), 1, px.size(), f);
                std::fclose(f);
            }
            std::printf("[screenshot saved: %s]\n", path);
            if (std::getenv("EXIT_AFTER_SHOT"))
                glfwSetWindowShouldClose(window_, GLFW_TRUE);
        }
    }
    audio_.stopMusic();
    if (game_)
        game_->save(bw::defaultSavePath());
    glfwDestroyWindow(window_);
    glfwTerminate();
    return 0;
}

void App::frame(double dt) {
    animDt_ = dt;
    glfwGetFramebufferSize(window_, &fbW_, &fbH_);
    glfwGetWindowSize(window_, &winW_, &winH_);
    const bool prof = std::getenv("DEBUG_PROFILE") != nullptr;
    auto tick = [] { return std::chrono::steady_clock::now(); };
    auto ms = [](auto a, auto b) {
        return std::chrono::duration<double, std::milli>(b - a).count();
    };
    auto t0 = tick();
    handleContinuousInput(dt);
    auto t1 = tick();
    update(dt);
    auto t2 = tick();
    render();
    auto t3 = tick();
    glfwSwapBuffers(window_);
    auto t4 = tick();
    glfwPollEvents();
    frameMs_ = frameMs_ * 0.9 + ms(t0, t4) * 0.1;
    frameMsPeak_ = std::max(frameMsPeak_ * 0.995, ms(t0, t4));
    if (prof)
        std::printf("[prof in=%.1f update=%.1f render=%.1f swap=%.1f]\n",
                    ms(t0, t1), ms(t1, t2), ms(t2, t3), ms(t3, t4));
    if (debugOverlay_ || std::getenv("BW_GL_CHECK"))
        glCheckErrors("frame");
}

void App::handleContinuousInput(double dt) {
    if (!game_)
        return;
    clickCooldown_ = std::max(0.0, clickCooldown_ - dt);
    buildCooldown_ = std::max(0.0, buildCooldown_ - dt);
    shootCooldown_ = std::max(0.0, shootCooldown_ - dt);
    statusTimer_ = std::max(0.0, statusTimer_ - dt);
    if (!mouseLocked_ || menuOpen_)
        return;

    auto& p = game_->player;
    bw::PlayerInput in;
    in.forward = glfwGetKey(window_, GLFW_KEY_W) == GLFW_PRESS;
    in.back = glfwGetKey(window_, GLFW_KEY_S) == GLFW_PRESS;
    in.left = glfwGetKey(window_, GLFW_KEY_A) == GLFW_PRESS;
    in.right = glfwGetKey(window_, GLFW_KEY_D) == GLFW_PRESS;
    in.jump = glfwGetKey(window_, GLFW_KEY_SPACE) == GLFW_PRESS;
    in.down = glfwGetKey(window_, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS;
    static bool prevJump = false;
    in.jumpPressed = in.jump && !prevJump;
    prevJump = in.jump;
    // debug: walk forward and hop periodically (BW_AUTO_MOVE=period s)
    if (const char* v = std::getenv("BW_AUTO_MOVE")) {
        static double autoMoveT = 0.0;
        autoMoveT += dt;
        const double period = std::atof(v) > 0.1 ? std::atof(v) : 2.0;
        in.forward = true;
        in.jump = std::fmod(autoMoveT, period) > period - 0.30;
        in.jumpPressed = in.jump && !prevJump;
        prevJump = in.jump;
    }
    p.setMove(in.forward, in.back, in.left, in.right);
    p.setJump(in.jump);
    p.setDown(in.down);
    p.setRun(glfwGetKey(window_, GLFW_KEY_LEFT_CONTROL) == GLFW_PRESS);
    input_ = in;

    if (!editorMode_ && !matchOver_) {
        const bool lmb =
            glfwGetMouseButton(window_, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS;
        const bool rmb =
            glfwGetMouseButton(window_, GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS;
        // hold to dig/build (like the Godot continuous tools)
        if (p.interactionMode == bw::INTERACT_DIG && lmb)
            tryDig();
        if (p.interactionMode == bw::INTERACT_BUILD && rmb)
            tryBuild();
        if (p.interactionMode == bw::INTERACT_COMBAT &&
            p.weapon == bw::WEAPON_CROSSBOW && lmb)
            tryAttack();
        prevLmb_ = lmb;
        prevRmb_ = rmb;
    }

    if (editorMode_) {
        const bool lmb =
            glfwGetMouseButton(window_, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS;
        const bool rmb =
            glfwGetMouseButton(window_, GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS;
        if ((lmb || rmb) && clickCooldown_ <= 0.0) {
            const glm::dvec3 origin = p.freecamPos;
            const glm::dvec3 dir = p.forward();
            // raycast editor blocks (world space)
            bool hit = false;
            const auto toWorld = [&](const bw::Cell& c) {
                return bw::Cell{editorOrigin_.x + c.x, editorBaseY_ + c.y,
                                editorOrigin_.z + c.z};
            };
            std::unordered_map<bw::Cell, uint8_t, bw::CellHash> worldBlocks;
            for (const auto& [c, t] : editor_.blocks)
                worldBlocks[toWorld(c)] = t;
            double best = 60.0;
            bw::Cell outCell, outFace;
            // simple per-block slab test
            for (const auto& [c, t] : worldBlocks) {
                (void)t;
                const double mnx = bw::blockCellMin(c.x);
                const double mny = bw::blockCellMin(c.y);
                const double mnz = bw::blockCellMin(c.z);
                const double mxx = bw::blockCellMax(c.x);
                const double mxy = bw::blockCellMax(c.y);
                const double mxz = bw::blockCellMax(c.z);
                double tmin = -1e18, tmax = 1e18;
                int axis = -1;
                bool skip = false;
                for (int a = 0; a < 3 && !skip; ++a) {
                    const double o = a == 0 ? origin.x
                                            : (a == 1 ? origin.y : origin.z);
                    const double d = a == 0 ? dir.x : (a == 1 ? dir.y : dir.z);
                    const double lo = a == 0 ? mnx : (a == 1 ? mny : mnz);
                    const double hi = a == 0 ? mxx : (a == 1 ? mxy : mxz);
                    if (std::abs(d) < 1e-12) {
                        if (o < lo || o > hi)
                            skip = true;
                    } else {
                        double t1 = (lo - o) / d;
                        double t2 = (hi - o) / d;
                        if (t1 > t2)
                            std::swap(t1, t2);
                        if (t1 > tmin) {
                            tmin = t1;
                            axis = a;
                        }
                        if (t2 < tmax)
                            tmax = t2;
                        if (tmin > tmax)
                            skip = true;
                    }
                }
                if (skip || tmin < 0.0 || tmin >= best)
                    continue;
                best = tmin;
                outCell = c;
                outFace = {0, 0, 0};
                if (axis == 0)
                    outFace.x = dir.x > 0 ? -1 : 1;
                else if (axis == 1)
                    outFace.y = dir.y > 0 ? -1 : 1;
                else
                    outFace.z = dir.z > 0 ? -1 : 1;
                hit = true;
            }
            if (!hit) {
                // intersect the build plane y = base + editorPlane_
                const double planeY =
                    (double)(editorBaseY_ + editorPlane_) * bw::BLOCK_CELL;
                if (std::abs(dir.y) > 1e-6) {
                    const double t = (planeY - origin.y) / dir.y;
                    if (t > 0.0 && t < 60.0) {
                        const glm::dvec3 pnt = origin + dir * t;
                        outCell = {bw::blockCellOf(pnt.x),
                                   editorBaseY_ + editorPlane_,
                                   bw::blockCellOf(pnt.z)};
                        outFace = {0, 1, 0};
                        hit = true;
                    }
                }
            }
            if (hit) {
                const bw::Cell local{outCell.x - editorOrigin_.x,
                                     outCell.y - editorBaseY_,
                                     outCell.z - editorOrigin_.z};
                if (lmb) {
                    editor_.pushUndo();
                    editor_.setBlock(local, (uint8_t)p.inventory.selectedType());
                    audio_.play("assets/audio/arrowhit.wav", 40);
                } else {
                    editor_.pushUndo();
                    editor_.eraseBlock(local);
                    audio_.play("assets/audio/arrowhit.wav", 30);
                }
                menu_.editorBlocks = (int)editor_.blocks.size();
                clickCooldown_ = 0.12;
            }
        }
    }
}

void App::update(double dt) {
    if (!game_)
        return;
    audio_.update(dt);

    const bool active = !menuOpen_ && !matchOver_;
    game_->update(dt, input_, active);

    // automated smoke actions
    if (std::getenv("AUTO_DIG") && !autoDigDone_ && elapsed_ > 2.0) {
        autoDigDone_ = true;
        tryDig();
        std::printf("[auto dig]\n");
    }
    if (std::getenv("AUTO_BUILD") && !autoBuildDone_ && elapsed_ > 3.0) {
        autoBuildDone_ = true;
        tryBuild();
        std::printf("[auto build]\n");
    }
    if (std::getenv("AUTO_BLUEPRINT") && !autoBlueprintDone_ &&
        elapsed_ > 2.5) {
        autoBlueprintDone_ = true;
        const auto& list = blueprints_.list();
        std::printf("[auto blueprint: %zu available, index=%d]\n", list.size(),
                    blueprintIndex_);
        tryPlaceBlueprint();
        std::printf("[auto blueprint result: %s]\n", status_.c_str());
    }
    if (std::getenv("AUTO_SHOOT") && !autoShootDone_ && elapsed_ > 4.0) {
        autoShootDone_ = true;
        tryAttack();
        std::printf("[auto shoot]\n");
    }
    if (std::getenv("AUTO_CRAFT") && !autoCraftDone_ && elapsed_ > 3.5) {
        autoCraftDone_ = true;
        craftingOpen_ = true;
        const auto& recipes = game_->crafting.recipes();
        int crafted = 0;
        for (int i = 0; i < (int)recipes.size(); ++i) {
            if (game_->crafting.craft(recipes[i],
                                      game_->player.inventory.counts)) {
                ++crafted;
                craftIndex_ = i;
                break;
            }
        }
        std::printf("[auto craft: %d recipes, crafted=%d]\n",
                    (int)recipes.size(), crafted);
    }
    if (std::getenv("AUTO_EDITOR") && !autoEditorDone_ && elapsed_ > 5.0) {
        autoEditorDone_ = true;
        enterEditor();
        for (int x = -3; x <= 3; ++x)
            for (int z = -3; z <= 3; ++z)
                editor_.setBlock({x, 0, z}, bw::STONE);
        for (int x = -3; x <= 3; ++x)
            for (int y = 1; y <= 2; ++y)
                editor_.setBlock({x, y, -3},
                                 y == 1 ? bw::WOOD : bw::GRASS);
        editor_.setBlock({0, 1, 0}, bw::GOLD);
        menu_.editorBlocks = (int)editor_.blocks.size();
        if (std::getenv("AUTO_EDITOR_CLOSE"))
            handleMenuAction("resume");
        std::printf("[auto editor: %d blocks]\n", (int)editor_.blocks.size());
    }
    if (std::getenv("AUTO_SAVE") && !autoSaveDone_ && elapsed_ > 6.0) {
        autoSaveDone_ = true;
        saveGameToDisk();
        std::printf("[auto save]\n");
    }
    if (std::getenv("AUTO_LOAD") && !autoLoadDone_ && elapsed_ > 7.0) {
        autoLoadDone_ = true;
        loadGameFromDisk();
        std::printf("[auto load]\n");
    }
    if (std::getenv("DEBUG_LOG") && std::fmod(elapsed_, 3.0) < dt) {
        size_t wet = 0;
        for (const auto& [k, wp] : game_->water.pages()) {
            (void)k;
            if (wp.hasWater)
                ++wet;
        }
        std::printf(
            "[log t=%.1f pos=%.1f,%.1f,%.1f balloons=%zu blocks=%zu "
            "waterPages=%zu hp=%.0f]\n",
            elapsed_, game_->player.pos.x, game_->player.pos.y,
            game_->player.pos.z, game_->enemies.balloons().size(),
            game_->blocks.count(), wet, game_->player.health);
    }

    if (active)
        game_->generateChunksAround(game_->player.pos, 2);

    updatePages();
    updateWater(dt);
    updateBlockInstances();

    // events
    for (const auto& [type, pos] : game_->events()) {
        if (type == "pop") {
            audio_.play("assets/images/assest/balloon-pop-48030 (1).wav", 70);
            puffs_.push_back({pos, 0.0f});
        } else if (type == "arrow_hit") {
            audio_.play("assets/audio/arrowhit.wav", 55);
        }
    }
    game_->enemies.drainEvents();
    for (auto it = puffs_.begin(); it != puffs_.end();) {
        it->life += dt;
        if (it->life > 0.6)
            it = puffs_.erase(it);
        else
            ++it;
    }

    pollNetwork(dt);

    for (auto& r : remotes_) {
        const double k = std::min(1.0, dt * 8.0);
        r.pos += (r.targetPos - r.pos) * k;
        double dyaw = r.targetYaw - r.yaw;
        while (dyaw > 3.14159265)
            dyaw -= 6.2831853;
        while (dyaw < -3.14159265)
            dyaw += 6.2831853;
        r.yaw += dyaw * k;
    }

    // ---- character animation state machines ----
    if (game_->player.health < prevHealth_ - 0.01)
        hitTimer_ = 0.35;
    prevHealth_ = game_->player.health;
    hitTimer_ = std::max(0.0, hitTimer_ - dt);
    {
        anim::Input in = playerAnimInput();
        playerDriver_.update(in);
        if (std::getenv("BW_ANIM_DEBUG") &&
            std::fmod(elapsed_, 1.0) < dt)
            std::printf(
                "[anim state=%s t=%.2f air=%.2f swim=%.2f dead=%.2f "
                "aim=%.2f crouch=%.2f speed=%.2f vy=%.2f pitch=%.2f "
                "dt=%.4f]\n",
                anim::stateName(playerDriver_.state), playerDriver_.stateTime,
                playerDriver_.airBlend, playerDriver_.swimBlend,
                playerDriver_.deathBlend, playerDriver_.aimBlend,
                playerDriver_.crouch, in.speed, in.vy, in.pitch, in.dt);
    }
    for (auto& r : remotes_) {
        anim::Input in = remoteAnimInput(r);
        remoteDrivers_[r.id].update(in);
    }

    if (game_->match.finished && !matchOver_) {
        matchOver_ = true;
        mouseLocked_ = false;
        glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    }
}

void App::pollNetwork(double dt) {
    auto messages = network_.poll();
    for (const auto& message : messages) {
        const std::string type = message.value("type", "");
        if (type == "auth_ok") {
            setStatus("CONECTAT: " + network_.state.username);
            menu_.show("multiplayer");
            menu_.loggedUser = network_.state.username;
            network_.fetchRooms();
        } else if (type == "auth_error" || type == "error" ||
                   type == "_connection_failed") {
            setStatus(network_.state.lastError);
        } else if (type == "room_created" || type == "joined") {
            menu_.roomCode = network_.state.roomId;
            menu_.roomPlayers = network_.state.roomPlayers;
            menu_.status = "SALA " + network_.state.roomId;
        } else if (type == "player_joined" || type == "player_ready" ||
                   type == "player_left") {
            menu_.roomPlayers = network_.state.roomPlayers;
        } else if (type == "room_list") {
            menu_.status = std::to_string(network_.state.roomList.size()) +
                           " SALI DISPONIBILE";
        } else if (type == "room_closed") {
            setStatus(network_.state.lastError);
            menu_.show("multiplayer");
        } else if (type == "game_started") {
            const int seed = message.value("seed", 1337);
            const std::string mode = bw::normalizeGameMode(
                message.value("game_mode", "classic"));
            bw::WorldConfig cfg;
            cfg.world_seed = seed;
            initWorld(cfg, mode, menu_.selectedCharacter);
            networkGame_ = true;
            menuOpen_ = false;
            mouseLocked_ = true;
            glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
            firstMouse_ = true;
            setStatus("MECI INCEPUT");
        } else if (type == "state_update" || type == "match_ended") {
            applyRemoteState(message);
            if (message.contains("time_remaining"))
                game_->match.syncRemaining(message.value("time_remaining", -1.0));
            if (message.value("match_finished", false))
                game_->match.finish();
        } else if (type == "terrain_change") {
            if (message.value("player_id", 0) != network_.state.playerId) {
                if (message.contains("pos") && message["pos"].is_array() &&
                    message["pos"].size() >= 3) {
                    const int64_t x = message["pos"][0].get<int64_t>();
                    const int64_t y = message["pos"][1].get<int64_t>();
                    const int64_t z = message["pos"][2].get<int64_t>();
                    const std::string action =
                        message.value("action_type", "dig");
                    const int block = message.value("block_type", 0);
                    if (action == "dig")
                        game_->applyTerrainChange(x, y, z, bw::AIR);
                    else if (action == "build")
                        game_->applyTerrainChange(x, y, z, block);
                }
            }
        } else if (type == "chat") {
            setStatus(message.value("name", "Player") + ": " +
                      message.value("message", ""));
        } else if (type == "save_data_result") {
            setStatus(message.value("success", false) ? "SALVAT LOCAL SI ONLINE"
                                                      : "SALVAT DOAR LOCAL");
        } else if (type == "load_data_result") {
            if (message.value("success", false) &&
                message.contains("data") && message["data"].is_object())
                applyOnlineSave(message["data"]);
            else
                setStatus("SALVAREA ONLINE NU ESTE DISPONIBILA");
        } else if (type == "delete_account_result" &&
                   message.value("success", false)) {
            setStatus("CONT STERS");
            menu_.show("main");
        } else if (type == "_disconnected") {
            setStatus("DECONECTAT");
            networkGame_ = false;
        }
    }

    if (networkGame_ && network_.state.roomId.size() > 0) {
        netAccumulator_ += dt;
        if (netAccumulator_ >= 0.1) {
            netAccumulator_ = 0.0;
            const auto& p = game_->player;
            const double pos[3] = {p.pos.x, p.pos.y, p.pos.z};
            network_.sendInput(pos, p.yaw, p.weapon, p.interactionMode, p.score,
                               p.balloonsPopped, p.health, !p.dead);
        }
    }
}

void App::updatePages() {
    auto& terrain = game_->terrain;
    const int64_t pcx = (int64_t)std::floor(
        world::colIndex(game_->player.pos.x) / (double)world::PAGE_CELLS);
    const int64_t pcz = (int64_t)std::floor(
        world::colIndex(game_->player.pos.z) / (double)world::PAGE_CELLS);
    int built = 0;
    const int budget = 4;
    for (int64_t r = 0; r <= rPages_ && built < budget; ++r) {
        for (int64_t z = pcz - r; z <= pcz + r && built < budget; ++z) {
            for (int64_t x = pcx - r; x <= pcx + r && built < budget; ++x) {
                if (r > 0 && std::abs(x - pcx) != r && std::abs(z - pcz) != r)
                    continue;
                const auto it = terrain.pages().find(world::pageKey(x, z));
                if (it == terrain.pages().end() || !it->second.built) {
                    terrain.ensureBuilt(x, z);
                    ++built;
                }
            }
        }
    }
    uploadDirtyPages();
}

void App::uploadDirtyPages() {
    auto& terrain = game_->terrain;
    const int64_t pcx = (int64_t)std::floor(
        world::colIndex(game_->player.pos.x) / (double)world::PAGE_CELLS);
    const int64_t pcz = (int64_t)std::floor(
        world::colIndex(game_->player.pos.z) / (double)world::PAGE_CELLS);
    for (auto& [key, p] : terrain.pages()) {
        if (!p.built || !p.dirtyMesh)
            continue;
        if (std::abs(p.px - pcx) > rPages_ + 1 || std::abs(p.pz - pcz) > rPages_ + 1)
            continue;
        auto& r = pageGL_[key];
        if (!r.vao) {
            glGenVertexArrays(1, &r.vao);
            glGenBuffers(1, &r.vbo);
            glBindVertexArray(r.vao);
            glBindBuffer(GL_ARRAY_BUFFER, r.vbo);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, sharedEbo_);
            glEnableVertexAttribArray(0);
            glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                                  (void*)0);
            glEnableVertexAttribArray(1);
            glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                                  (void*)(3 * sizeof(float)));
            glBindVertexArray(0);
        }
        r.vertexCount =
            (GLsizei)(world::PAGE_VERTS * world::PAGE_VERTS);
        glBindBuffer(GL_ARRAY_BUFFER, r.vbo);
        glBufferData(GL_ARRAY_BUFFER,
                     (GLsizeiptr)(p.verts.size() * sizeof(float)), p.verts.data(),
                     GL_DYNAMIC_DRAW);
        p.dirtyMesh = false;
    }
}

void App::updateWater(double dt) {
    (void)dt;
    auto& water = game_->water;
    water.rebuildSurfaces();
    for (auto& [key, wp] : water.pages()) {
        if (!wp.hasWater || !wp.surfReady || !wp.dirty)
            continue;
        const int64_t wkey = world::pageKey(wp.px, wp.pz);
        auto& r = waterGL_[wkey];
        if (!r.vao) {
            glGenVertexArrays(1, &r.vao);
            glGenBuffers(1, &r.vbo);
            glGenBuffers(1, &r.ebo);
            glBindVertexArray(r.vao);
            glBindBuffer(GL_ARRAY_BUFFER, r.vbo);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, r.ebo);
            glEnableVertexAttribArray(0);
            glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 10 * sizeof(float),
                                  (void*)0);
            glEnableVertexAttribArray(1);
            glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 10 * sizeof(float),
                                  (void*)(3 * sizeof(float)));
            glEnableVertexAttribArray(2);
            glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, 10 * sizeof(float),
                                  (void*)(6 * sizeof(float)));
            glBindVertexArray(0);
        }
        glBindBuffer(GL_ARRAY_BUFFER, r.vbo);
        glBufferData(GL_ARRAY_BUFFER,
                     (GLsizeiptr)(wp.surf.size() * sizeof(float)),
                     wp.surf.data(), GL_DYNAMIC_DRAW);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, r.ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                     (GLsizeiptr)(wp.idx.size() * sizeof(uint32_t)),
                     wp.idx.data(), GL_DYNAMIC_DRAW);
        r.indexCount = (GLsizei)wp.idx.size();
        wp.dirty = false;
    }
}

void App::updateBlockInstances() {
    if (game_->blocks.version() == blocksVersion_)
        return;
    blocksVersion_ = game_->blocks.version();
    std::vector<float> inst;
    inst.reserve(game_->blocks.count() * 6);
    for (const auto& [c, id] : game_->blocks.map()) {
        const float cx = (float)(bw::blockCellMin(c.x) + bw::BLOCK_CELL * 0.5);
        const float cy = (float)(bw::blockCellMin(c.y) + bw::BLOCK_CELL * 0.5);
        const float cz = (float)(bw::blockCellMin(c.z) + bw::BLOCK_CELL * 0.5);
        const glm::vec3 col = bw::blockColor(id);
        inst.insert(inst.end(), {cx, cy, cz, col.r, col.g, col.b});
    }
    glBindBuffer(GL_ARRAY_BUFFER, instVbo_);
    glBufferData(GL_ARRAY_BUFFER, inst.size() * sizeof(float), inst.data(),
                 GL_DYNAMIC_DRAW);
}

// ============================================================
// rendering
// ============================================================

glm::dvec3 App::cameraEye() const {
    const auto& p = game_->player;
    if (p.cameraMode == bw::CAMERA_FREECAM)
        return p.freecamPos;
    // debug: BW_ORBIT_DEG orbits the third-person camera around the
    // character (BW_CAM_DIST overrides the distance) - used to inspect
    // the animation from every side.
    if (const char* o = std::getenv("BW_ORBIT_DEG")) {
        const double a =
            p.yaw + std::atof(o) * 3.141592653589793 / 180.0;
        const double d = std::getenv("BW_CAM_DIST")
                             ? std::atof(std::getenv("BW_CAM_DIST"))
                             : p.cameraDistance;
        // BW_CAM_ELEV raises the orbit camera so terrain can be
        // inspected from above (degrees)
        const double el = std::getenv("BW_CAM_ELEV")
                              ? std::atof(std::getenv("BW_CAM_ELEV")) *
                                    3.141592653589793 / 180.0
                              : 0.0;
        const glm::dvec3 dir(std::sin(a) * std::cos(el), -std::sin(el),
                             -std::cos(a) * std::cos(el));
        return p.pos + glm::dvec3(0.0, bw::Player::EYE * 0.75, 0.0) - dir * d;
    }
    return p.cameraPosition();
}

glm::dvec3 App::cameraForward() const {
    if (std::getenv("BW_ORBIT_DEG")) {
        const auto& p = game_->player;
        const glm::dvec3 target =
            p.pos + glm::dvec3(0.0, bw::Player::EYE * 0.75, 0.0);
        const glm::dvec3 d = target - cameraEye();
        if (glm::length(d) > 1e-6)
            return glm::normalize(d);
    }
    return game_->player.forward();
}

void App::setModelUniforms() {
    // shared camera uniforms for the model program (call after glUseProgram)
    const glm::vec3 eye((float)cameraEye().x, (float)cameraEye().y,
                        (float)cameraEye().z);
    glUniform3fv(glGetUniformLocation(progModel_, "uCamPos"), 1,
                 glm::value_ptr(eye));
    glUniform3fv(glGetUniformLocation(progModel_, "uSunDir"), 1,
                 glm::value_ptr(SUN_DIR));
    glUniform3fv(glGetUniformLocation(progModel_, "uFogColor"), 1,
                 glm::value_ptr(FOG_COLOR));
    glUniform1f(glGetUniformLocation(progModel_, "uFogEnd"), (float)FOG_END);
    glUniform1i(glGetUniformLocation(progModel_, "uTex"), 0);
}

void App::drawSceneAt(const model::Scene& sc, const SceneGL& gl,
                      const glm::mat4& model, const glm::vec3& tint,
                      float unlit) {
    if (!gl.ok)
        return;
    for (size_t oi = 0; oi < sc.objs.size(); ++oi) {
        const auto& o = sc.objs[oi];
        auto gIt = gl.geom.find(o.mesh);
        if (gIt == gl.geom.end())
            continue;
        const auto& gm = sc.geoms[o.mesh];
        const int img = gm.texImage >= 0 ? gm.texImage : -1;
        auto iIt = gl.tex.find(img);
        GLuint tex = iIt != gl.tex.end() ? iIt->second : gl.white;
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, tex);
        glUniform3f(glGetUniformLocation(progModel_, "uColor"), tint.r, tint.g,
                    tint.b);
        glUniform1f(glGetUniformLocation(progModel_, "uUnlit"), unlit);
        glm::mat4 m = model * o.base;
        glUniformMatrix4fv(glGetUniformLocation(progModel_, "uModel"), 1,
                           GL_FALSE, glm::value_ptr(m));
        glBindVertexArray(gIt->second);
        glDrawElements(GL_TRIANGLES, gl.tris.at(o.mesh), GL_UNSIGNED_INT,
                       nullptr);
    }
}

void App::drawSkinned(const model::Scene& sc, const SceneGL& gl,
                      const glm::mat4& mvp, const glm::mat4& model,
                      const glm::vec3& tint,
                      const std::vector<glm::mat4>& bones) {
    if (!gl.ok || bones.empty())
        return;
    glUseProgram(progSkin_);
    const glm::dvec3 eye = cameraEye();
    const glm::vec3 eyeF((float)eye.x, (float)eye.y, (float)eye.z);
    glUniformMatrix4fv(glGetUniformLocation(progSkin_, "uMvp"), 1, GL_FALSE,
                       glm::value_ptr(mvp));
    glUniformMatrix4fv(glGetUniformLocation(progSkin_, "uModel"), 1, GL_FALSE,
                       glm::value_ptr(model));
    glUniform3fv(glGetUniformLocation(progSkin_, "uCamPos"), 1,
                 glm::value_ptr(eyeF));
    glUniform3fv(glGetUniformLocation(progSkin_, "uSunDir"), 1,
                 glm::value_ptr(SUN_DIR));
    glUniform3fv(glGetUniformLocation(progSkin_, "uFogColor"), 1,
                 glm::value_ptr(FOG_COLOR));
    glUniform1f(glGetUniformLocation(progSkin_, "uFogEnd"), (float)FOG_END);
    glUniform1f(glGetUniformLocation(progSkin_, "uUnlit"), 0.0f);
    glUniform1i(glGetUniformLocation(progSkin_, "uTex"), 0);
    const GLsizei count =
        (GLsizei)std::min<size_t>(bones.size(), 32);
    glUniformMatrix4fv(glGetUniformLocation(progSkin_, "uBones"), count,
                       GL_FALSE, glm::value_ptr(bones[0]));
    for (const auto& o : sc.objs) {
        if (o.skin < 0)
            continue;
        auto gIt = gl.skinGeom.find(o.mesh);
        if (gIt == gl.skinGeom.end())
            continue;
        const auto& gm = sc.geoms[o.mesh];
        const int img = gm.texImage >= 0 ? gm.texImage : -1;
        auto iIt = gl.tex.find(img);
        GLuint tex = iIt != gl.tex.end() ? iIt->second : gl.white;
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, tex);
        glUniform3f(glGetUniformLocation(progSkin_, "uColor"), tint.r, tint.g,
                    tint.b);
        glBindVertexArray(gIt->second);
        glDrawElements(GL_TRIANGLES, gl.tris.at(o.mesh), GL_UNSIGNED_INT,
                       nullptr);
    }
    glBindVertexArray(0);
}

// ============================================================
// baked clip playback (glTF animations: Idle/Walk/Run)
// ============================================================

void App::initCharacterClips() {
    clipsReady_ = false;
    const size_t n = charScene_.nodeLocal.size();
    restPose_.t.assign(n, glm::vec3(0.0f));
    restPose_.r.assign(n, glm::quat(1.0f, 0.0f, 0.0f, 0.0f));
    restPose_.s.assign(n, glm::vec3(1.0f));
    for (size_t i = 0; i < n; ++i) {
        glm::vec3 t, s, skew;
        glm::quat r;
        glm::vec4 persp;
        glm::decompose(charScene_.nodeLocal[i], s, r, t, skew, persp);
        restPose_.t[i] = t;
        restPose_.r[i] = r;
        restPose_.s[i] = s;
    }
    poseA_ = poseB_ = poseMix_ = restPose_;
    if (charScene_.animations.empty()) {
        bw::dbg::warn("character GLB has no animations; using procedural pose");
        return;
    }
    auto findClip = [&](const char* name) {
        for (int i = 0; i < (int)charScene_.animations.size(); ++i)
            if (charScene_.animations[i].name == name)
                return i;
        return -1;
    };
    clipIdle_ = findClip("Idle");
    clipWalk_ = findClip("Walk");
    clipRun_ = findClip("Run");
    if (clipIdle_ < 0)
        clipIdle_ = 0;
    if (clipWalk_ < 0)
        clipWalk_ = clipIdle_;
    if (clipRun_ < 0)
        clipRun_ = clipWalk_;
    clipsReady_ = true;
    bw::dbg::info("character clips: %zu anims (idle=%d walk=%d run=%d)",
                  charScene_.animations.size(), clipIdle_, clipWalk_, clipRun_);
}

void App::sampleClip(const model::Animation& anim, float time,
                     PoseBuf& out) const {
    out = restPose_;
    for (const auto& ch : anim.channels) {
        if (ch.node < 0 || ch.node >= (int)out.t.size())
            continue;
        if (ch.sampler < 0 || ch.sampler >= (int)anim.samplers.size())
            continue;
        const model::AnimSampler& sm = anim.samplers[ch.sampler];
        const size_t nk = sm.times.size();
        if (nk == 0 || sm.values.empty())
            continue;
        size_t i0 = 0, i1 = 0;
        float u = 0.0f;
        if (time <= sm.times.front()) {
            i0 = i1 = 0;
        } else if (time >= sm.times.back()) {
            i0 = i1 = nk - 1;
        } else {
            size_t lo = 0, hi = nk - 1;
            while (hi - lo > 1) {
                const size_t mid = (lo + hi) / 2;
                if (sm.times[mid] <= time)
                    lo = mid;
                else
                    hi = mid;
            }
            i0 = lo;
            i1 = hi;
            const float span = sm.times[i1] - sm.times[i0];
            u = span > 1e-8f ? (time - sm.times[i0]) / span : 0.0f;
        }
        if (sm.step)
            u = 0.0f;
        const size_t last = sm.values.size() - 1;
        if (i0 > last)
            i0 = last;
        if (i1 > last)
            i1 = last;
        const glm::vec4& v0 = sm.values[i0];
        const glm::vec4& v1 = sm.values[i1];
        if (ch.path == 1) {
            const glm::quat q0(v0.w, v0.x, v0.y, v0.z);
            const glm::quat q1(v1.w, v1.x, v1.y, v1.z);
            out.r[ch.node] = glm::normalize(glm::slerp(q0, q1, u));
        } else {
            const glm::vec3 v = glm::mix(glm::vec3(v0), glm::vec3(v1), u);
            if (ch.path == 0)
                out.t[ch.node] = v;
            else
                out.s[ch.node] = v;
        }
    }
}

void App::blendPose(const PoseBuf& a, const PoseBuf& b, float w,
                    PoseBuf& out) const {
    const size_t n = restPose_.t.size();
    out.t.resize(n);
    out.r.resize(n);
    out.s.resize(n);
    for (size_t i = 0; i < n; ++i) {
        out.t[i] = glm::mix(a.t[i], b.t[i], w);
        out.r[i] = glm::normalize(glm::slerp(a.r[i], b.r[i], w));
        out.s[i] = glm::mix(a.s[i], b.s[i], w);
    }
}

void App::applyPose(const PoseBuf& pose,
                    std::vector<glm::mat4>& locals) const {
    locals.resize(pose.t.size());
    for (size_t i = 0; i < pose.t.size(); ++i) {
        glm::mat4 m = glm::translate(glm::mat4(1.0f), pose.t[i]);
        m *= glm::mat4_cast(pose.r[i]);
        m = glm::scale(m, pose.s[i]);
        locals[i] = m;
    }
}

void App::updateClipPlayer(ClipPlayer& cp, float dt, float speed01,
                           bool running, float rateScale) {
    if (!clipsReady_)
        return;
    int target = clipIdle_;
    if (speed01 > 0.12f)
        target = running ? clipRun_ : clipWalk_;
    if (target != cp.clip) {
        cp.prev = cp.clip;
        cp.prevTime = cp.time;
        cp.clip = target;
        cp.fade = 0.0f;
    }
    const model::Animation& cur = charScene_.animations[cp.clip];
    // locomotion cycle follows the speed so the feet slide less
    const float rate =
        (cp.clip == clipIdle_ ? 1.0f : std::clamp(speed01, 0.6f, 1.9f)) *
        rateScale;
    cp.time += dt * rate;
    if (cur.duration > 0.01f)
        cp.time = std::fmod(cp.time, cur.duration);
    if (cp.prev >= 0 && cp.prev < (int)charScene_.animations.size()) {
        const model::Animation& pv = charScene_.animations[cp.prev];
        cp.prevTime += dt * rate;
        if (pv.duration > 0.01f)
            cp.prevTime = std::fmod(cp.prevTime, pv.duration);
        cp.fade = std::min(1.0f, cp.fade + dt / 0.18f);
    } else {
        cp.fade = 1.0f;
    }
}

// base locomotion (baked clips or rest pose) + procedural layers
void App::poseCharacter(ClipPlayer& cp, anim::Driver& driver,
                        const anim::Input& in, float speed01, bool running,
                        std::vector<glm::mat4>& bones) {
    if (!charRig_.valid)
        return;
    if (clipsReady_) {
        // slow the locomotion cycle down in the air / water / death so the
        // procedural layers can take over
        const float rate = driver.state == anim::AIR    ? 0.30f
                           : driver.state == anim::SWIM ? 0.15f
                           : driver.state == anim::DEAD ? 0.0f
                                                        : 1.0f;
        if (const char* ph = std::getenv("BW_ANIM_PHASE")) {
            cp.clip = clipWalk_;
            cp.prev = -1;
            cp.fade = 1.0f;
            cp.time = (float)(std::atof(ph) / (2.0 * 3.141592653589793) *
                              charScene_.animations[clipWalk_].duration);
        } else if (std::getenv("BW_ANIM_FORCE")) {
            updateClipPlayer(cp, in.dt, 1.0f, false, rate);
        } else {
            updateClipPlayer(cp, in.dt, speed01, running, rate);
        }
        sampleClip(charScene_.animations[cp.clip], cp.time, poseA_);
        if (cp.prev >= 0 && cp.fade < 1.0f) {
            sampleClip(charScene_.animations[cp.prev], cp.prevTime, poseB_);
            const float w = cp.fade * cp.fade * (3.0f - 2.0f * cp.fade);
            blendPose(poseB_, poseA_, w, poseMix_);
            applyPose(poseMix_, poseLocals_);
        } else {
            applyPose(poseA_, poseLocals_);
        }
    } else {
        applyPose(restPose_, poseLocals_);
    }
    driver.overlay(charScene_, charRig_, poseLocals_, in);
    model::computeNodeGlobals(charScene_, poseLocals_, poseGlobals_);
    const int skinIndex = charScene_.skins.empty() ? -1 : 0;
    model::computeSkinMatrices(charScene_, poseGlobals_, skinIndex, bones);
    if (bones.size() > 32)
        bones.resize(32);
}

anim::Input App::playerAnimInput() const {
    const auto& p = game_->player;
    anim::Input in;
    in.dt = (float)animDt_;
    in.speed = (float)std::hypot(p.velocity.x, p.velocity.z);
    in.maxSpeed = (float)p.moveSpeed;
    in.running = p.run();
    in.onFloor = p.onFloor && !p.inWater;
    in.inWater = p.inWater;
    in.dead = p.dead;
    in.vy = (float)p.velocity.y;
    in.yaw = (float)p.yaw;
    in.pitch = (float)p.pitch;
    in.proceduralBase = !clipsReady_;
    const bool combat = p.interactionMode == bw::INTERACT_COMBAT;
    in.aiming = combat && p.weapon == bw::WEAPON_CROSSBOW && !p.dead;
    in.armed = combat && p.weapon == bw::WEAPON_SWORD && !p.dead;
    if (!p.dead) {
        if (p.weapon == bw::WEAPON_SWORD && p.swordTimer > 0.0)
            in.attack = (float)(1.0 - p.swordTimer / 0.35);
        else if (p.weapon == bw::WEAPON_CROSSBOW && shootCooldown_ > 0.0)
            in.attack = (float)(1.0 - shootCooldown_ / 0.45);
        in.attackKind = p.weapon == bw::WEAPON_SWORD ? 1 : 0;
    }
    if (hitTimer_ > 0.0)
        in.hit = (float)(1.0 - hitTimer_ / 0.35);
    // debug overrides for animation inspection (BW_ANIM_* env)
    if (const char* s = std::getenv("BW_ANIM_STATE")) {
        if (std::strcmp(s, "air") == 0)
            in.onFloor = false;
        else if (std::strcmp(s, "swim") == 0) {
            in.inWater = true;
            in.onFloor = false;
        } else if (std::strcmp(s, "dead") == 0)
            in.dead = true;
    }
    if (const char* v = std::getenv("BW_ANIM_SPEED"))
        in.speed = (float)std::atof(v) * in.maxSpeed;
    if (const char* v = std::getenv("BW_ANIM_VY"))
        in.vy = (float)std::atof(v);
    if (std::getenv("BW_ANIM_AIM"))
        in.aiming = true;
    if (std::getenv("BW_ANIM_SWORD"))
        in.armed = true;
    if (const char* v = std::getenv("BW_ANIM_ATTACK")) {
        in.attack = (float)std::atof(v);
        in.attackKind = std::getenv("BW_ANIM_KIND")
                            ? std::atoi(std::getenv("BW_ANIM_KIND"))
                            : 0;
    }
    if (const char* v = std::getenv("BW_ANIM_HIT"))
        in.hit = (float)std::atof(v);
    return in;
}

anim::Input App::remoteAnimInput(const RemotePlayer& r) const {
    anim::Input in;
    in.dt = (float)animDt_;
    const double dist = glm::length(r.targetPos - r.pos);
    in.speed = (float)std::min(20.0, dist * 8.0);
    in.maxSpeed = 7.0f;
    in.running = in.speed > 7.0f;
    in.dead = !r.alive;
    in.yaw = (float)r.yaw;
    in.pitch = 0.0f;
    in.vy = (float)((r.targetPos.y - r.pos.y) * 8.0);
    in.onFloor = !(in.vy > 0.5f && in.speed > 0.5f);
    in.inWater = r.pos.y < bw::WATER_LEVEL - 0.25;
    in.proceduralBase = !clipsReady_;
    return in;
}

void App::render() {
    glViewport(0, 0, fbW_, fbH_);
    glClearColor(FOG_COLOR.r, FOG_COLOR.g, FOG_COLOR.b, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    const bool prof = std::getenv("DEBUG_PROFILE") != nullptr;
    auto tick = [] { return std::chrono::steady_clock::now(); };
    auto ms = [](auto a, auto b) {
        return std::chrono::duration<double, std::milli>(b - a).count();
    };
    auto t0 = tick();
    renderTerrain();
    auto t1 = tick();
    renderBlocks();
    auto t1b = tick();
    if (editorMode_)
        renderEditor();
    auto t1c = tick();
    renderEntities();
    auto t1d = tick();
    renderPlayerModel();
    renderViewmodel();
    auto t2 = tick();
    renderWater();
    auto t3 = tick();
    glDisable(GL_DEPTH_TEST);
    renderUI();
    glEnable(GL_DEPTH_TEST);
    auto t4 = tick();
    if (prof)
        std::printf(
            "[render terrain=%.1f blocks=%.1f editor=%.1f ents=%.1f rest=%.1f "
            "water=%.1f ui=%.1f]\n",
            ms(t0, t1), ms(t1, t1b), ms(t1b, t1c), ms(t1c, t1d),
            ms(t1d, t2), ms(t2, t3), ms(t3, t4));
}

void App::renderTerrain() {
    glUseProgram(progTerrain_);
    const glm::dvec3 eye = cameraEye();
    const glm::dvec3 fwd = cameraForward();
    const glm::mat4 view =
        glm::lookAt(glm::vec3(eye), glm::vec3(eye + fwd), glm::vec3(0, 1, 0));
    const float aspect =
        fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
    const glm::mat4 proj =
        glm::perspective(glm::radians((float)game_->player.fov), aspect, 0.1f,
                         2600.0f);
    glUniformMatrix4fv(glGetUniformLocation(progTerrain_, "uMvp"), 1, GL_FALSE,
                       glm::value_ptr(proj * view));
    const glm::vec3 eyeF((float)eye.x, (float)eye.y, (float)eye.z);
    glUniform3fv(glGetUniformLocation(progTerrain_, "uCamPos"), 1,
                 glm::value_ptr(eyeF));
    glUniform3fv(glGetUniformLocation(progTerrain_, "uSunDir"), 1,
                 glm::value_ptr(SUN_DIR));
    glUniform3fv(glGetUniformLocation(progTerrain_, "uFogColor"), 1,
                 glm::value_ptr(FOG_COLOR));
    glUniform1f(glGetUniformLocation(progTerrain_, "uFogStart"), 320.0f);
    glUniform1f(glGetUniformLocation(progTerrain_, "uFogEnd"), (float)FOG_END);
    glUniform1f(glGetUniformLocation(progTerrain_, "uRelief"),
                (float)terrain::RELIEF_SCALE);
    glUniform1f(glGetUniformLocation(progTerrain_, "uPbr"),
                terrainPbr_ ? 1.0f : 0.0f);
    glUniform1f(glGetUniformLocation(progTerrain_, "uTexScale"), 0.33f);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D_ARRAY, terrainAlbedo_);
    glUniform1i(glGetUniformLocation(progTerrain_, "uAlbedoRough"), 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D_ARRAY, terrainNormal_);
    glUniform1i(glGetUniformLocation(progTerrain_, "uNormalTex"), 1);
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D_ARRAY, terrainExtra_);
    glUniform1i(glGetUniformLocation(progTerrain_, "uExtraTex"), 2);
    glActiveTexture(GL_TEXTURE0);
    glUniform1f(glGetUniformLocation(progTerrain_, "uParallax"), 0.045f);

    const int64_t pcx = (int64_t)std::floor(
        world::colIndex(game_->player.pos.x) / (double)world::PAGE_CELLS);
    const int64_t pcz = (int64_t)std::floor(
        world::colIndex(game_->player.pos.z) / (double)world::PAGE_CELLS);
    for (auto& [key, p] : game_->terrain.pages()) {
        if (!p.built)
            continue;
        if (std::abs(p.px - pcx) > rPages_ || std::abs(p.pz - pcz) > rPages_)
            continue;
        auto it = pageGL_.find(world::pageKey(p.px, p.pz));
        if (it == pageGL_.end() || !it->second.vertexCount)
            continue;
        glBindVertexArray(it->second.vao);
        glDrawElements(GL_TRIANGLES,
                       (GLsizei)(world::PAGE_CELLS *
                                 world::PAGE_CELLS * 6),
                       GL_UNSIGNED_INT, nullptr);
    }
    glBindVertexArray(0);
}

void App::renderBlocks() {
    if (game_->blocks.count() == 0)
        return;
    const glm::dvec3 eye = cameraEye();
    const glm::dvec3 fwd = cameraForward();
    const glm::mat4 view =
        glm::lookAt(glm::vec3(eye), glm::vec3(eye + fwd), glm::vec3(0, 1, 0));
    const float aspect =
        fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
    const glm::mat4 proj =
        glm::perspective(glm::radians((float)game_->player.fov), aspect, 0.1f,
                         2600.0f);
    glUseProgram(progBlock_);
    glUniformMatrix4fv(glGetUniformLocation(progBlock_, "uMvp"), 1, GL_FALSE,
                       glm::value_ptr(proj * view));
    const glm::vec3 eyeF((float)eye.x, (float)eye.y, (float)eye.z);
    glUniform3fv(glGetUniformLocation(progBlock_, "uCamPos"), 1,
                 glm::value_ptr(eyeF));
    glUniform3fv(glGetUniformLocation(progBlock_, "uSunDir"), 1,
                 glm::value_ptr(SUN_DIR));
    glUniform3fv(glGetUniformLocation(progBlock_, "uFogColor"), 1,
                 glm::value_ptr(FOG_COLOR));
    glUniform1f(glGetUniformLocation(progBlock_, "uFogEnd"), (float)FOG_END);
    glBindVertexArray(cubeVao_);
    glBindBuffer(GL_ARRAY_BUFFER, instVbo_);
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                          (void*)0);
    glVertexAttribDivisor(2, 1);
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                          (void*)(3 * sizeof(float)));
    glVertexAttribDivisor(3, 1);
    glDrawElementsInstanced(GL_TRIANGLES, 36, GL_UNSIGNED_INT, nullptr,
                            (GLsizei)game_->blocks.count());
    glBindVertexArray(0);
}

void App::renderEditor() {
    if (editor_.blocks.empty())
        return;
    const glm::dvec3 eye = cameraEye();
    const glm::dvec3 fwd = cameraForward();
    const glm::mat4 view =
        glm::lookAt(glm::vec3(eye), glm::vec3(eye + fwd), glm::vec3(0, 1, 0));
    const float aspect =
        fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
    const glm::mat4 proj =
        glm::perspective(glm::radians((float)game_->player.fov), aspect, 0.1f,
                         2600.0f);
    std::vector<float> inst;
    inst.reserve(editor_.blocks.size() * 6);
    for (const auto& [c, id] : editor_.blocks) {
        const float cx = (float)(bw::blockCellMin(editorOrigin_.x + c.x) +
                                 bw::BLOCK_CELL * 0.5);
        const float cy = (float)(bw::blockCellMin(editorBaseY_ + c.y) +
                                 bw::BLOCK_CELL * 0.5);
        const float cz = (float)(bw::blockCellMin(editorOrigin_.z + c.z) +
                                 bw::BLOCK_CELL * 0.5);
        const glm::vec3 col = bw::blockColor(id);
        inst.insert(inst.end(), {cx, cy, cz, col.r, col.g, col.b});
    }
    glUseProgram(progBlock_);
    glUniformMatrix4fv(glGetUniformLocation(progBlock_, "uMvp"), 1, GL_FALSE,
                       glm::value_ptr(proj * view));
    const glm::vec3 eyeF((float)eye.x, (float)eye.y, (float)eye.z);
    glUniform3fv(glGetUniformLocation(progBlock_, "uCamPos"), 1,
                 glm::value_ptr(eyeF));
    glUniform3fv(glGetUniformLocation(progBlock_, "uSunDir"), 1,
                 glm::value_ptr(SUN_DIR));
    glUniform3fv(glGetUniformLocation(progBlock_, "uFogColor"), 1,
                 glm::value_ptr(FOG_COLOR));
    glUniform1f(glGetUniformLocation(progBlock_, "uFogEnd"), (float)FOG_END);
    glBindVertexArray(cubeVao_);
    glBindBuffer(GL_ARRAY_BUFFER, editorInstVbo_);
    glBufferData(GL_ARRAY_BUFFER, inst.size() * sizeof(float), inst.data(),
                 GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                          (void*)0);
    glVertexAttribDivisor(2, 1);
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                          (void*)(3 * sizeof(float)));
    glVertexAttribDivisor(3, 1);
    glDrawElementsInstanced(GL_TRIANGLES, 36, GL_UNSIGNED_INT, nullptr,
                            (GLsizei)editor_.blocks.size());
    glBindVertexArray(0);
}

void App::renderEntities() {
    const glm::dvec3 eye = cameraEye();
    const glm::dvec3 fwd = cameraForward();
    const glm::mat4 view =
        glm::lookAt(glm::vec3(eye), glm::vec3(eye + fwd), glm::vec3(0, 1, 0));
    const float aspect =
        fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
    const glm::mat4 proj =
        glm::perspective(glm::radians((float)game_->player.fov), aspect, 0.1f,
                         2600.0f);
    glUseProgram(progModel_);
    glUniformMatrix4fv(glGetUniformLocation(progModel_, "uMvp"), 1, GL_FALSE,
                       glm::value_ptr(proj * view));
    setModelUniforms();

    const double now = glfwGetTime();
    if (std::getenv("DEBUG_PROFILE")) {
        size_t sp = 0;
        for (const auto& [k, list] : game_->enemies.spawners()) {
            (void)k;
            sp += list.size();
        }
        std::printf("[ents spawners=%zu balloons=%zu arrows=%zu remotes=%zu]\n",
                    sp, game_->enemies.balloons().size(),
                    game_->enemies.arrows().size(), remotes_.size());
    }
    // fast mode: cheap instanced cubes instead of the heavy GLB props
    if (fastMode_) {
        std::vector<float> inst;
        for (const auto& [key, list] : game_->enemies.spawners()) {
            (void)key;
            for (const auto& s : list) {
                if (glm::length(glm::dvec3(s.pos) - eye) > 160.0)
                    continue;
                inst.insert(inst.end(), {(float)s.pos.x, (float)s.pos.y,
                                         (float)s.pos.z, 0.25f, 0.25f, 0.28f});
            }
        }
        for (const auto& b : game_->enemies.balloons()) {
            if (b.dead || glm::length(b.pos - eye) > 900.0)
                continue;
            glm::vec3 col(0.9f, 0.35f, 0.35f);
            if (b.type == 1)
                col = {0.95f, 0.85f, 0.3f};
            else if (b.type == 2)
                col = {0.5f, 0.7f, 1.0f};
            inst.insert(inst.end(), {(float)b.pos.x, (float)b.pos.y,
                                     (float)b.pos.z, col.r, col.g, col.b});
        }
        if (!inst.empty()) {
            glUseProgram(progBlock_);
            glUniformMatrix4fv(glGetUniformLocation(progBlock_, "uMvp"), 1,
                               GL_FALSE, glm::value_ptr(proj * view));
            const glm::vec3 eyeF((float)eye.x, (float)eye.y, (float)eye.z);
            glUniform3fv(glGetUniformLocation(progBlock_, "uCamPos"), 1,
                         glm::value_ptr(eyeF));
            glUniform3fv(glGetUniformLocation(progBlock_, "uSunDir"), 1,
                         glm::value_ptr(SUN_DIR));
            glUniform3fv(glGetUniformLocation(progBlock_, "uFogColor"), 1,
                         glm::value_ptr(FOG_COLOR));
            glUniform1f(glGetUniformLocation(progBlock_, "uFogEnd"),
                        (float)FOG_END);
            glBindVertexArray(cubeVao_);
            glBindBuffer(GL_ARRAY_BUFFER, editorInstVbo_);
            glBufferData(GL_ARRAY_BUFFER, inst.size() * sizeof(float),
                         inst.data(), GL_DYNAMIC_DRAW);
            glEnableVertexAttribArray(2);
            glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                                  (void*)0);
            glVertexAttribDivisor(2, 1);
            glEnableVertexAttribArray(3);
            glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                                  (void*)(3 * sizeof(float)));
            glVertexAttribDivisor(3, 1);
            glDrawElementsInstanced(GL_TRIANGLES, 36, GL_UNSIGNED_INT, nullptr,
                                    (GLsizei)(inst.size() / 6));
            glBindVertexArray(0);
        }
        glUseProgram(progModel_);
        glUniformMatrix4fv(glGetUniformLocation(progModel_, "uMvp"), 1,
                           GL_FALSE, glm::value_ptr(proj * view));
        setModelUniforms();
    }
    // spawners
    if (spawnerGL_.ok && !fastMode_) {
        const glm::vec3 sz = spawnerScene_.bmax - spawnerScene_.bmin;
        const float diag = glm::length(sz);
        const float scale = diag > 1e-3f ? 3.0f / diag : 1.0f;
        const glm::vec3 centre = (spawnerScene_.bmin + spawnerScene_.bmax) * 0.5f;
        for (const auto& [key, list] : game_->enemies.spawners()) {
            (void)key;
            for (const auto& s : list) {
                if (glm::length(glm::dvec3(s.pos) - eye) > 130.0)
                    continue;
                glm::mat4 m = glm::translate(glm::mat4(1.0f), glm::vec3(s.pos));
                m = glm::scale(m, glm::vec3(scale));
                m = m * glm::translate(glm::mat4(1.0f), -centre);
                drawSceneAt(spawnerScene_, spawnerGL_, m, glm::vec3(1.0f));
            }
        }
    }
    // balloons
    if (balloonGL_.ok && !fastMode_) {
        const glm::vec3 centre = (balloonScene_.bmin + balloonScene_.bmax) * 0.5f;
        for (const auto& b : game_->enemies.balloons()) {
            if (b.dead)
                continue;
            if (glm::length(b.pos - eye) > 900.0)
                continue;
            float target = b.type == 2 ? 3.2f : (b.type == 1 ? 1.6f : 2.2f);
            const glm::vec3 sz = balloonScene_.bmax - balloonScene_.bmin;
            const float diag = glm::length(sz);
            const float scale = diag > 1e-3f ? target / diag : 1.0f;
            const float bob = (float)std::sin(now * 2.0 + b.pos.x * 0.1) * 0.15f;
            glm::mat4 m = glm::translate(
                glm::mat4(1.0f), glm::vec3(b.pos) + glm::vec3(0, bob, 0));
            m = glm::scale(m, glm::vec3(scale));
            m = m * glm::translate(glm::mat4(1.0f), -centre);
            glm::vec3 tint(1.0f);
            if (b.hitFlash > 0.0)
                tint = glm::vec3(1.0f, 0.4f, 0.4f);
            else if (b.type == 1)
                tint = glm::vec3(1.0f, 0.9f, 0.35f);
            else if (b.type == 2)
                tint = glm::vec3(0.55f, 0.75f, 1.0f);
            drawSceneAt(balloonScene_, balloonGL_, m, tint);
        }
    }
    // arrows
    if (arrowGL_.ok) {
        for (const auto& a : game_->enemies.arrows()) {
            if (glm::length(a->pos - eye) > 400.0)
                continue;
            const glm::mat4 m =
                bw::arrowModelMatrix(arrowScene_, a->pos, a->dir);
            drawSceneAt(arrowScene_, arrowGL_, m, glm::vec3(1.0f));
        }
    }
    // remote players
    if (!remotes_.empty()) {
        if (charGL_.ok) {
            for (const auto& r : remotes_) {
                const glm::mat4 m =
                    anim::characterMatrix(charScene_, r.pos, r.yaw);
                const glm::vec3 tint =
                    r.alive ? glm::vec3(0.8f, 0.9f, 1.0f)
                            : glm::vec3(0.5f, 0.5f, 0.5f);
                if (charScene_.skinned() && charRig_.valid) {
                    anim::Input in = remoteAnimInput(r);
                    const float speed01 =
                        std::min(1.0f, in.speed / in.maxSpeed);
                    poseCharacter(remoteClips_[r.id], remoteDrivers_[r.id], in,
                                  speed01, in.running, poseBones_);
                    drawSkinned(charScene_, charGL_, proj * view, m, tint,
                                poseBones_);
                } else {
                    drawSceneAt(charScene_, charGL_, m, tint);
                }
            }
        } else {
            // fallback capsules via the block shader
            glUseProgram(progBlock_);
            glUniformMatrix4fv(glGetUniformLocation(progBlock_, "uMvp"), 1,
                               GL_FALSE, glm::value_ptr(proj * view));
            const glm::vec3 eyeF((float)eye.x, (float)eye.y, (float)eye.z);
            glUniform3fv(glGetUniformLocation(progBlock_, "uCamPos"), 1,
                         glm::value_ptr(eyeF));
            glUniform3fv(glGetUniformLocation(progBlock_, "uSunDir"), 1,
                         glm::value_ptr(SUN_DIR));
            glUniform3fv(glGetUniformLocation(progBlock_, "uFogColor"), 1,
                         glm::value_ptr(FOG_COLOR));
            glUniform1f(glGetUniformLocation(progBlock_, "uFogEnd"),
                        (float)FOG_END);
            std::vector<float> inst;
            for (const auto& r : remotes_)
                inst.insert(inst.end(),
                            {(float)r.pos.x, (float)r.pos.y + 1.0f,
                             (float)r.pos.z, 0.8f, 0.85f, 0.9f});
            if (!inst.empty()) {
                glBindVertexArray(cubeVao_);
                glBindBuffer(GL_ARRAY_BUFFER, editorInstVbo_);
                glBufferData(GL_ARRAY_BUFFER, inst.size() * sizeof(float),
                             inst.data(), GL_DYNAMIC_DRAW);
                glEnableVertexAttribArray(2);
                glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE,
                                      6 * sizeof(float), (void*)0);
                glVertexAttribDivisor(2, 1);
                glEnableVertexAttribArray(3);
                glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE,
                                      6 * sizeof(float),
                                      (void*)(3 * sizeof(float)));
                glVertexAttribDivisor(3, 1);
                glDrawElementsInstanced(GL_TRIANGLES, 36, GL_UNSIGNED_INT,
                                        nullptr, (GLsizei)remotes_.size());
                glBindVertexArray(0);
            }
        }
    }
}

void App::renderPlayerModel() {
    const auto& p = game_->player;
    if (p.cameraMode != bw::CAMERA_THIRD_PERSON)
        return;
    const glm::dvec3 eye = cameraEye();
    const glm::dvec3 fwd = cameraForward();
    const glm::mat4 view =
        glm::lookAt(glm::vec3(eye), glm::vec3(eye + fwd), glm::vec3(0, 1, 0));
    const float aspect =
        fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
    const glm::mat4 proj =
        glm::perspective(glm::radians((float)p.fov), aspect, 0.1f, 2600.0f);
    if (charGL_.ok) {
        const glm::mat4 m =
            anim::characterMatrix(charScene_, p.pos, p.yaw);
        if (charScene_.skinned() && charRig_.valid) {
            anim::Input in = playerAnimInput();
            const float speed01 =
                std::min(1.0f, in.speed / std::max(0.1f, in.maxSpeed));
            poseCharacter(playerClip_, playerDriver_, in, speed01, in.running,
                          poseBones_);
            drawSkinned(charScene_, charGL_, proj * view, m, glm::vec3(1.0f),
                        poseBones_);
        } else {
            glUseProgram(progModel_);
            glUniformMatrix4fv(glGetUniformLocation(progModel_, "uMvp"), 1,
                               GL_FALSE, glm::value_ptr(proj * view));
            setModelUniforms();
            drawSceneAt(charScene_, charGL_, m, glm::vec3(1.0f));
        }
    }
}

void App::renderViewmodel() {
    const auto& p = game_->player;
    if (p.cameraMode == bw::CAMERA_FREECAM || editorMode_ ||
        p.interactionMode == bw::INTERACT_DIG)
        return;
    const glm::dvec3 eye = cameraEye();
    const glm::dvec3 fwd = glm::normalize(cameraForward());
    glm::dvec3 right = glm::cross(fwd, glm::dvec3(0, 1, 0));
    if (glm::length(right) < 1e-5)
        right = {1, 0, 0};
    right = glm::normalize(right);
    const glm::dvec3 up = glm::cross(right, fwd);
    const glm::dvec3 anchor = eye + fwd * 0.55 + right * 0.22 - up * 0.22;
    glm::mat4 basis(glm::vec4(glm::vec3(right), 0.0f),
                    glm::vec4(glm::vec3(up), 0.0f),
                    glm::vec4(glm::vec3(fwd), 0.0f),
                    glm::vec4(glm::vec3(anchor), 1.0f));
    const glm::dvec3 eyeF = cameraEye();
    const glm::dvec3 f = cameraForward();
    const glm::mat4 view = glm::lookAt(glm::vec3(eyeF), glm::vec3(eyeF + f),
                                       glm::vec3(0, 1, 0));
    const float aspect =
        fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
    const glm::mat4 proj =
        glm::perspective(glm::radians((float)p.fov), aspect, 0.1f, 2600.0f);
    glUseProgram(progModel_);
    glUniformMatrix4fv(glGetUniformLocation(progModel_, "uMvp"), 1, GL_FALSE,
                       glm::value_ptr(proj * view));
    setModelUniforms();
    glDisable(GL_DEPTH_TEST);
    // simple box weapon: crossbow is long, sword shorter
    const glm::vec3 tint = p.weapon == bw::WEAPON_CROSSBOW
                               ? glm::vec3(0.45f, 0.30f, 0.16f)
                               : glm::vec3(0.75f, 0.76f, 0.80f);
    glm::mat4 m = basis;
    if (p.weapon == bw::WEAPON_CROSSBOW)
        m = glm::scale(m, glm::vec3(0.08f, 0.08f, 0.85f));
    else
        m = glm::scale(m, glm::vec3(0.07f, 0.07f, 0.6f));
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, whiteTex_);
    glUniform3f(glGetUniformLocation(progModel_, "uColor"), tint.r, tint.g,
                tint.b);
    glUniform1f(glGetUniformLocation(progModel_, "uUnlit"), 1.0f);
    glUniformMatrix4fv(glGetUniformLocation(progModel_, "uModel"), 1, GL_FALSE,
                       glm::value_ptr(m));
    glBindVertexArray(cubeVao_);
    glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_INT, nullptr);
    glBindVertexArray(0);
    glEnable(GL_DEPTH_TEST);
}

void App::renderWater() {
    const glm::dvec3 eye = cameraEye();
    const glm::dvec3 fwd = cameraForward();
    const glm::mat4 view =
        glm::lookAt(glm::vec3(eye), glm::vec3(eye + fwd), glm::vec3(0, 1, 0));
    const float aspect =
        fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
    const glm::mat4 proj =
        glm::perspective(glm::radians((float)game_->player.fov), aspect, 0.1f,
                         2600.0f);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDepthMask(GL_FALSE);
    glUseProgram(progWater_);
    glUniformMatrix4fv(glGetUniformLocation(progWater_, "uMvp"), 1, GL_FALSE,
                       glm::value_ptr(proj * view));
    const glm::vec3 eyeF((float)eye.x, (float)eye.y, (float)eye.z);
    glUniform3fv(glGetUniformLocation(progWater_, "uCamPos"), 1,
                 glm::value_ptr(eyeF));
    glUniform3fv(glGetUniformLocation(progWater_, "uSunDir"), 1,
                 glm::value_ptr(SUN_DIR));
    glUniform3fv(glGetUniformLocation(progWater_, "uFogColor"), 1,
                 glm::value_ptr(FOG_COLOR));
    glUniform1f(glGetUniformLocation(progWater_, "uFogEnd"), (float)FOG_END);
    for (auto& [key, wp] : game_->water.pages()) {
        (void)key;
        if (!wp.hasWater || !wp.surfReady)
            continue;
        auto it = waterGL_.find(world::pageKey(wp.px, wp.pz));
        if (it == waterGL_.end() || !it->second.indexCount)
            continue;
        glBindVertexArray(it->second.vao);
        glDrawElements(GL_TRIANGLES, it->second.indexCount, GL_UNSIGNED_INT,
                       nullptr);
    }
    glBindVertexArray(0);
    glDepthMask(GL_TRUE);
    glDisable(GL_BLEND);
}

// ============================================================
// UI
// ============================================================

void App::renderUI() {
    ui_.clear();
    if (menuOpen_)
        drawMenu();
    else if (matchOver_)
        drawMatchOver();
    else
        drawHUD();
    if (craftingOpen_ && !menuOpen_)
        drawCrafting();
    if (editorMode_ && !menuOpen_)
        drawEditorHUD();
    if (chatActive_)
        ui_.rect(10, (float)fbH_ - 90, 520, 30, 0.05f, 0.06f, 0.08f, 0.9f);
    if (chatActive_)
        ui_.textAt(18, (float)fbH_ - 84, "T: " + chatInput_, 1, 1, 1, 1, 0.8f);
    if (debugOverlay_)
        drawDebugOverlay();

    // solid quads
    if (!ui_.solid.empty()) {
        std::vector<float> verts;
        verts.reserve(ui_.solid.size() * 36);
        for (const auto& q : ui_.solid) {
            const float x0 = q.x, y0 = q.y, x1 = q.x + q.w, y1 = q.y + q.h;
            const float v[36] = {
                x0, y0, q.r, q.g, q.b, q.a, x1, y0, q.r, q.g, q.b, q.a,
                x1, y1, q.r, q.g, q.b, q.a, x0, y0, q.r, q.g, q.b, q.a,
                x1, y1, q.r, q.g, q.b, q.a, x0, y1, q.r, q.g, q.b, q.a};
            verts.insert(verts.end(), v, v + 36);
        }
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glUseProgram(progUI_);
        glUniform2f(glGetUniformLocation(progUI_, "uRes"), (float)fbW_,
                    (float)fbH_);
        glBindVertexArray(uiVao_);
        glBindBuffer(GL_ARRAY_BUFFER, uiVbo_);
        glBufferData(GL_ARRAY_BUFFER, verts.size() * sizeof(float), verts.data(),
                     GL_DYNAMIC_DRAW);
        glDrawArrays(GL_TRIANGLES, 0, (GLsizei)(verts.size() / 6));
        glBindVertexArray(0);
        glDisable(GL_BLEND);
    }
    // text quads
    if (!ui_.text.empty()) {
        std::vector<float> verts;
        verts.reserve(ui_.text.size() * 48);
        for (const auto& q : ui_.text) {
            const float x0 = q.x, y0 = q.y, x1 = q.x + q.w, y1 = q.y + q.h;
            const float v[48] = {
                x0, y0, q.u0, q.v0, q.r, q.g, q.b, q.a,
                x1, y0, q.u1, q.v0, q.r, q.g, q.b, q.a,
                x1, y1, q.u1, q.v1, q.r, q.g, q.b, q.a,
                x0, y0, q.u0, q.v0, q.r, q.g, q.b, q.a,
                x1, y1, q.u1, q.v1, q.r, q.g, q.b, q.a,
                x0, y1, q.u0, q.v1, q.r, q.g, q.b, q.a};
            verts.insert(verts.end(), v, v + 48);
        }
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glUseProgram(progText_);
        glUniform2f(glGetUniformLocation(progText_, "uRes"), (float)fbW_,
                    (float)fbH_);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, fontTex_);
        glUniform1i(glGetUniformLocation(progText_, "uTex"), 0);
        glBindVertexArray(textVao_);
        glBindBuffer(GL_ARRAY_BUFFER, textVbo_);
        glBufferData(GL_ARRAY_BUFFER, verts.size() * sizeof(float), verts.data(),
                     GL_DYNAMIC_DRAW);
        glDrawArrays(GL_TRIANGLES, 0, (GLsizei)(verts.size() / 8));
        glBindVertexArray(0);
        glDisable(GL_BLEND);
    }
}

void App::drawMenu() {
    const float W = (float)fbW_, H = (float)fbH_;
    const auto items = menu_.items(true, network_.state.loggedIn,
                                   network_.state.inRoom,
                                   network_.state.isHost,
                                   network_.state.roomList,
                                   network_.state.roomIds);
    menu_.selected = std::min(menu_.selected, std::max(0, (int)items.size() - 1));
    menuHitboxes_.clear();

    ui_.rect(0, 0, W, H, 0.03f, 0.04f, 0.06f, 0.90f);
    ui_.rect(0, 0, W, 86, 0.10f, 0.17f, 0.21f, 0.98f);
    ui_.textCentered(W / 2, 18, "BALLOON WAR", 0.95f, 0.76f, 0.18f, 1.0f, 1.1f);
    ui_.textAt(24, 52, network_.state.loggedIn ? network_.state.username
                                               : "NEAUTENTIFICAT",
               0.75f, 0.88f, 0.91f, 1.0f, 0.5f);

    std::string title = "MENIU";
    if (menu_.screen == "play") title = "ALEGE MODUL";
    if (menu_.screen == "characters") title = "ALEGE PERSONAJUL";
    if (menu_.screen == "settings") title = "SETARI";
    if (menu_.screen == "confirm_delete") title = "STERGERE CONT";
    if (menu_.screen == "creator") title = "MOD CREATOR";
    if (menu_.screen == "login") title = "CONT";
    if (menu_.screen == "multiplayer") title = "MULTIPLAYER";
    ui_.textCentered(W / 2, 104, title, 1, 1, 1, 1, 0.8f);

    const float buttonW = std::min(520.0f, W - 60.0f);
    float buttonH = 42.0f;
    float gap = 8.0f;
    const int n = std::max(1, (int)items.size());
    float totalH = n * buttonH + (n - 1) * gap;
    float y0 = std::max(155.0f, (H - totalH) / 2.0f);
    if (y0 + totalH > H - 54) {
        buttonH = std::max(30.0f, (H - y0 - 60.0f) / n - 3.0f);
        gap = 3.0f;
        totalH = n * buttonH + (n - 1) * gap;
    }
    const float x0 = (W - buttonW) / 2.0f;
    for (int i = 0; i < (int)items.size(); ++i) {
        const float y = y0 + i * (buttonH + gap);
        const bool selected = i == menu_.selected;
        const bool active =
            items[i].action == "field:" + menu_.activeField;
        float r = 0.15f, g = 0.18f, b = 0.20f, a = 0.94f;
        float tr = 0.82f, tg = 0.88f, tb = 0.89f;
        if (!items[i].enabled) {
            r = 0.12f; g = 0.13f; b = 0.14f; a = 0.72f;
            tr = tg = tb = 0.45f;
        } else if (selected || active) {
            r = 0.13f; g = 0.42f; b = 0.48f;
            tr = tg = tb = 1.0f;
        }
        ui_.rect(x0, y, buttonW, buttonH, r, g, b, a);
        if (active)
            ui_.outline(x0, y, buttonW, buttonH, 0.92f, 0.70f, 0.18f, 0.9f,
                        2.0f);
        else
            ui_.outline(x0, y, buttonW, buttonH, 0.28f, 0.34f, 0.36f, 1.0f,
                        1.5f);
        const float scale = buttonH >= 38 ? 0.62f : 0.5f;
        ui_.textCentered(W / 2, y + buttonH * 0.5f - 8, items[i].label, tr, tg,
                         tb, 1.0f, scale);
        menuHitboxes_.push_back({x0, y});
    }
    if (!menu_.status.empty())
        ui_.textCentered(W / 2, H - 34, menu_.status.substr(0, 90), 0.92f, 0.76f,
                         0.28f, 1.0f, 0.55f);
    if (!status_.empty() && statusTimer_ > 0.0)
        ui_.textCentered(W / 2, H - 58, status_, 1.0f, 1.0f, 0.6f, 1.0f, 0.55f);
    ui_.textCentered(W / 2, H - 16,
                     "SAGETI + ENTER | CLICK | ESC REVINE", 0.6f, 0.65f, 0.7f,
                     1.0f, 0.45f);
}

void App::drawHUD() {
    const float W = (float)fbW_, H = (float)fbH_;
    const auto& p = game_->player;
    // crosshair
    glUseProgram(progCross_);
    glUniform3f(glGetUniformLocation(progCross_, "uColor"), 0.9f, 0.9f, 0.95f);
    glBindVertexArray(crossVao_);
    glDrawArrays(GL_LINES, 0, 4);
    glBindVertexArray(0);

    // health bar
    const float hpFrac =
        p.maxHealth > 0 ? (float)(p.health / p.maxHealth) : 0.0f;
    ui_.rect(20, 18, 240, 18, 0.10f, 0.10f, 0.12f, 0.8f);
    ui_.rect(22, 20, 236 * std::clamp(hpFrac, 0.0f, 1.0f), 14, 0.85f, 0.20f,
             0.20f, 0.95f);
    ui_.textAt(24, 42, "HP " + std::to_string((int)std::max(0.0, p.health)),
               1, 1, 1, 1, 0.5f);
    ui_.textAt(20, 62, "SCOR: " + std::to_string(p.score) + "   BALOANE: " +
                           std::to_string(p.balloonsPopped),
               1.0f, 0.85f, 0.3f, 1.0f, 0.55f);
    const std::string modeName = game_->match.rules.name;
    ui_.textAt(20, 84, modeName + "  " + game_->match.clockText() + "   INAMICI: " +
                           std::to_string((int)game_->enemies.balloons().size()),
               0.8f, 0.9f, 1.0f, 1.0f, 0.5f);

    // interaction mode + weapon
    const char* interact =
        p.interactionMode == bw::INTERACT_DIG
            ? "SAPA"
            : (p.interactionMode == bw::INTERACT_BUILD ? "CONSTRUIESTE"
                                                       : "COMBAT");
    const char* weapon =
        p.weapon == bw::WEAPON_CROSSBOW ? "ARBALETA" : "SABIE";
    const char* dig = p.digMode == bw::DIG_MODE_CUBE ? "CUB" : "SFERA";
    std::string modeLine = std::string("MODE: ") + interact + "  ARMA: " +
                           weapon + "  " + dig;
    if (p.interactionMode == bw::INTERACT_BUILD && !blueprints_.list().empty() &&
        blueprintIndex_ >= 0 && blueprintIndex_ < (int)blueprints_.list().size())
        modeLine += "  BLUEPRINT(P): " + blueprints_.list()[blueprintIndex_].name;
    ui_.textAt(20, H - 130, modeLine, 0.9f, 0.95f, 0.8f, 1.0f, 0.5f);

    // remote player nameplates
    if (!remotes_.empty()) {
        const glm::dvec3 eye = cameraEye();
        const glm::dvec3 fwd = cameraForward();
        const glm::mat4 view = glm::lookAt(glm::vec3(eye), glm::vec3(eye + fwd),
                                           glm::vec3(0, 1, 0));
        const float aspect =
            fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
        const glm::mat4 proj = glm::perspective(
            glm::radians((float)p.fov), aspect, 0.1f, 2600.0f);
        for (const auto& r : remotes_) {
            const glm::vec4 clip =
                proj * view *
                glm::vec4(glm::vec3(r.pos + glm::dvec3(0.0, 2.4, 0.0)), 1.0f);
            if (clip.w <= 0.001f)
                continue;
            const glm::vec3 ndc = glm::vec3(clip) / clip.w;
            if (ndc.x < -1.1f || ndc.x > 1.1f || ndc.y < -1.1f ||
                ndc.y > 1.1f)
                continue;
            const float sx = (ndc.x * 0.5f + 0.5f) * W;
            const float sy = (1.0f - (ndc.y * 0.5f + 0.5f)) * H;
            ui_.textCentered(sx, sy, r.name + (r.alive ? "" : " [mort]"), 0.95f,
                             0.95f, 1.0f, 0.95f, 0.5f);
        }
    }

    // death screen
    if (p.dead) {
        ui_.rect(0, 0, W, H, 0.35f, 0.0f, 0.0f, 0.42f);
        ui_.textCentered(W / 2, H * 0.40f, "AI MURIT", 1.0f, 0.35f, 0.35f, 1.0f,
                         1.3f);
        char buf[96];
        std::snprintf(buf, sizeof(buf), "RESPAWN IN %.1f s   (R = REPEDE)",
                      std::max(0.0, p.respawnTimer));
        ui_.textCentered(W / 2, H * 0.40f + 54, buf, 1.0f, 1.0f, 1.0f, 1.0f,
                         0.7f);
    }

    // hotbar
    const float slot = 52.0f, gap = 6.0f;
    const float totalW = bw::kInventorySlots * slot +
                         (bw::kInventorySlots - 1) * gap;
    const float x0 = W * 0.5f - totalW * 0.5f;
    const float y = H - slot - 16.0f;
    for (int i = 0; i < bw::kInventorySlots; ++i) {
        const float x = x0 + i * (slot + gap);
        const bool sel = i == p.inventory.selected;
        ui_.rect(x - 2, y - 2, slot + 4, slot + 4, sel ? 1.0f : 0.12f,
                 sel ? 1.0f : 0.12f, sel ? 1.0f : 0.12f, 0.95f);
        ui_.rect(x, y, slot, slot, 0.06f, 0.06f, 0.06f, 0.9f);
        const int type = bw::kBlockOrder[i];
        const glm::vec3 col = bw::blockColor(type);
        ui_.rect(x + 5, y + 5, slot - 10, slot - 10, col.r, col.g, col.b, 0.95f);
        const int count = p.inventory.counts[type];
        ui_.textAt(x + 6, y + slot - 18, std::to_string(count), 1, 1, 1, 1,
                   0.45f);
        ui_.textAt(x + slot - 12, y + 2, std::to_string((i + 1) % 10), 1, 1, 1,
                   0.8f, 0.4f);
    }

    // chat log
    if (!network_.chatMessages.empty()) {
        float cy = H - 200.0f;
        for (const auto& line : network_.chatMessages) {
            ui_.textAt(20, cy, line, 0.9f, 0.95f, 1.0f, 0.9f, 0.5f);
            cy += 20.0f;
        }
    }
    if (!status_.empty() && statusTimer_ > 0.0)
        ui_.textCentered(W / 2, 120, status_, 1.0f, 0.95f, 0.5f, 1.0f, 0.55f);

    // balloon puffs
    if (!puffs_.empty()) {
        std::vector<float> pd;
        for (const auto& pf : puffs_) {
            pd.insert(pd.end(), {(float)pf.pos.x, (float)pf.pos.y,
                                 (float)pf.pos.z, 1.0f, 0.5f, 0.5f, 0.8f});
        }
        const glm::dvec3 eye = cameraEye();
        const glm::dvec3 fwd = cameraForward();
        const glm::mat4 view = glm::lookAt(glm::vec3(eye),
                                           glm::vec3(eye + fwd),
                                           glm::vec3(0, 1, 0));
        const float aspect =
            fbH_ > 0 ? (float)fbW_ / (float)fbH_ : 16.0f / 9.0f;
        const glm::mat4 proj = glm::perspective(
            glm::radians((float)p.fov), aspect, 0.1f, 2600.0f);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glUseProgram(progPuff_);
        glUniformMatrix4fv(glGetUniformLocation(progPuff_, "uMvp"), 1, GL_FALSE,
                           glm::value_ptr(proj * view));
        glUniform1f(glGetUniformLocation(progPuff_, "uSize"), 18.0f);
        glBindBuffer(GL_ARRAY_BUFFER, puffVbo_);
        glBufferData(GL_ARRAY_BUFFER, pd.size() * sizeof(float), pd.data(),
                     GL_DYNAMIC_DRAW);
        glBindVertexArray(puffVao_);
        glDrawArrays(GL_POINTS, 0, (GLsizei)(pd.size() / 7));
        glBindVertexArray(0);
        glDisable(GL_BLEND);
        glDisable(GL_DEPTH_TEST);
    }
}

void App::drawDebugOverlay() {
    const float W = (float)fbW_;
    size_t builtPages = 0, dirtyPages = 0;
    for (const auto& [key, p] : game_->terrain.pages()) {
        (void)key;
        if (p.built)
            ++builtPages;
        if (p.dirtyMesh)
            ++dirtyPages;
    }
    size_t wetPages = 0;
    for (const auto& [key, wp] : game_->water.pages()) {
        (void)key;
        if (wp.hasWater)
            ++wetPages;
    }
    size_t spawners = 0;
    for (const auto& [key, list] : game_->enemies.spawners()) {
        (void)key;
        spawners += list.size();
    }
    const auto& p = game_->player;
    const double fps = frameMs_ > 0.01 ? 1000.0 / frameMs_ : 0.0;
    char buf[64];
    std::vector<std::string> lines;
    std::snprintf(buf, sizeof(buf), "FPS %.0f  frame %.1f ms (peak %.1f)",
                  fps, frameMs_, frameMsPeak_);
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "seed %d  relief %.1f  mode %s",
                  game_->config.world_seed, terrain::RELIEF_SCALE,
                  game_->matchMode.c_str());
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "pos %.1f %.1f %.1f  yaw %.0f  pitch %.0f",
                  p.pos.x, p.pos.y, p.pos.z, p.yaw * 57.2958,
                  p.pitch * 57.2958);
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "camera %d  interact %d  dig %d  weapon %d",
                  p.cameraMode, p.interactionMode, p.digMode, p.weapon);
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "onFloor %d  inWater %d  dead %d  hp %.0f",
                  (int)p.onFloor, (int)p.inWater, (int)p.dead, p.health);
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "blocks %zu (v%llu)  pages %zu built/%zu total (%zu dirty)",
                  game_->blocks.count(),
                  (unsigned long long)game_->blocks.version(), builtPages,
                  game_->terrain.pages().size(), dirtyPages);
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "water %zu pages  balloons %zu  arrows %zu  spawners %zu",
                  wetPages, game_->enemies.balloons().size(),
                  game_->enemies.arrows().size(), spawners);
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "remote %zu  net conn %d login %d room %s",
                  remotes_.size(), (int)network_.state.connected,
                  (int)network_.state.loggedIn,
                  network_.state.roomId.empty() ? "-"
                                                : network_.state.roomId.c_str());
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "status: %s",
                  status_.empty() ? "-" : status_.c_str());
    lines.push_back(buf);
    std::snprintf(buf, sizeof(buf), "log: %s", bw::dbg::logPath().c_str());
    lines.push_back(buf);

    const float lineH = 15.0f;
    const float panelW = 620.0f;
    const float panelH = lines.size() * lineH + 12.0f;
    const float x = W - panelW - 12.0f;
    ui_.rect(x, 8, panelW, panelH, 0.02f, 0.03f, 0.05f, 0.78f);
    ui_.outline(x, 8, panelW, panelH, 0.3f, 0.8f, 0.4f, 0.8f, 1.0f);
    float y = 14.0f;
    for (const auto& line : lines) {
        ui_.textAt(x + 8, y, line, 0.75f, 1.0f, 0.8f, 1.0f, 0.42f);
        y += lineH;
    }
}

void App::drawCrafting() {
    const float W = (float)fbW_, H = (float)fbH_;
    ui_.rect(W * 0.5f - 260, 80, 520, H - 220, 0.05f, 0.06f, 0.08f, 0.92f);
    ui_.textCentered(W / 2, 96, "CRAFTING (I INCHIDE)", 0.95f, 0.8f, 0.3f, 1.0f,
                     0.7f);
    const auto& recipes = game_->crafting.recipes();
    float y = 140;
    for (int i = 0; i < (int)recipes.size(); ++i) {
        const auto& r = recipes[i];
        const bool can =
            game_->crafting.canCraft(r, game_->player.inventory.counts);
        const bool sel = i == craftIndex_;
        ui_.rect(W * 0.5f - 240, y - 4, 480, 34,
                 sel ? 0.13f : 0.09f, sel ? 0.35f : 0.10f,
                 sel ? 0.40f : 0.12f, 0.9f);
        ui_.textAt(W * 0.5f - 228, y, r.name + (can ? "  [ENTER]" : "  (lipsa)"),
                   can ? 1.0f : 0.5f, can ? 1.0f : 0.5f, can ? 1.0f : 0.5f,
                   1.0f, 0.55f);
        y += 38;
    }
    ui_.textCentered(W / 2, H - 130, "SAGETI SUS/JOS + ENTER", 0.8f, 0.8f, 0.8f,
                     1.0f, 0.5f);
}

void App::drawEditorHUD() {
    const float W = (float)fbW_, H = (float)fbH_;
    ui_.rect(0, 0, W, 64, 0.08f, 0.10f, 0.12f, 0.85f);
    ui_.textCentered(W / 2, 10, "EDITOR STRUCTURI", 0.95f, 0.8f, 0.3f, 1.0f,
                     0.8f);
    ui_.textAt(16, 40,
               "CLICK STANGA: PUNE | CLICK DREAPTA: STERGE | SCROLL: NIVEL " +
                   std::to_string(editorPlane_) + " | WASD ZBOR | ESC MENIU",
               0.9f, 0.95f, 1.0f, 1.0f, 0.45f);
    ui_.textAt(16, 70, "NUME: " + menu_.editorName + "   BLOCURI: " +
                           std::to_string(editor_.blocks.size()),
               1.0f, 1.0f, 1.0f, 1.0f, 0.5f);
    // type palette
    const float slot = 40.0f;
    for (int i = 0; i < bw::kInventorySlots; ++i) {
        const float x = 16 + i * (slot + 4);
        const int type = bw::kBlockOrder[i];
        const glm::vec3 col = bw::blockColor(type);
        const bool sel = type == game_->player.inventory.selectedType();
        ui_.rect(x - 2, H - slot - 50, slot + 4, slot + 4,
                 sel ? 1.0f : 0.1f, sel ? 1.0f : 0.1f, sel ? 1.0f : 0.1f, 0.9f);
        ui_.rect(x, H - slot - 48, slot, slot, col.r, col.g, col.b, 0.95f);
        ui_.textAt(x + 4, H - slot - 48, std::to_string((i + 1) % 10), 1, 1, 1,
                   0.8f, 0.4f);
    }
    if (!status_.empty() && statusTimer_ > 0.0)
        ui_.textCentered(W / 2, H - 110, status_, 1.0f, 0.95f, 0.5f, 1.0f,
                         0.55f);
}

void App::drawMatchOver() {
    const float W = (float)fbW_, H = (float)fbH_;
    ui_.rect(0, 0, W, H, 0.02f, 0.03f, 0.05f, 0.82f);
    ui_.textCentered(W / 2, H * 0.32f, "MECI TERMINAT", 1.0f, 0.8f, 0.25f, 1.0f,
                     1.2f);
    ui_.textCentered(W / 2, H * 0.32f + 50,
                     "SCOR FINAL: " + std::to_string(game_->player.score),
                     1, 1, 1, 1, 0.8f);
    ui_.textCentered(W / 2, H * 0.32f + 86,
                     "BALOANE SPARTE: " +
                         std::to_string(game_->player.balloonsPopped),
                     1, 1, 1, 1, 0.8f);
    ui_.textCentered(W / 2, H * 0.32f + 140, "APASA ENTER PENTRU MENIU",
                     0.9f, 0.95f, 1.0f, 1.0f, 0.6f);
}

std::string App::handleMenuAction(const std::string& action) {
    if (action.empty())
        return "";
    if (action == "resume") {
        menuOpen_ = false;
        mouseLocked_ = true;
        glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
        firstMouse_ = true;
        return "";
    }
    if (action == "quit") {
        glfwSetWindowShouldClose(window_, GLFW_TRUE);
        return "";
    }
    if (action == "save_game") {
        saveGameToDisk();
        return "";
    }
    if (action == "load_game") {
        loadGameFromDisk();
        return "";
    }
    if (action == "start_singleplayer") {
        leaveEditor();
        bw::WorldConfig cfg = menu_.creatorConfig();
        initWorld(cfg, menu_.selectedSingleplayerMode(), menu_.selectedCharacter);
        menu_.inGame = true;
        menuOpen_ = false;
        mouseLocked_ = true;
        glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
        firstMouse_ = true;
        return "JOC NOU";
    }
    if (action == "start_creator_world") {
        bw::WorldConfig cfg = menu_.creatorConfig();
        initWorld(cfg, "sandbox", menu_.selectedCharacter);
        game_->sessionMode = "creator";
        menu_.inGame = true;
        menuOpen_ = false;
        mouseLocked_ = true;
        glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
        firstMouse_ = true;
        return "MOD CREATOR";
    }
    if (action == "start_structure_editor") {
        enterEditor();
        return "";
    }
    if (action == "editor_cycle") {
        const auto& list = blueprints_.list();
        if (!list.empty()) {
            blueprintIndex_ = (blueprintIndex_ + 1) % (int)list.size();
            menu_.editorBlueprint = list[blueprintIndex_].name;
        }
        return "";
    }
    if (action == "editor_load") {
        loadEditorBlueprint();
        return "";
    }
    if (action == "editor_undo") {
        editor_.undo();
        menu_.editorBlocks = (int)editor_.blocks.size();
        return "UNDO";
    }
    if (action == "editor_redo") {
        editor_.redo();
        menu_.editorBlocks = (int)editor_.blocks.size();
        return "REDO";
    }
    if (action == "editor_grid") {
        cycleEditorGrid();
        return "";
    }
    if (action == "editor_clear") {
        editor_.clear();
        menu_.editorBlocks = 0;
        return "GOLIT";
    }
    if (action == "characters") {
        menu_.show("characters");
        return "";
    }
    if (action == "confirm_character") {
        menu_.show("main");
        return "";
    }
    if (action == "toggle_music") {
        audio_.setMusic(menu_.musicEnabled);
        return menu_.musicEnabled ? "MUZICA PORNITA" : "MUZICA OPRITA";
    }
    if (action == "login") {
        if (network_.connectAndAuth(menu_.username, menu_.password, true))
            return "AUTENTIFICARE...";
        return "COMPLETEAZA UTILIZATOR SI PAROLA";
    }
    if (action == "logout") {
        network_.disconnect();
        network_.state.loggedIn = false;
        return "DECONECTAT";
    }
    if (action == "delete_account_screen" || action == "delete_account") {
        if (action == "delete_account")
            network_.deleteAccount();
        return "";
    }
    if (action == "create_room") {
        network_.createRoom(menu_.roomName, menu_.roomCode, menu_.roomPassword,
                            menu_.roomGameMode.empty() ? "classic"
                                                       : menu_.roomGameMode);
        return "SE CREEAZA SALA...";
    }
    if (action == "join_room") {
        network_.joinRoom(menu_.roomCode, menu_.roomPassword);
        return "INTRA IN SALA...";
    }
    if (action == "leave_room") {
        network_.leaveRoom();
        return "";
    }
    if (action == "refresh_rooms") {
        network_.fetchRooms();
        return "";
    }
    if (action == "ready") {
        network_.sendReady(menu_.selectedCharacter);
        return "READY";
    }
    if (action == "start_network_game") {
        network_.startGame();
        return "SE PORNESTE MECIUL...";
    }
    if (action == "load_online") {
        network_.loadPlayerData();
        return "SE INCARCA...";
    }
    return "";
}

} // namespace

int main(int, char**) {
    App app;
    return app.run();
}
