# Problems & Potential Improvements

> Consolidated list of all known bugs (past & present), design limitations, and potential improvements across the entire system.
>
> Last updated: 2026-05-08

---

## 1. Resolved Bugs (for reference)

| # | Description | Root Cause | Fix | Date |
|---|-------------|-----------|-----|------|
| 7 | `projectToWorld` Y and Z signs inverted — ground detected as ceiling, height classification completely wrong | ARKit camera: +Y up, -Z forward; code used `+d` instead of `-d` for z_cam, missing negation on y_cam | Corrected signs: `y_cam = -d*(by-cy)/fy`, `z_cam = -d` | 2/22 |
| 8 | `hdist` computed from world origin instead of camera position — everything read as "far away" after walking a few meters | Bug 1 masked this; once signs were fixed, all obstacles appeared at P5 | Changed all `hdist` calculations to use `(pt - cameraPos)` in `computeFreeSpaceMap`, `detectStairs`, `detectSlope` | 2/22 |
| 9 | Slope false positive when facing a wall — wall foot points misidentified as a slope | Too few validation checks on regression | Added minPoints≥30, distance span≥1.0m, R²>0.5 | 2/22 |
| 10 | 64×48 analysis resolution too low — small obstacles (poles, curbs) missed | 1 pixel ≈ 4cm at 3m; a 5cm pole = 0-1 px | Upgraded to full 192×192 resolution (stride=1) | 2/23 |
| 11 | No confidence filtering — noise at edges and far distances caused false obstacles | ARKit depth has unreliable pixels at reflective surfaces, far range, depth discontinuities | Added `confidenceMap >= 1` filter (reject low confidence) | 2/23 |
| 12 | Stair/slope scan column range was fixed pixel count, not angular | At different resolutions the angular coverage changed | Made scan range scale with resolution: `cols * 10/48` | 2/23 |
| 13 | ESP32 D5/D8 motors not vibrating | Soldering / wiring issue on hardware prototype | Hardware debugging + pin scanner test identified working pins | 4/28 |

---

## 2. Open Known Issues

### Issue #14 — `maxIndex` may skip intermediate route segments

- **Where**: `ViewController.checkUserThresholds()` (Macro Navigation)
- **Problem**: When `threshold_1_radius` is large (4m), the user can be inside multiple threshold-1 circles simultaneously. The code takes `maxIndex` (furthest matching point), which can skip intermediate waypoints.
- **Impact**: Low at current r=4m. Would become a problem if radius increases or route points are densely spaced.
- **Potential fix**: Use the **closest** matching point to the user instead of the furthest, or track "last confirmed waypoint" and only advance sequentially.

---

## 3. LiDAR B2 Pipeline — Design Limitations & Potential Improvements

### 3.1 Ground Y Estimation

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **Histogram lowest-30% assumption** | `histogramGroundY()` searches for a peak in the lowest 30% of Y values. Fails when standing on an elevated platform (e.g., stage, bridge) where the lowest 30% is empty air below | Use **largest-peak** overall, or detect bimodal distributions |
| **Fixed bin size** | `binSize = 0.05m` — too coarse for precision, too fine for noisy data | Adaptive bin size based on data spread |
| **Band boundaries are fixed** | `[0, 1.5, 3.0, 5.0]m` hard-coded — may not suit all environments | Adaptive band sizing based on point density |
| **EMA can lag during elevation changes** | Walking up/down stairs: `groundYAlpha=0.1` means ~10 frames to converge to new ground level | Faster alpha when vertical velocity is detected; or event-triggered reset when stairs/slope confirmed |
| **No multi-plane support** | Assumes one ground plane per band — breaks at curbs, split-level areas | RANSAC or multi-peak histogram to detect 2+ ground planes per band |

