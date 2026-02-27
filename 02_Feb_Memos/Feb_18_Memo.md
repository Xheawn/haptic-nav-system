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

### 2. Security: API Key Removal
- Discovered Google Maps API keys were hardcoded in **6 files** (ViewController.swift, Googlemaps.txt, Stage1–3 txt files, Python file)
- Created `Secrets.plist` to store API key locally, loaded at runtime via `Bundle.main.path(forResource:)`
- Added `Secrets.plist` to `.gitignore` — key never committed to git
- Replaced all hardcoded keys with `"YOUR_API_KEY_HERE"` in legacy reference files
- Rotated API key in Google Cloud Console (old key invalidated)

### 3. GitHub Repository Setup
- Created public repo: **https://github.com/Xheawn/haptic-nav-system**
- MIT License
- Added `.gitignore` (Xcode caches, xcuserdata, DS_Store, Secrets.plist, .windsurf/)
- Wrote `README.md` with architecture diagram, feature list, setup instructions, BLE protocol spec
- Initial commit + push of entire project
- Resolved merge conflict with remote LICENSE via `--allow-unrelated-histories`

### 4. B2 Literature Research
Surveyed approaches for depth grid obstacle detection for visually impaired navigation:
- **RANSAC Ground Plane Estimation** — Rodriguez et al. (2012), Lee et al. (2015): fit ground plane, anything deviating = obstacle
- **Vertical Gradient ΔV** — Huang et al. (2016): depth jumps between adjacent rows detect stairs/curbs/drop-offs
- **Horizontal Gradient ΔH** — large horizontal depth changes detect wall edges, pillars
- **Patch-Based DFS Pathfinding** — arXiv 2504.20976 (2025): 15×15 depth patch grid + DFS to find longest free path, very similar to our 16×16 approach
- **Occupancy Grid + Free Space** — binary threshold grid, connected component analysis for walkable regions
- Decided on lightweight combination: absolute threshold (done) + ΔV + ΔH + free space analysis for B2

### 5. Documentation Updates
- Updated `PROGRESS.md`: Phase B1 marked complete with full details
- Created English & Chinese memos

## Files Modified / Created
| File | Action |
|------|--------|
| `Controllers/LiDARManager.swift` | **Created** then heavily iterated |
| `Controllers/ViewController.swift` | Edited (debug grid UI + LiDAR + Secrets.plist loading) |
| `Info.plist` | Edited (camera permission) |
| `Secrets.plist` | **Created** (gitignored, local only) |
| `.gitignore` | **Created** |
| `README.md` | **Created** |
| `PROGRESS.md` | Updated (B1 complete) |
| `Feb_18_Memo.md` | **Created** |
| `Feb_18_Memo_CN.md` | **Created** |
| `Feb_17_Memo_CN.md` | **Created** |
| 6 legacy files | Edited (API keys removed) |

## Issues Encountered & Resolved
1. **Grid orientation wrong** — Depth buffer is 256×192 in landscape-right native orientation; in portrait, x and y axes were swapped. Fixed by mapping display row→buffer x, display col→buffer y.
2. **Left-right mirrored** — After axis swap, left-right was still inverted. Fixed by reversing column index: `byStart = (cols - 1 - col) * pxPerCol`.
3. **Phone overheating + UI lag** — 16×16 grid at 10 Hz with full sort (O(n log n)) per cell was too expensive. Fixed with: (a) Quickselect O(n) for percentile-10, (b) analysis rate reduced to 5 Hz.
4. **Not enough forward data** — User needs more forward obstacle detection, less near-ground data. Fixed with `forwardCropRatio = 0.75` to crop bottom 25% of buffer and redistribute rows to forward area.
5. **API key exposed in public repo** — Hardcoded Google Maps keys in 6 files. Fixed with Secrets.plist + .gitignore + key rotation.
6. **Git push rejected** — Remote had LICENSE commit from GitHub creation. Fixed with `git pull --allow-unrelated-histories --no-rebase`.

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

## Key References for B2
- arXiv 2504.20976 (2025) — *Real-Time Wayfinding Assistant for BLV Users* — 15×15 patch DFS pathfinding
- Sensors 2015, 15(10):27116 — *Indoor Obstacle Detection Using Depth Information* — RANSAC ground plane
- IEEE RASC 2016, Huang et al. — *Fast Ground Plane Detection from 3D Point Clouds* — vertical gradient
- Sensors 2012, 12(12):17476 — *Assisting the Visually Impaired: Obstacle Detection* — stereo + RANSAC + acoustic

## Next Steps
- **Step 2:** Gradient analysis (ΔV + ΔH) + free space estimation → `HazardResult` output
- **Step 3:** Arbitration Layer merging Google Maps direction + LiDAR hazard
- **Step 4:** ESP32 protocol extension for STOP/terrain commands + motor patterns
