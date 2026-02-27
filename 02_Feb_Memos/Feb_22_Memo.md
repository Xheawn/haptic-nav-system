# Feb 22, 2026 — Daily Memo

## Today's Accomplishments

### 1. Fixed Critical Bug: Camera Coordinate Signs in `projectToWorld()`
The ARKit camera coordinate system is **+X right, +Y up, -Z forward**. The original implementation had wrong signs:

```swift
// BEFORE (wrong):
let y_cam = (Float(by) - cy) * d / fy   // missing negative
let z_cam = d                              // should be -d

// AFTER (correct):
let y_cam = -d * (Float(by) - cy) / fy    // image Y↓ vs camera Y↑
let z_cam = -d                              // camera looks along -Z
```

**Impact:** All world Y values were inverted — ground was treated as ceiling, height classification was wrong, slope detection produced false positives (e.g., walls detected as slopes), and phone tilt angle had no correct effect on obstacle detection.

### 2. Fixed Critical Bug: Distance Reference Point
All `hdist` calculations used distance from **world origin** instead of **camera position**:

```swift
// BEFORE (wrong): distance from world origin
let hdist = sqrtf(pt.x * pt.x + pt.z * pt.z)

// AFTER (correct): distance from camera
let dx = pt.x - cameraPos.x
let dz = pt.z - cameraPos.z
let hdist = sqrtf(dx * dx + dz * dz)
```

**Impact:** After fixing Bug 1, everything became P5 (clear) because as the user walked away from the ARKit session origin, all obstacle distances appeared very large. This bug was masked by Bug 1 (wrong signs accidentally kept distances "reasonable" near origin).

**Fixed in:** `computeFreeSpaceMap()`, `detectStairs()`, `detectSlope()`

### 3. Improved Slope Detection Robustness
- Increased minimum ground point count: 20 → **30**
- Added **minimum distance range check**: ground points must span ≥ 1.0m horizontally (prevents false slope when only a few ground points exist near a wall base)
- Added **R² > 0.5** check: linear regression must actually explain the data well before reporting a slope (prevents noise-induced false positives)

### 4. Added Camera Pitch Debug Logging
- Compute camera pitch from transform matrix: `asin(forward.y)` in degrees
- Log `pitch=XX°` in `[B2]` console output (0° = horizontal, negative = looking down)
- Helps verify on-device that phone tilt correctly affects obstacle classification

## Why These Bugs Mattered Together

| Scenario | Bug 1 Only (wrong signs) | Bug 1 Fixed + Bug 2 (wrong origin) | Both Fixed |
|----------|--------------------------|-------------------------------------|------------|
| Wall ahead | Slope false positive | P5 (everything "far") | Correct obstacle detection |
| Phone horizontal | Wrong classification | P5 always | Ground = P5, correct |
| Phone vertical at wall | Wrong classification | P5 always | Wall = P0/P2, correct |

## Files Modified
| File | Action |
|------|--------|
| `Controllers/LiDARManager.swift` | Fixed camera coord signs, camera-relative distances, slope R² check, pitch logging |

## Issues
| # | Description | Status |
|---|-------------|--------|
| 7 | `projectToWorld` y_cam and z_cam signs inverted (ARKit camera: +Y up, -Z forward) | ✅ Fixed |
| 8 | `hdist` computed from world origin instead of camera position | ✅ Fixed |
| 9 | Slope detection false positive near walls (insufficient validation) | ✅ Fixed |

## Next Steps
- **Real-device testing** of corrected B2 analysis (verify groundY, pitch, obstacle detection at different phone angles)
- **Step 3:** Arbitration Layer — merge macro (Google Maps direction) + micro (LiDAR hazard)
- **Step 4:** ESP32 protocol upgrade (4-byte packet) + 3-motor PWM
