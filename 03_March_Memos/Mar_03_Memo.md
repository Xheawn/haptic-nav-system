# Mar 3, 2026 — Daily Memo

## Today's Accomplishments

### 1. LiDARManager.start() Line-by-Line Deep Dive
Performed a complete line-by-line analysis of the `start()` method in `LiDARManager.swift`, covering:

- **`ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)`** — Static method that checks whether the device has LiDAR hardware (iPhone 12 Pro+ / iPad Pro 2020+)
- **`ARWorldTrackingConfiguration()`** — ARKit's 6DOF world tracking configuration class, fusing LiDAR + IMU + visual-inertial odometry. Supports pose tracking, plane detection, scene reconstruction, and scene depth
- **`config.frameSemantics = .sceneDepth`** — Enables per-frame LiDAR depth output. Once set, `ARFrame.sceneDepth` and `ARFrame.smoothedSceneDepth` are populated (each containing `depthMap` Float32 256×192 + `confidenceMap` UInt8 256×192)
- **`session.delegate = self`** — Registers `ARSessionDelegate`, causing ARKit to call `session(_:didUpdate:)` at ~60FPS
- **`session.run(config)`** — Non-blocking call that actually starts the LiDAR sensor, camera, and IMU. ARKit then runs continuously on a background thread

### Complete Call Chain

```
viewDidLoad()                          ← Called once by iOS
  └── LiDARManager.shared.start()      ← Starts ARSession
        └── session.run(config)        ← Activates sensors
              └── ARKit auto-callback at 60FPS:
                    session(_:didUpdate: frame)
                      ├── buildGrid()           → onGridUpdate → updateDepthGridUI
                      └── analyzeHazards()      → onHazardUpdate → handleHazardUpdate
                            ├── projectToWorld()
                            ├── estimateBandGroundY()
                            ├── classifyPoints()
                            ├── detectStairs()
                            ├── detectSlope()
                            ├── computeFreeSpaceMap()
                            ├── findSafePath()
                            └── applyHysteresis()
```

### 2. LiDARManager.start() Code Comments
Added inline Chinese comments to the `start()` method in `LiDARManager.swift`, documenting `ARWorldTrackingConfiguration` capabilities (6DOF pose tracking, plane detection, scene reconstruction, scene depth).

## Files Modified

| File | Action |
|------|--------|
| `Controllers/LiDARManager.swift` | Added `ARWorldTrackingConfiguration` capability comments in `start()` |
| `03_March_Memos/Mar_03_Memo_CN.md` | **Created** — Today's memo (Chinese) |
| `03_March_Memos/Mar_03_Memo.md` | **Created** — Today's memo (English) |

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
