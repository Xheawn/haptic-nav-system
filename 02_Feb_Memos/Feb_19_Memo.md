# Feb 19, 2026 — Daily Memo

## Today's Accomplishments

### 1. Continuous Gradient Color for Depth Grid UI
- Replaced the 4-tier discrete color coding (red/orange/yellow/green) with a **continuous HSB hue gradient**
- Hue 0° (red) at 0m → Hue 120° (green) at 3.0m, linearly interpolated
- ≥3.0m and `inf` values display full green
- Added configurable `maxColorDistance = 3.0` in `ViewController.swift`
- Much more intuitive: every 0.1m difference is visually distinct

### 2. Literature Review (8 Papers)
Reviewed 8 academic papers on assistive navigation, obstacle detection, and haptic feedback for visually impaired users. Created detailed English and Chinese review documents.

**Papers reviewed:**
1. **Liu et al. (CHI 2022)** — Microsoft Soundscape user engagement analysis (4,700+ BLV users, ML engagement prediction)
2. **Tsai et al. (ACM TACCESS 2024)** — iOS inertial indoor wayfinding + backtracking (phone-in-pocket, Apple Watch UI)
3. **See et al. (Applied Sciences 2022)** — Smartphone depth imaging with 23-point sampling for obstacle detection
4. **MAIDR Meets AI (ASSETS 2024)** — Multimodal LLM data visualization for blind users (limited relevance)
5. **Crabb et al. (Sensors 2023)** — Lightweight visual-inertial indoor localization for BVI travelers
6. **Zuschlag et al. (arXiv 2022)** — 3D camera + haptic feedback sleeve with 2D vibration motor array
7. **Rodriguez et al. (Sensors 2012)** — RANSAC ground plane estimation + polar grid + acoustic feedback ⭐
8. **Huang et al. (Sensors 2015)** — RANSAC floor removal + region growing obstacle segmentation ⭐

**Key methods identified for our system (Priority 1 for Step 2):**
- Vertical gradient ΔV — detect stairs, curbs, drop-offs
- Horizontal gradient ΔH — detect obstacle edges, pillars
- Column-sum obstacle density (U-disparity concept) — left/right safety comparison
- Temporal smoothing (EMA) — reduce grid flickering
- Ground plane estimation (RANSAC, lightweight)
- Connected component analysis — group danger cells into obstacle clusters

### 3. Feb 18 Memos Updated
- Added sections for API key security fix, GitHub repo setup, B2 literature research
- Added issues #5-6 (API key exposure, git push conflict)
- Updated file tables and added B2 references section

### 4. B2 Hazard Analysis Pipeline — Full Implementation ⭐
Implemented the complete LiDAR obstacle detection and safe path finding system.

**Architecture decisions (from design discussion):**
- Use full 256×192 depth data for analysis (16×16 grid is debug UI only)
- ARKit VIO already fuses IMU — no need for separate IMU module
- Project depth pixels to **world coordinates** via `camera.transform` + scaled `camera.intrinsics` → phone shake/tilt invariant
- Replace RANSAC with **world Y height comparison** (simpler, handles multi-plane naturally)
- 3-motor haptic encoding (L/F/R) instead of 2 motors

**LiDARManager.swift — ~650 lines added:**
- **Data structures**: `FrameAnalysisResult` (spe/sps/spa/nspf/dse/use/pds/pus + obstacles), `ObstacleCluster`, `PointClassification` (6-level), 20+ configurable params
- **Step A**: Depth → world coordinates (64×48 downsampled, intrinsics scaled from captured image to depth map resolution)
- **Step B**: Ground Y estimation (histogram peak in lowest 30% + EMA α=0.1)
- **Step C**: Height classification (ground ±8cm / tripHazard / obstacleLow/Mid/High / dropMild/Severe)
- **Step E**: Stairs detection (worldY step pattern in central ±10 columns, ≥3 consecutive steps)
- **Step F**: Slope detection (linear regression on ground points, threshold ±5°)
- **Step G**: 48-column angular free space map (freeDistance per direction)
- **Step H**: Safe path finding (contiguous safe corridors, physical width ≥ safeWidthConstant 0.8m, center preference)
- **Step I**: Temporal smoothing (bool hysteresis 3-on/5-off, EMA angle/distance, asymmetric EMA for nearest obstacle)
- **Console log**: `[B2] flags=[SPE SPS] angle=+0.0° width=2.50m near=1.20m@+15° groundY=-1.150 obs=2`

**ViewController.swift — ~100 lines added:**
- **hazardLabel**: On-screen debug label (mode + L/F/R intensities + distances)
- **handleHazardUpdate()**: P0-P5 priority haptic encoding:
  - P0: STOP (all 3 motors 255, no safe path)
  - P1: Drop ahead (F motor fast pulse) — future ESP32 pattern
  - P2: Steering (angle → L/F/R weight interpolation, urgency from distance)
  - P3: Terrain overlay (stairs = F≥120, slope = F≥60)
  - P4: Side awareness (L/R ≤80 when obstacles on sides, F=0)
  - P5: Clear (all motors 0)
- **Console log**: `[HAPTIC] P2:steer +15° | L=000 F=113 R=089`

**Build: ✅ SUCCEEDED**

## Files Modified / Created
| File | Action |
|------|--------|
| `Controllers/LiDARManager.swift` | **Major edit** (~650 lines: B2 analysis pipeline) |
| `Controllers/ViewController.swift` | Edited (HSB gradient + B2 hazard label + haptic encoding) |
| `Literature_Review.txt` | **Created** (English, 8 papers) |
| `Literature_Review_CN.txt` | **Created** (Chinese, 8 papers) |
| `Feb_18_Memo.md` | Updated (added §2-4, issues, references) |
| `Feb_18_Memo_CN.md` | Updated (added §2-4, issues, references) |
| `Feb_19_Memo.md` | **Created** |
| `Feb_19_Memo_CN.md` | **Created** |

## Next Steps
- **Step 3:** Arbitration Layer — merge macro (Google Maps direction) + micro (LiDAR hazard)
- **Step 4:** ESP32 protocol upgrade (4-byte packet: CommandType + L/F/R intensities) + 3-motor PWM
- **Hardware:** Decide Front motor GPIO pin, test on real device
- Real-device testing of B2 analysis output (verify groundY, safe path, obstacle detection)