### 3.2 Point Classification (Step C)

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **Height-only classification** | All classification is based solely on `pt.y - groundY`. No shape, texture, or context | Add spatial clustering — isolated high points may be noise, dense clusters are real obstacles |
| **Fixed thresholds** | `groundTolerance=0.08m`, `tripHazardHeight=0.15m`, etc. — one-size-fits-all | Per-band or per-distance adaptive thresholds (far points have more depth noise) |
| **No "overhead" class** | Objects above head height (tree branches, signs) are classified as `obstacleHigh` but aren't real walking hazards | Add overhead classification for `h > userHeight` — filter from blocking path |
| **Trip hazard zone is narrow** | 0.08–0.15m range is only 7cm — easy to miss in noisy data | Widen or add hysteresis specifically for trip hazard detection |

### 3.3 Stairs Detection (Step E)

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **Central ±10° only** | Stairs at an angle (approaching diagonally) may be missed | Widen scan or scan in the direction of the detected safe path |
| **No step count output** | Only returns `Bool` — doesn't tell you how many steps or total height | Return step count + total elevation change for richer haptic feedback |
| **Sensitive to partial occlusion** | A person standing on stairs blocks the step pattern | Multi-frame accumulation of stair evidence |
| **Can't distinguish curb from stairs** | A single step (curb) doesn't trigger (requires ≥3 steps). But a curb is still important | Add separate curb detection (1-2 step pattern with different threshold) |

### 3.4 Slope Detection (Step F)

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **Linear regression only** | Assumes slope is a straight line — curved ramps or terrain undulation not handled | Piecewise or polynomial regression |
| **No slope magnitude output** | Only returns `Bool` (up/down) — doesn't say how steep | Return slope angle in degrees for proportional haptic feedback |
| **Central ±5° is narrow** | Slope at an angle to walking direction may be missed | Scan in walking direction (from GPS heading or safe path angle) |

### 3.5 Free Space Map (Step G)

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **Only counts blocking obstacles** | `tripHazard` and `dropMild` are NOT considered blocking — user can walk into a trip hazard zone without warning in P4/P5 | Add a secondary "caution distance" map that includes trip hazards |
| **Per-column minimum only** | No distinction between a wall (entire column blocked) and a floating obstacle (partially blocked) | Track vertical extent of blockage per column |
| **No temporal persistence** | Each frame computes fresh — a briefly occluded obstacle disappears instantly | Keep a short-term occupancy memory (last N frames) |

### 3.6 Safe Path Finding (Step H)

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **Fixed `safeWidthConstant=0.8m`** | Doesn't account for user carrying bags, using wheelchair, etc. | User-configurable width profile |
| **Fixed `minSafeDistance=2.0m`** | Too conservative in tight spaces (narrow hallways), too aggressive in open areas | Adaptive: shorter in hallways (detected by narrow total FOV clearance), longer outdoors |
| **No path trajectory planning** | Picks the best corridor at this instant — doesn't consider that the user is already walking in a direction | Factor in user heading/momentum: prefer corridors aligned with current walking direction |
| **Best-effort angle when blocked** | When `noSafePathFound`, returns widest gap angle even if that gap is too narrow — user may try to squeeze through | Provide clearer "stop and reassess" vs "squeeze through narrow gap" distinction |
| **Forward cone ±15° is fixed** | P0 gating uses hardcoded ±15° — may not match actual phone-to-walking-direction offset | Use compass/GPS heading to determine actual forward direction |

### 3.7 Temporal Smoothing (Step I)

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **Hysteresis counts are global** | `boolHysteresisOn=3` / `boolHysteresisOff=5` for all flags — stairs may need different timing than safe path | Per-flag tunable hysteresis thresholds |
| **EMA angle can overshoot** | When safe path rapidly switches sides (obstacle moves), EMA lags behind | Use a dead-zone: if raw angle flips sign, reset EMA instead of smoothing through zero |
| **Asymmetric EMA for distance only covers one variable** | `nearestObstacleDistance` has fast-approach/slow-release, but `nearestForwardDistance` (for P0) does not | Apply asymmetric EMA to `forwardNearDist` too — critical for P0 responsiveness |

---

## 4. Macro Navigation — Limitations & Improvements

