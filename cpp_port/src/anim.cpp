#include "anim.h"

#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtx/quaternion.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace anim {

namespace {

constexpr float PI = 3.14159265358979323846f;

// the character's own frame (Blender metarig export):
// faces -X, up +Y, left +Z
const glm::vec3 FWD(-1.0f, 0.0f, 0.0f);
const glm::vec3 UP(0.0f, 1.0f, 0.0f);
const glm::vec3 LEFT(0.0f, 0.0f, 1.0f);

float clampf(float v, float lo, float hi) {
    return std::max(lo, std::min(hi, v));
}

float smoothstep(float a, float b, float x) {
    const float t = clampf((x - a) / std::max(1e-5f, b - a), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

// damped spring used for the landing crouch
float springDecay(float t, float freq, float damp) {
    return std::exp(-damp * t) * std::cos(freq * t);
}

} // namespace

const char* stateName(State s) {
    switch (s) {
    case GROUND:
        return "ground";
    case AIR:
        return "air";
    case SWIM:
        return "swim";
    case DEAD:
        return "dead";
    }
    return "?";
}

Rig Rig::map(const model::Scene& sc) {
    Rig r;
    auto N = [&](const char* name) { return model::findNode(sc, name); };
    r.spine = N("spine");
    r.spine1 = N("spine.001");
    r.spine2 = N("spine.002");
    r.spine3 = N("spine.003");
    r.spine4 = N("spine.004");
    r.spine5 = N("spine.005");
    r.head = N("spine.006");
    r.breastL = N("breast.L");
    r.breastR = N("breast.R");
    r.shoulderL = N("shoulder.L");
    r.shoulderR = N("shoulder.R");
    r.armL = N("upper_arm.L");
    r.armR = N("upper_arm.R");
    r.foreL = N("forearm.L");
    r.foreR = N("forearm.R");
    r.handL = N("hand.L");
    r.handR = N("hand.R");
    r.thighL = N("thigh.L");
    r.thighR = N("thigh.R");
    r.shinL = N("shin.L");
    r.shinR = N("shin.R");
    r.footL = N("foot.L");
    r.footR = N("foot.R");
    r.heelL = N("heel.02.L");
    r.heelR = N("heel.02.R");
    r.toeL = N("toe.L");
    r.toeR = N("toe.R");
    r.pelvisL = N("pelvis.L");
    r.pelvisR = N("pelvis.R");
    r.valid = r.spine >= 0 && r.thighL >= 0 && r.thighR >= 0 &&
              r.shinL >= 0 && r.shinR >= 0 && r.armL >= 0 && r.armR >= 0;
    return r;
}

void Driver::reset(float yaw) {
    state = GROUND;
    stateTime = airTime = landTime = swimPhase = deathTime = idleTime = 0.0f;
    landStrength = 0.0f;
    speedSmooth = leanFwd = leanSide = yawRate = crouch = 0.0f;
    airBlend = swimBlend = deathBlend = aimBlend = armedBlend = 0.0f;
    walkPhase = 0.0f;
    prevYaw = yaw;
    lastVy_ = 0.0f;
    seed = std::fmod(std::abs(yaw) * 12.9898f, 6.2831853f);
}

void Driver::update(const Input& in) {
    const float dt = clampf(in.dt, 0.0f, 0.1f);
    if (dt <= 0.0f)
        return;

    const float speed01 =
        clampf(in.speed / std::max(0.5f, in.maxSpeed), 0.0f, 1.6f);
    speedSmooth += (speed01 - speedSmooth) * std::min(1.0f, dt * 8.0f);
    idleTime += dt;

    float dyaw = in.yaw - prevYaw;
    while (dyaw > PI)
        dyaw -= 2.0f * PI;
    while (dyaw < -PI)
        dyaw += 2.0f * PI;
    yawRate += (dyaw / dt - yawRate) * std::min(1.0f, dt * 6.0f);
    prevYaw = in.yaw;

    if (in.dead) {
        if (state != DEAD) {
            state = DEAD;
            stateTime = 0.0f;
        }
    } else if (in.inWater) {
        if (state != SWIM) {
            state = SWIM;
            stateTime = 0.0f;
            swimPhase = 0.0f;
        }
    } else if (!in.onFloor) {
        if (state != AIR) {
            state = AIR;
            airTime = 0.0f;
        }
    } else {
        if (state == AIR) {
            // landing impact from the vertical speed before the hit;
            // small steps down a slope should not crouch
            if (airTime > 0.12f && std::abs(lastVy_) > 2.5f) {
                landStrength =
                    clampf(std::abs(lastVy_) / 6.5f, 0.25f, 1.0f);
                landTime = 0.55f;
            }
        }
        if (state != GROUND) {
            state = GROUND;
            stateTime = 0.0f;
        }
    }
    stateTime += dt;
    if (state == AIR)
        airTime += dt;
    if (state == SWIM)
        swimPhase += dt * (1.7f + 3.4f * speedSmooth);
    if (state == DEAD)
        deathTime += dt;
    if (state == GROUND && speedSmooth > 0.03f)
        walkPhase += dt * (3.5f + 7.0f * std::min(1.0f, speedSmooth));
    landTime = std::max(0.0f, landTime - dt);
    lastVy_ = in.vy;

    auto approach = [&](float& v, float target, float rate) {
        v += (target - v) * std::min(1.0f, dt * rate);
    };
    approach(airBlend, state == AIR ? 1.0f : 0.0f, 7.0f);
    approach(swimBlend, state == SWIM ? 1.0f : 0.0f, 5.0f);
    approach(deathBlend, state == DEAD ? 1.0f : 0.0f, 3.0f);
    approach(aimBlend, in.aiming ? 1.0f : 0.0f, 6.0f);
    approach(armedBlend, in.armed ? 1.0f : 0.0f, 6.0f);

    const float leanTarget =
        clampf(0.10f * speedSmooth + 0.05f * (in.running ? 1.0f : 0.0f) *
                                         speedSmooth,
               -0.25f, 0.30f);
    approach(leanFwd, leanTarget, 5.0f);
    approach(leanSide, clampf(yawRate * 0.14f, -0.30f, 0.30f), 5.0f);

    // landing crouch: fast dip that bounces back
    const float landT =
        landTime > 0.0f ? 1.0f - landTime / 0.55f : 1.0f;
    crouch = landTime > 0.0f
                 ? landStrength * springDecay(landT, 11.0f, 5.5f)
                 : 0.0f;
    crouch = clampf(crouch, -0.15f, 1.0f);
}

void Driver::overlay(const model::Scene& sc, const Rig& rig,
                     std::vector<glm::mat4>& locals, const Input& in) {
    const size_t n = locals.size();
    if (n == 0 || !rig.valid)
        return;

    globals_.assign(n, glm::mat4(1.0f));
    model::computeNodeGlobals(sc, locals, globals_);

    // rotate a node (and its whole subtree) around its own joint in
    // model space
    auto rotateAt = [&](int node, const glm::quat& q) {
        if (node < 0 || node >= (int)n)
            return;
        const glm::vec3 p(globals_[node][3]);
        const glm::mat4 R =
            glm::translate(glm::mat4(1.0f), p) * glm::mat4_cast(q) *
            glm::translate(glm::mat4(1.0f), -p);
        stack_.clear();
        stack_.push_back(node);
        while (!stack_.empty()) {
            const int d = stack_.back();
            stack_.pop_back();
            globals_[d] = R * globals_[d];
            for (int c : sc.nodeChildren[d])
                stack_.push_back(c);
        }
    };
    auto rot = [&](int node, const glm::vec3& axis, float angle) {
        if (std::abs(angle) < 1e-5f)
            return;
        rotateAt(node, glm::angleAxis(angle, glm::normalize(axis)));
    };
    auto translateSubtree = [&](int node, const glm::vec3& offset) {
        if (node < 0 || node >= (int)n ||
            glm::length2(offset) < 1e-10f)
            return;
        const glm::mat4 T = glm::translate(glm::mat4(1.0f), offset);
        stack_.clear();
        stack_.push_back(node);
        while (!stack_.empty()) {
            const int d = stack_.back();
            stack_.pop_back();
            globals_[d] = T * globals_[d];
            for (int c : sc.nodeChildren[d])
                stack_.push_back(c);
        }
    };
    // point a bone's Y axis (its length axis) along `dir`, weight 0..1
    auto pointBone = [&](int node, const glm::vec3& dir, float w) {
        if (node < 0 || node >= (int)n || w <= 1e-4f)
            return;
        const glm::vec3 cur(globals_[node][1]);
        if (glm::length2(cur) < 1e-8f)
            return;
        const glm::vec3 a = glm::normalize(cur);
        const glm::vec3 b = glm::normalize(dir);
        glm::quat q = glm::rotation(a, b);
        if (w < 1.0f)
            q = glm::slerp(glm::quat(1, 0, 0, 0), q, w);
        rotateAt(node, q);
        if (std::getenv("BW_ANIM_DEBUG")) {
            const glm::vec3 post = glm::normalize(glm::vec3(globals_[node][1]));
            std::printf("[pointBone node=%d cur=(%.2f,%.2f,%.2f) "
                        "tgt=(%.2f,%.2f,%.2f) post=(%.2f,%.2f,%.2f) w=%.2f]\n",
                        node, a.x, a.y, a.z, b.x, b.y, b.z, post.x, post.y,
                        post.z, w);
        }
    };

    // authored shorthands (see the frame note above)
    auto pitchBody = [&](int node, float a) { rot(node, LEFT, a); };
    auto rollBody = [&](int node, float a) { rot(node, FWD, a); };
    auto twistBody = [&](int node, float a) { rot(node, UP, a); };
    auto swingLimb = [&](int node, float a) { rot(node, LEFT, -a); };
    auto bendKnee = [&](int node, float a) { rot(node, LEFT, a); };
    auto bendElbow = [&](int node, float a) { rot(node, LEFT, -a); };

    const float speed01 = clampf(speedSmooth, 0.0f, 1.0f);
    const float t = idleTime;
    const float dead = deathBlend;
    const float swim = swimBlend;
    const float air = airBlend;
    const float land = crouch;

    // ---------------------------------------------------------
    // ground: lean, breathing, idle life
    // ---------------------------------------------------------
    const float ground = (1.0f - dead) * (1.0f - swim) * (1.0f - air * 0.6f);
    if (ground > 0.01f) {
        // forward lean with speed
        pitchBody(rig.spine, leanFwd * 0.55f * ground);
        pitchBody(rig.spine2, leanFwd * 0.30f * ground);
        pitchBody(rig.spine4, leanFwd * 0.25f * ground);
        // bank into turns
        rollBody(rig.spine, leanSide * 0.5f * ground);
        rollBody(rig.spine3, leanSide * 0.3f * ground);
        // idle breathing / weight shift
        const float idle = 1.0f - speed01;
        const float breath = std::sin(t * 1.9f + seed);
        pitchBody(rig.spine3, breath * 0.022f * idle * ground);
        rollBody(rig.spine1, std::sin(t * 0.9f + seed * 1.7f) * 0.018f *
                                idle * ground);
        // subtle idle head turns
        twistBody(rig.head,
                  std::sin(t * 0.37f + seed) * 0.10f * idle * ground);
    }
    // no baked clips: synthesize the walk/run cycle
    if (in.proceduralBase && ground > 0.01f && state == GROUND) {
        const float s = std::min(1.0f, speedSmooth);
        const float p = walkPhase;
        swingLimb(rig.thighL, std::sin(p) * 0.65f * s * ground);
        swingLimb(rig.thighR, std::sin(p + PI) * 0.65f * s * ground);
        bendKnee(rig.shinL,
                 std::max(0.0f, -std::sin(p - 0.5f)) * 0.95f * s * ground);
        bendKnee(rig.shinR, std::max(0.0f, -std::sin(p + PI - 0.5f)) * 0.95f *
                                s * ground);
        rot(rig.footL, LEFT, -std::sin(p + 0.8f) * 0.25f * s * ground);
        rot(rig.footR, LEFT, -std::sin(p + PI + 0.8f) * 0.25f * s * ground);
        swingLimb(rig.armL, std::sin(p + PI) * 0.5f * s * ground);
        swingLimb(rig.armR, std::sin(p) * 0.5f * s * ground);
        bendElbow(rig.foreL,
                  (0.2f + 0.15f * std::max(0.0f, std::sin(p + PI))) * s *
                      ground);
        bendElbow(rig.foreR,
                  (0.2f + 0.15f * std::max(0.0f, std::sin(p))) * s * ground);
        pitchBody(rig.spine3, std::sin(p * 2.0f) * 0.05f * s * ground);
        rollBody(rig.spine4, std::sin(p) * 0.05f * s * ground);
        rollBody(rig.spine5, std::sin(p) * 0.04f * s * ground);
    }

    // ---------------------------------------------------------
    // head look: follow the camera pitch
    // ---------------------------------------------------------
    {
        const float look = clampf(in.pitch, -1.3f, 1.3f);
        const float w = (1.0f - dead) * (1.0f - swim * 0.5f);
        pitchBody(rig.head, -look * 0.45f * w);
        pitchBody(rig.spine4, -look * 0.10f * w);
    }

    // ---------------------------------------------------------
    // air: takeoff, fall and landing
    // ---------------------------------------------------------
    if (air > 0.01f) {
        const float up = clampf(in.vy / 4.5f, -1.0f, 1.0f);
        const float rise = clampf(up, 0.0f, 1.0f);
        const float fall = clampf(-up, 0.0f, 1.0f);
        // short hops keep the locomotion pose; only real air time poses
        const float a = air * clampf(airTime / 0.20f, 0.0f, 1.0f);
        // takeoff: body extends, arms swing up, legs tuck
        pitchBody(rig.spine, (-0.12f * rise + 0.10f * fall) * a);
        swingLimb(rig.armL, (0.45f * rise + 0.20f * fall) * a);
        swingLimb(rig.armR, (0.45f * rise + 0.20f * fall) * a);
        rot(rig.armL, FWD, 0.40f * a);
        rot(rig.armR, FWD, -0.40f * a);
        bendElbow(rig.foreL, 0.30f * a);
        bendElbow(rig.foreR, 0.30f * a);
        // legs: tuck on the way up, trail on the way down
        swingLimb(rig.thighL, (0.35f * rise - 0.22f * fall) * a);
        swingLimb(rig.thighR, (0.24f * rise - 0.38f * fall) * a);
        bendKnee(rig.shinL, (0.60f * rise + 0.30f * fall) * a);
        bendKnee(rig.shinR, (0.45f * rise + 0.38f * fall) * a);
    }

    // landing crouch (feet planted, knees absorb)
    if (land > 0.005f) {
        translateSubtree(rig.spine, glm::vec3(0.0f, -0.10f * land, 0.0f));
        pitchBody(rig.spine, 0.28f * land);
        swingLimb(rig.thighL, 0.55f * land);
        swingLimb(rig.thighR, 0.55f * land);
        bendKnee(rig.shinL, 0.95f * land);
        bendKnee(rig.shinR, 0.95f * land);
        swingLimb(rig.armL, -0.25f * land);
        swingLimb(rig.armR, -0.25f * land);
        rot(rig.armL, FWD, 0.30f * land);
        rot(rig.armR, FWD, -0.30f * land);
        bendElbow(rig.foreL, 0.55f * land);
        bendElbow(rig.foreR, 0.55f * land);
    }

    // ---------------------------------------------------------
    // swim: prone crawl / treading water
    // ---------------------------------------------------------
    if (swim > 0.01f) {
        const float cruise = clampf(speedSmooth * 2.0f, 0.0f, 1.0f);
        const float bodyPitch = (0.45f + 0.70f * cruise) * swim;
        pitchBody(rig.spine, bodyPitch);
        translateSubtree(rig.spine,
                         glm::vec3(0.0f,
                                   0.05f * swim +
                                       std::sin(swimPhase * 2.0f) * 0.025f *
                                           swim,
                                   0.0f));
        // prone body axis (towards the head) and its down direction
        const glm::vec3 axis =
            glm::normalize(UP * std::cos(bodyPitch) + FWD * std::sin(bodyPitch));
        const glm::vec3 down =
            glm::normalize(glm::cross(axis, LEFT)) * -1.0f;
        // arms: alternating crawl strokes
        auto stroke = [&](int arm, int fore, float phase, float side) {
            const glm::vec3 dir = glm::normalize(
                axis * std::cos(phase) + down * std::sin(phase) * 0.9f +
                LEFT * side * 0.25f);
            pointBone(arm, dir, swim);
            const float bend = 0.25f + 0.55f * std::max(0.0f, -std::sin(phase));
            bendElbow(fore, bend * swim);
        };
        stroke(rig.armL, rig.foreL, swimPhase, 1.0f);
        stroke(rig.armR, rig.foreR, swimPhase + PI, -1.0f);
        // legs: flutter kick
        auto kick = [&](int thigh, int shin, float phase) {
            const glm::vec3 dir = glm::normalize(
                -axis * 0.95f + down * std::sin(phase) * 0.35f);
            pointBone(thigh, dir, swim * 0.8f);
            bendKnee(shin, (0.25f + 0.30f * std::max(0.0f, std::sin(phase))) *
                               swim);
        };
        kick(rig.thighL, rig.shinL, swimPhase * 2.0f);
        kick(rig.thighR, rig.shinR, swimPhase * 2.0f + PI);
        // head up to breathe
        pointBone(rig.head, glm::normalize(axis * 0.75f + UP * 0.75f),
                  swim * 0.7f);
    }

    // ---------------------------------------------------------
    // aim (crossbow) and ready stance (sword)
    // ---------------------------------------------------------
    const float aim = aimBlend * (1.0f - dead) * (1.0f - swim) * (1.0f - air);
    if (aim > 0.01f) {
        const glm::vec3 aimDir =
            glm::normalize(FWD * std::cos(in.pitch) + UP * std::sin(in.pitch));
        // weapon arm (right): nearly straight towards the target
        pointBone(rig.armR, aimDir, aim * 0.90f);
        const glm::vec3 foreDir =
            glm::normalize(aimDir * 0.94f + UP * 0.16f);
        pointBone(rig.foreR, foreDir, aim * 0.85f);
        pointBone(rig.handR, aimDir, aim * 0.5f);
        // support arm (left) holds the foregrip under the weapon
        const glm::vec3 supDir = glm::normalize(
            aimDir * 0.72f + LEFT * 0.62f + UP * -0.18f);
        pointBone(rig.armL, supDir, aim * 0.85f);
        const glm::vec3 supFore = glm::normalize(
            aimDir * 0.55f + LEFT * 0.80f + UP * 0.10f);
        pointBone(rig.foreL, supFore, aim * 0.8f);
        pointBone(rig.handL, aimDir, aim * 0.4f);
        // chest opens towards the shot, hips stay square
        twistBody(rig.spine3, 0.16f * aim);
        twistBody(rig.spine5, 0.10f * aim);
        pitchBody(rig.spine2, -0.05f * aim);
        rot(rig.shoulderR, UP, -0.10f * aim);
    }
    const float ready =
        armedBlend * (1.0f - dead) * (1.0f - swim) * (1.0f - air) *
        (1.0f - aimBlend);
    if (ready > 0.01f) {
        // sword ready: weapon arm low, guard hand up front
        const glm::vec3 guard =
            glm::normalize(FWD * 0.80f + LEFT * 0.40f + UP * 0.30f);
        pointBone(rig.armR,
                  glm::normalize(FWD * 0.75f + LEFT * -0.45f + UP * -0.35f),
                  ready * 0.6f);
        pointBone(rig.foreR, glm::normalize(guard + UP * 0.35f),
                  ready * 0.55f);
        pointBone(rig.armL, guard, ready * 0.6f);
        pointBone(rig.foreL, glm::normalize(guard + UP * 0.15f),
                  ready * 0.55f);
        twistBody(rig.spine3, -0.10f * ready);
    }

    // ---------------------------------------------------------
    // attacks
    // ---------------------------------------------------------
    if (in.attack >= 0.0f && in.attack <= 1.0f && dead < 0.5f) {
        const float p = in.attack;
        if (in.attackKind == 1) {
            // sword: windup -> strike -> recover
            const float wind = smoothstep(0.0f, 0.32f, p);
            const float strike = smoothstep(0.30f, 0.52f, p);
            const float recover = smoothstep(0.55f, 1.0f, p);
            const float w = wind * (1.0f - recover);
            const float s = strike * (1.0f - recover);
            twistBody(rig.spine3, 0.42f * w - 0.34f * s);
            twistBody(rig.spine2, 0.18f * w - 0.16f * s);
            pitchBody(rig.spine, -0.10f * w + 0.22f * s);
            // right arm sweeps from high/back to across the body
            const glm::vec3 high =
                glm::normalize(FWD * -0.35f + UP * 0.85f + LEFT * -0.35f);
            const glm::vec3 low =
                glm::normalize(FWD * 0.75f + UP * -0.55f + LEFT * 0.45f);
            const glm::vec3 armDir = glm::mix(high, low, s);
            pointBone(rig.armR, armDir, w + s);
            pointBone(rig.foreR,
                      glm::normalize(armDir + FWD * 0.55f * w),
                      (w + s) * 0.55f);
            pointBone(rig.handR, armDir, (w + s) * 0.4f);
            pointBone(rig.armL,
                      glm::normalize(FWD * 0.5f + LEFT * 0.5f + UP * 0.1f),
                      0.4f * (w + s));
            bendElbow(rig.foreL, 0.7f * (w + s));
        } else {
            // crossbow: snap to aim, kick back, settle
            const float raise = smoothstep(0.0f, 0.12f, p);
            const float kick = std::exp(-std::max(0.0f, p - 0.12f) * 9.0f) *
                               smoothstep(0.05f, 0.15f, p);
            const float rec = 1.0f - smoothstep(0.35f, 1.0f, p);
            const float w = raise * rec;
            const glm::vec3 aimDir = glm::normalize(
                FWD * std::cos(in.pitch) + UP * std::sin(in.pitch));
            const glm::vec3 dir =
                glm::normalize(aimDir + UP * 0.18f * kick);
            pointBone(rig.armR, dir, w * 0.9f);
            pointBone(rig.foreR,
                      glm::normalize(dir * 0.94f + UP * 0.16f), w * 0.85f);
            pointBone(rig.handR, dir, w * 0.5f);
            pointBone(rig.armL,
                      glm::normalize(aimDir * 0.72f + LEFT * 0.62f +
                                     UP * -0.18f),
                      w * 0.85f);
            pointBone(rig.foreL,
                      glm::normalize(aimDir * 0.55f + LEFT * 0.80f +
                                     UP * 0.10f),
                      w * 0.8f);
            twistBody(rig.spine3, (0.16f - 0.30f * kick) * raise);
            pitchBody(rig.spine2, -0.14f * kick);
        }
    }

    // ---------------------------------------------------------
    // hit flinch
    // ---------------------------------------------------------
    if (in.hit >= 0.0f && in.hit <= 1.0f && dead < 0.5f) {
        const float h = 1.0f - in.hit;
        const float f = h * h;
        pitchBody(rig.spine, -0.22f * f);
        pitchBody(rig.spine3, -0.16f * f);
        rollBody(rig.spine1, 0.10f * f);
        twistBody(rig.head, 0.18f * f);
        rot(rig.armL, FWD, 0.45f * f);
        rot(rig.armR, FWD, -0.35f * f);
        bendElbow(rig.foreL, 0.75f * f);
        bendElbow(rig.foreR, 0.55f * f);
        bendKnee(rig.shinL, 0.25f * f);
        bendKnee(rig.shinR, 0.25f * f);
    }

    // ---------------------------------------------------------
    // death: collapse face down
    // ---------------------------------------------------------
    if (dead > 0.01f) {
        const float fall = smoothstep(0.0f, 0.65f, deathTime);
        const float settle = smoothstep(0.6f, 1.4f, deathTime);
        const float roll = 0.35f * fall;
        pitchBody(rig.spine, (1.42f * fall - 0.06f * settle) * dead);
        rollBody(rig.spine, roll * dead);
        translateSubtree(
            rig.spine,
            glm::vec3(0.0f, (-0.30f * fall - 0.04f * settle) * dead, 0.0f));
        // legs fold under, arms sprawl
        bendKnee(rig.shinL, (1.1f * fall + 0.15f * settle) * dead);
        bendKnee(rig.shinR, (0.9f * fall + 0.15f * settle) * dead);
        swingLimb(rig.thighL, -0.25f * fall * dead);
        swingLimb(rig.thighR, -0.15f * fall * dead);
        pointBone(rig.armL,
                  glm::normalize(FWD * 0.55f + LEFT * 0.75f + UP * -0.35f),
                  fall * dead * 0.85f);
        pointBone(rig.armR,
                  glm::normalize(FWD * 0.35f + LEFT * -0.85f + UP * -0.35f),
                  fall * dead * 0.85f);
        bendElbow(rig.foreL, 0.35f * fall * dead);
        bendElbow(rig.foreR, 0.30f * fall * dead);
        pointBone(rig.head, glm::normalize(FWD * 0.6f + UP * 0.8f),
                  fall * dead * 0.4f);
    }

    // write the modified globals back into local transforms
    for (size_t i = 0; i < n; ++i) {
        const int parent = sc.nodeParent[i];
        if (parent >= 0 && parent < (int)n)
            locals[i] = glm::inverse(globals_[parent]) * globals_[i];
        else
            locals[i] = globals_[i];
    }
}

namespace {

// skinned meshes render in their own vertex space (the inverse bind
// matrices cancel the node transforms), so the scene bbox is wrong
// for them - use the skinned geometry bounds instead
void skinBounds(const model::Scene& sc, glm::vec3& bmin, glm::vec3& bmax) {
    bmin = glm::vec3(1e30f);
    bmax = glm::vec3(-1e30f);
    for (const auto& g : sc.geoms) {
        if (!g.skinned)
            continue;
        bmin = glm::min(bmin, g.bmin);
        bmax = glm::max(bmax, g.bmax);
    }
    if (bmin.x > bmax.x) {
        bmin = sc.bmin;
        bmax = sc.bmax;
    }
}

} // namespace

glm::mat4 characterMatrix(const model::Scene& sc, const glm::dvec3& pos,
                          double yaw) {
    glm::vec3 bmin, bmax;
    skinBounds(sc, bmin, bmax);
    const glm::vec3 centre = (bmin + bmax) * 0.5f;
    const float scale = characterScale(sc);
    glm::mat4 m = glm::translate(glm::mat4(1.0f), glm::vec3(pos));
    // the Blender export faces the mesh along -X while the game yaw
    // rotates with the opposite handedness: compensate both
    m = glm::rotate(m, (float)(-yaw - PI * 0.5),
                    glm::vec3(0.0f, 1.0f, 0.0f));
    m = glm::scale(m, glm::vec3(scale));
    m = m * glm::translate(
                glm::mat4(1.0f),
                glm::vec3(-centre.x, -bmin.y, -centre.z));
    return m;
}

float characterScale(const model::Scene& sc) {
    glm::vec3 bmin, bmax;
    skinBounds(sc, bmin, bmax);
    const float height = bmax.y - bmin.y;
    if (height > 1e-3f)
        return 1.8f / height;
    const float diag = glm::length(bmax - bmin);
    return diag > 1e-3f ? 1.8f / diag : 1.0f;
}

} // namespace anim
