# Feb 18, 2026 — Daily Memo

## Today's Accomplishments

### 1. LiDAR 16×16 Depth Grid — Phase B1 Complete

**LiDARManager.swift — Major Rewrite**
- Switched from `frame.sceneDepth` to `frame.smoothedSceneDepth` (Apple multi-frame temporal smoothing)
- Upgraded from basic 3-column min-depth to **16×16 grid** (256 cells, each 16×12 buffer pixels)
- Each cell uses **percentile-10** depth via O(n) Quickselect algorithm (replaced full sort)
- Portrait orientation fix: buffer x→display row, buffer y→display col
- Left-right mirror fix: reversed column mapping to match real-world scene direction
- Added `forwardCropRatio = 0.75` — skips bottom 25% of FOV (near-ground), allocates all 16 rows to forward detection
- Analysis rate reduced from 10 Hz → **5 Hz** to combat phone overheating
- All thresholds configurable: `dangerCloseDistance`, `dangerDistance`, `cautionDistance`, `forwardCropRatio`, etc.

**ViewController.swift — Debug Grid UI**
- 16×16 color-coded grid overlay centered on screen
- 4-tier color coding:
  - 🔴 Red: < 0.5m (extreme danger)
  - 🟠 Orange: 0.5m – 1.0m (danger)
  - 🟡 Yellow: 1.0m – 2.0m (caution)
  - 🟢 Green: > 2.0m (clear)
- Real-time updates at 5 Hz via `LiDARManager.shared.onGridUpdate` callback
- Temporary overlay for verification — will be removed/toggled later

**Info.plist**
- Added `NSCameraUsageDescription` for ARKit LiDAR access

### 2. Documentation Updates
- Updated `PROGRESS.md`: Phase B1 marked complete with full details
- Created this memo

## Files Modified / Created
| File | Action |
|------|--------|
| `Controllers/LiDARManager.swift` | **Created** then heavily iterated |
| `Controllers/ViewController.swift` | Edited (debug grid UI + LiDAR integration) |
| `Info.plist` | Edited (camera permission) |
| `PROGRESS.md` | Updated (B1 complete) |
| `Feb_18_Memo.md` | **Created** |

## Issues Encountered & Resolved
1. **Grid orientation wrong** — Depth buffer is 256×192 in landscape-right native orientation; in portrait, x and y axes were swapped. Fixed by mapping display row→buffer x, display col→buffer y.
2. **Left-right mirrored** — After axis swap, left-right was still inverted. Fixed by reversing column index: `byStart = (cols - 1 - col) * pxPerCol`.
3. **Phone overheating + UI lag** — 16×16 grid at 10 Hz with full sort (O(n log n)) per cell was too expensive. Fixed with: (a) Quickselect O(n) for percentile-10, (b) analysis rate reduced to 5 Hz.
4. **Not enough forward data** — User needs more forward obstacle detection, less near-ground data. Fixed with `forwardCropRatio = 0.75` to crop bottom 25% of buffer and redistribute rows to forward area.

## Configurable Parameters (LiDARManager)
| Parameter | Value | Description |
|-----------|-------|-------------|
| `dangerCloseDistance` | 0.5m | Red threshold |
| `dangerDistance` | 1.0m | Orange threshold |
| `cautionDistance` | 2.0m | Yellow threshold |
| `forwardCropRatio` | 0.75 | Forward FOV focus (skip 25% near-ground) |
| `hGradientThreshold` | 1.0m | Horizontal gradient (Step 2) |
| `vGradientThreshold` | 0.5m | Vertical gradient (Step 2) |
| `analysisInterval` | 0.2s | 5 Hz analysis rate |
| `logInterval` | 0.5s | 2 Hz console print rate |

## Next Steps
- **Step 2:** Gradient analysis (horizontal ΔH + vertical ΔV) for obstacle edge and terrain discontinuity detection → `HazardResult` output
- **Step 3:** Arbitration Layer merging Google Maps direction + LiDAR hazard
- **Step 4:** ESP32 protocol extension for STOP/terrain commands + motor patterns
