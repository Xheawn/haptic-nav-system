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

## Files Modified / Created
| File | Action |
|------|--------|
| `Controllers/ViewController.swift` | Edited (HSB gradient color) |
| `Literature_Review.txt` | **Created** (English, 8 papers) |
| `Literature_Review_CN.txt` | **Created** (Chinese, 8 papers) |
| `Feb_18_Memo.md` | Updated (added §2-4, issues, references) |
| `Feb_18_Memo_CN.md` | Updated (added §2-4, issues, references) |
| `Feb_19_Memo.md` | **Created** |
| `Feb_19_Memo_CN.md` | **Created** |

## Next Steps
- **Step 2:** Implement ΔV + ΔH gradient analysis + column-sum density + EMA temporal smoothing → `HazardResult` output
- **Step 3:** Arbitration Layer merging Google Maps direction + LiDAR hazard
- **Step 4:** ESP32 protocol extension for STOP/terrain commands + motor patterns
- Test HSB gradient on real device
