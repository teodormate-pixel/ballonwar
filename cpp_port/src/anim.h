// ============================================================
// BalloonWar character animation
//
// Baked glTF clips (Idle/Walk/Run) are the locomotion base; this
// module adds a state machine and procedural overlay layers on
// top of them, in model space:
//
//   - jump takeoff / fall / landing crouch
//   - swimming (prone crawl + treading water)
//   - crossbow aiming and sword attacks (upper body)
//   - hit flinch and death collapse
//   - lean into acceleration and turns, head look, idle life
//
// All rotations are authored in the character's own frame:
// forward = -X, up = +Y, left = +Z (Blender metarig export).
// ============================================================

#pragma once

#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>

#include <vector>

#include "model.h"

namespace anim {

// bone node indices of the BalloonWar character rig
struct Rig {
    int spine = -1, spine1 = -1, spine2 = -1;
    int spine3 = -1, spine4 = -1, spine5 = -1;
    int head = -1; // spine.006
    int breastL = -1, breastR = -1;
    int shoulderL = -1, shoulderR = -1;
    int armL = -1, armR = -1;
    int foreL = -1, foreR = -1;
    int handL = -1, handR = -1;
    int thighL = -1, thighR = -1;
    int shinL = -1, shinR = -1;
    int footL = -1, footR = -1;
    int heelL = -1, heelR = -1;
    int toeL = -1, toeR = -1;
    int pelvisL = -1, pelvisR = -1;
    bool valid = false;

    static Rig map(const model::Scene& sc);
};

enum State { GROUND = 0, AIR = 1, SWIM = 2, DEAD = 3 };
const char* stateName(State s);

// per-frame description of what the character is doing
struct Input {
    float dt = 1.0f / 60.0f;
    float speed = 0.0f;    // horizontal speed (m/s)
    float maxSpeed = 7.0f; // reference top speed
    bool running = false;
    bool onFloor = true;
    bool inWater = false;
    bool dead = false;
    float vy = 0.0f;   // vertical velocity (m/s)
    float yaw = 0.0f;  // world yaw (for turn lean)
    float pitch = 0.0f; // look pitch, radians (+ = up)
    bool aiming = false;  // crossbow ready
    bool armed = false;   // sword ready
    float attack = -1.0f; // 0..1 attack progress (<0 = none)
    int attackKind = 0;   // 0 crossbow, 1 sword
    float hit = -1.0f;    // 0..1 flinch progress (<0 = none)
    // no baked locomotion clips: synthesize a walk cycle instead
    bool proceduralBase = false;
};

// skeleton pose: one TRS per node
struct Pose {
    std::vector<glm::vec3> t, s;
    std::vector<glm::quat> r;
};

// state machine + procedural layers for one character
struct Driver {
    State state = GROUND;
    float stateTime = 0.0f;
    float airTime = 0.0f;
    float landTime = 0.0f;
    float landStrength = 0.0f;
    float swimPhase = 0.0f;
    float deathTime = 0.0f;
    float idleTime = 0.0f;
    float speedSmooth = 0.0f;
    float leanFwd = 0.0f;
    float leanSide = 0.0f;
    float yawRate = 0.0f;
    float prevYaw = 0.0f;
    float crouch = 0.0f;
    float airBlend = 0.0f;
    float swimBlend = 0.0f;
    float deathBlend = 0.0f;
    float aimBlend = 0.0f;
    float armedBlend = 0.0f;
    float walkPhase = 0.0f;
    float seed = 0.0f;

    void reset(float yaw);
    void update(const Input& in);
    // applies the layers on top of the base pose; `locals` is updated
    // in place and is ready for computeNodeGlobals/skinning
    void overlay(const model::Scene& sc, const Rig& rig,
                 std::vector<glm::mat4>& locals, const Input& in);

  private:
    float lastVy_ = 0.0f;
    std::vector<glm::mat4> globals_;
    std::vector<int> stack_;
};

// model matrix for a character (feet on the ground, facing `yaw`)
glm::mat4 characterMatrix(const model::Scene& sc, const glm::dvec3& pos,
                          double yaw);
// the character's rendered height (1.8 m by convention)
float characterScale(const model::Scene& sc);

} // namespace anim
