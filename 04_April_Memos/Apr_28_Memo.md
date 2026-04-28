# Apr 28, 2026 — Daily Memo

## Today's Accomplishments

### 1. Updated ESP32 Motor Test File
Updated `esp32_s3_test/motor_test/motor_test.ino`, currently a XIAO ESP32-S3 full pin scanner test:
- Tests D0–D10 (all 11 GPIO pins) sequentially, each `digitalWrite(HIGH)` for 800ms
- Observe which pin drives the motor via Serial Monitor
- Used to confirm usable GPIO pins, resolving previous D5/D8 motor issues

### 2. First Working 3-Motor Prototype 🎉
Successfully built the first hardware prototype with 3 vibration motor modules:
- **Left / Front / Right** — all three motors confirmed working
- Usable GPIO pins identified through pin scanner test
- Previous Issue #13 (D5/D8 motors not vibrating) resolved through hardware debugging

### 3. Created April Memos Directory
Created `04_April_Memos/` path, continuing the organizational structure from `02_Feb_Memos/` and `03_March_Memos/`.

### 4. Project Progress Summary (Feb–Mar Review)

Complete milestone summary of all work to date:

#### Phase A: BLE Communication ✅ (Completed 2/17)
- ESP32 BLE Server (`esp32_s3_test.ino`): device name `XIAO_ESP32S3`, custom Service/Characteristic UUIDs
- iOS BLE Central (`BLEManager.swift`): scan → connect → discover services → `sendCommand()`, auto-reconnect
- 2-byte protocol: `[AdjustDirection, AngleDiffMagnitude]`, 5Hz throttle
- End-to-end verified: iPhone real-time transmission, ESP32 Serial Monitor confirmed reception

#### Phase B1: LiDAR 16×16 Depth Grid ✅ (Completed 2/18)
- `LiDARManager.swift`: ARKit `smoothedSceneDepth` → 256×192 depth map → 16×16 grid
- Per-cell Quickselect O(n) percentile-10 depth
- `forwardCropRatio=0.75` crops bottom 25% near-ground region
- Analysis at 5Hz, console logging at 2Hz
- UI: 16×16 color grid + HSB continuous gradient (red → green)

#### Phase B2: Hazard Analysis Pipeline ✅ (Completed 2/19, fixed+upgraded 2/22–2/23)
- **Step A**: Depth → world coordinates (`camera.transform` + `camera.intrinsics` unprojection)
- **Step B**: Distance-banded ground Y estimation (3-band histogram peaks + EMA + pose-aware dynamic alpha)
- **Step C**: Height classification (8 levels: invalid/ground/tripHazard/obstacleLow/Mid/High/dropMild/Severe)
- **Step E**: Stairs detection (central ±10° worldY step pattern, ≥3 consecutive steps)
- **Step F**: Slope detection (ground point linear regression + R²>0.5 + span≥1m)
- **Step G**: 192-column angular free space map
- **Step H**: Safe path finding (physical width ≥ 0.8m, prefer straight ahead)
- **Step I**: Temporal smoothing (boolean hysteresis 3on/5off, EMA angle/distance)
- **Bug fixes** (2/22): `projectToWorld` camera coordinate signs + distance reference from world origin to camera position
- **Upgrade** (2/23): 64×48 → 192×192 full resolution + confidence filtering + adaptive scan ranges

#### P0–P5 Haptic Encoding ✅ (Completed 2/19, refined 2/23)
- P0: Emergency stop (forward ±15° fully blocked AND <1m → L/F/R all 255)
- P1: Blocked with distance (best-effort gap direction, intensity 120~200)
- P2: Steering guidance (safePathAngle → L/F/R weight interpolation, intensity 80~255)
- P3: Terrain overlay (stairs F≥120, slope F≥60)
- P4: Side awareness (L/R ≤80, path ahead clear)
- P5: Clear (all 0)

#### Macro Navigation (Google Maps) ✅ (Previously completed Stage 1–8)
- Stage 1–3: Directions API → Polyline decoding → Map visualization
- Stage 4: Real-time GPS threshold detection (circular t1 + quadrilateral t2, `maxIndex` picks furthest match)
- Stage 5: Off-route handling + GPS outlier filtering + auto-reroute (1s delay)
- Stage 6–7: AngleDiff/AdjustDirection calculation → BLE 2-byte transmission
- Stage 8: Search bar dynamic destination update

#### Documentation ✅
- `Project_Pipelines/B1_B2_Pipeline.md` — LiDAR analysis pipeline + end-to-end timing
- `Project_Pipelines/GoogleMaps_Navigation_Pipeline.md` — Macro navigation 8 Stages
- `Project_Pipelines/Apple_APIs_Reference.md` — All Apple APIs used in B1/B2
- `Project_Pipelines/ViewController_Workflow.md` — App launch to real-time operation workflow

### Current Status & TODO

| Module | Status |
|--------|--------|
| BLE Communication (Phase A) | ✅ Complete |
| LiDAR Grid (B1) | ✅ Complete |
| Hazard Analysis (B2) | ✅ Complete |
| P0–P5 Haptic Encoding | ✅ Complete |
| Macro Navigation | ✅ Complete |
| 3-Motor Hardware Prototype | ✅ **Completed today** |
| ESP32 Motor Pin Confirmation | ✅ **Completed today** |
| Arbitration Layer (Macro + Micro fusion) | 🔲 To be developed |
| ESP32 Protocol Upgrade (4-byte [cmd,L,F,R]) | 🔲 To be developed |
| ESP32 3-Motor PWM Control | 🔲 To be developed |
| End-to-End Real-Device Testing | 🔲 To be conducted |

## Files Created/Modified

| File | Action |
|------|--------|
| `esp32_s3_test/motor_test/motor_test.ino` | Updated (pin scanner test) |
| `04_April_Memos/Apr_28_Memo_CN.md` | **Created** — Today's memo (Chinese) |
| `04_April_Memos/Apr_28_Memo.md` | **Created** — Today's memo (English) |

## Issues

| # | Description | Status |
|---|-------------|--------|
| 13 | ESP32 D5/D8 motors not vibrating | ✅ Resolved (hardware debugging + pin scan confirmation) |
| 14 | `maxIndex` strategy may skip intermediate route segments with large t1 radius | 📋 Documented, no impact at r=4m |

## Next Steps
- **ESP32 protocol upgrade**: Extend from 2-byte `[dir, magnitude]` to 4-byte `[cmd, L, F, R]`
- **ESP32 3-motor PWM control**: Drive 3 motors based on BLE-received L/F/R intensities
- **Arbitration Layer**: Merge Macro (Google Maps direction) + Micro (LiDAR P0–P5) navigation commands
- **End-to-end real-device testing**: iPhone LiDAR → BLE → ESP32 → 3-motor vibration feedback