| Limitation | Detail | Potential Improvement |
|-----------|--------|----------------------|
| **GPS accuracy ~3-5m** | In urban canyons, GPS can drift 10m+ — causes false off-route triggers | Fuse with ARKit VIO position (already available from LiDAR session) for better local accuracy |
| **1-second reroute delay** | Off-route → wait 1s → reroute. In fast-moving scenarios this may be too slow; in GPS-noisy areas too fast | Adaptive delay: scale with confidence (more GPS samples confirming off-route → faster reroute) |
| **No indoor support** | Google Maps Directions API is outdoor-only; no indoor waypoint navigation | Add indoor mode using ARKit anchors or BLE beacons for indoor positioning |
| **Heading from compass only** | Phone compass is noisy (±5-10°) and affected by magnetic interference | Fuse compass with ARKit camera heading for more stable direction |
| **2-byte BLE protocol** | Current `[direction, magnitude]` can't send L/F/R motor intensities separately | Upgrade to 4-byte `[cmd, L, F, R]` — **already planned** |

---

## 5. System-Level — Missing Components

| Component | Status | Description |
|-----------|--------|-------------|
| **Arbitration Layer** | 🔲 Not started | Merge Macro (Google Maps direction) + Micro (LiDAR P0-P5) into unified haptic command. E.g., Google says "turn right" but LiDAR sees wall on right → override with LiDAR |
| **ESP32 3-Motor PWM** | 🔲 Not started | Receive `[cmd, L, F, R]` via BLE → drive 3 motors with independent PWM intensity |
| **Dynamic obstacle handling** | 🔲 Not started | People walking toward user — current system treats each frame independently, no velocity estimation |
| **User speed adaptation** | 🔲 Not started | Walk faster → need longer detection range and earlier warnings; standing still → reduce sensitivity |
| **Battery/thermal management** | 🔲 Not started | 192×192 at 5Hz is heavy on the GPU — no adaptive throttling when phone gets hot |
| **Audio feedback channel** | 🔲 Not started | Haptics alone may not convey stairs/slope/drop type — consider bone-conduction audio supplement |
| **End-to-end real-device testing** | 🔲 Not started | No systematic outdoor test with all components connected |

---

## 6. Performance Concerns

| Concern | Current State | Risk | Mitigation |
|---------|--------------|------|------------|
| **Phone overheating** | 192×192 × 5Hz = 184K points/sec + full B2 pipeline | Medium — iPhone 12 Pro sustained ARKit can cause throttling after 10-15 min | Add adaptive resolution: drop to 96×96 when thermal state is `.serious` |
| **Memory spikes** | `worldPoints` = 192×192 × 12 bytes = ~430KB per frame, allocated fresh each cycle | Low — short-lived, but GC pressure | Pre-allocate and reuse buffers instead of creating new arrays each frame |
| **Main thread blocking** | `updateDepthGridUI` updates 256 UILabels at 5Hz | Low-Medium — 256 label updates can cause micro-stutters | Use a single `CALayer`/`UIImage` render instead of 256 individual labels |
| **BLE throughput** | 2 bytes @ 5Hz = trivial | None currently | 4-byte upgrade still trivial; but if adding obstacle list data, may need MTU negotiation |

---

## 7. Priority Ranking

### High Priority (blocks real-world usability)
1. **Arbitration Layer** — without it, macro and micro navigation can conflict
2. **ESP32 4-byte protocol + 3-motor PWM** — hardware prototype exists, needs firmware
3. **End-to-end testing** — all components exist individually but never tested together

### Medium Priority (improves accuracy/robustness)
4. Ground Y estimation improvements (multi-plane, faster convergence on stairs)
5. Temporal persistence for free space (obstacle memory across frames)
6. Asymmetric EMA for `forwardNearDist` (P0 responsiveness)
7. Trip hazard inclusion in caution map
8. Overhead obstacle filtering

### Low Priority (nice-to-have / future)
9. Adaptive `minSafeDistance` and `safeWidthConstant`
10. ARKit VIO + GPS fusion for better positioning
11. Dynamic obstacle velocity estimation
12. Adaptive thermal throttling
13. Audio feedback channel
14. Indoor navigation support
