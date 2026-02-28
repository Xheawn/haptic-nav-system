# Feb 27, 2026 — Daily Memo

## Today's Accomplishments

### 1. Apple API Complete Reference Document
Created `Project_Pipelines/Apple_APIs_Reference.md`, systematically documenting all Apple frameworks, classes, protocols, properties, and functions used in the B1/B2 pipeline:

| Framework | Key APIs | Purpose |
|-----------|---------|---------|
| **ARKit** | ARSession, ARSessionDelegate, ARWorldTrackingConfiguration, ARFrame, ARCamera, ARDepthData | LiDAR depth capture, camera pose, confidence map |
| **CoreVideo** | CVPixelBufferLock/Unlock/GetBaseAddress/GetWidth/GetHeight/GetBytesPerRow | Direct raw memory access to depth and confidence maps |
| **simd** | simd_float3, simd_float4, simd_float3x3, simd_float4x4, matrix-vector multiply | 3D coordinate transforms (depth pixel → world coordinates) |
| **Foundation** | NSObject, TimeInterval, DispatchQueue.main.async | Base class, timestamps, main thread dispatch |
| **Swift Stdlib** | MemoryLayout, assumingMemoryBound, sqrtf/asin/atan/tan, Array ops | Memory operations, math, data processing |

Includes complete API call flow diagrams and per-step API dependency summary table.

### 2. ViewController Workflow Document
Created `Project_Pipelines/ViewController_Workflow.md`, a detailed walkthrough from app launch to real-time operation:

- **App launch → viewDidLoad trigger**: iOS app lifecycle, property initialization timing
- **viewDidLoad 11-step line-by-line analysis**: what each step does, which functions it calls, sync vs async
- **4 real-time data loops**:
  - **Loop A**: GPS ~1Hz → `checkUserThresholds` → `applyAdjustDirectionLogic`
  - **Loop B**: Compass ~10Hz → update `currentPhoneAngle` → `applyAdjust`
  - **Loop C**: LiDAR 5Hz → B1/B2 analysis → `handleHazardUpdate` → P0–P5 motor intensity
  - **Loop D**: BLE event-driven → scan/connect/reconnect → `sendCommand`
- **Loop A & Loop B coordination**: A provides "where to go", B provides "where the phone is facing"
- **Complete data flow diagram**: Sensor layer → iOS callback layer → ViewController processing layer → BLE output layer
- **First 3 seconds timeline**: millisecond-precise startup sequence example

### 3. Navigation Threshold Decision Logic Analysis
Detailed analysis of the `checkUserThresholds` core decision branch (L552–L611):

- **Case A (on route)**: `maxIndex` selection — picks the largest index representing the user's furthest progress along the route
- **Case B (off route)** three sub-steps:
  - B1: Immediate feedback — `isOffRoute=true`, BLE sends `[3, 0]`
  - B2: GPS outlier detection — if distance from last off-route position < 5m, treat as GPS drift, skip recalculation
  - B3: 1-second delayed reroute — prevents frequent API calls from GPS jitter

### 4. GitHub Permissions Confirmation
Confirmed the default permission model for a public repo:
- External users can only Fork/Clone/submit PRs/open Issues
- **Cannot** directly push or merge PRs — requires repo owner approval
- Only users added in Settings → Collaborators have write access

## Files Created/Modified

| File | Action |
|------|--------|
| `Project_Pipelines/Apple_APIs_Reference.md` | **Created** — B1/B2 Apple API complete reference |
| `Project_Pipelines/ViewController_Workflow.md` | **Created** — ViewController workflow walkthrough |
| `02_Feb_Memos/Feb_27_Memo_CN.md` | **Created** — Today's memo (Chinese) |
| `02_Feb_Memos/Feb_27_Memo.md` | **Created** — Today's memo (English) |

## Issues

| # | Description | Status |
|---|-------------|--------|
| 13 | ESP32 D5/D8 motors not vibrating (soldering issue) | 🔄 Pending hardware check |
| 14 | `maxIndex` strategy may skip intermediate route segments with large t1 radius | 📋 Documented |

## Next Steps
- **ESP32 motor soldering troubleshooting**
- **Real-device testing** of full-resolution analysis (performance/heat/small obstacle detection)
- **Arbitration Layer**: merge Macro (Google Maps) + Micro (LiDAR) navigation commands
- **ESP32 protocol upgrade**: 4-byte packet `[cmd, L, F, R]` + 3-motor PWM control
