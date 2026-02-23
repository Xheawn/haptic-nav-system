# Feb 23, 2026 — Daily Memo

## Today's Accomplishments

### 1. Full-Resolution Analysis Upgrade: 64×48 → 192×192
Upgraded the B2 hazard analysis pipeline from downsampled 64×48 (stride 3–4) to **full 256×192 resolution** (stride 1, with `forwardCropRatio=0.75` → 192×192 = 36,864 points).

| Metric | Old (64×48) | New (192×192) |
|--------|-----------|-------------|
| Analysis points | 3,072 | 36,864 |
| Memory | ~50KB | ~550KB |
| Free space angular columns | 48 (≈1°/col) | 192 (≈0.24°/col) |
| 5cm pole @3m | 0–1 px → missed | 2–3 px → detectable |

**Key change:** Removed fixed `analysisRows=64` / `analysisCols=48` constants. Now dynamically computed from actual depth buffer dimensions.

### 2. Confidence Map Filtering
Introduced ARKit's per-pixel confidence map (`ARDepthData.confidenceMap`) to filter out unreliable depth measurements:

```swift
// ARConfidenceLevel: 0=low, 1=medium, 2=high
if let cb = confBuffer {
    let confidence = cb[by * confBytesPerRow + bx]
    guard confidence >= 1 else { continue }  // skip low confidence
}
```

**Impact:** Removes noisy points from long range, reflective surfaces, and depth edges — reducing false obstacle detections and improving ground estimation stability.

### 3. Adaptive Stair/Slope Scan Ranges
Scan column ranges now scale proportionally with resolution to maintain consistent angular coverage:
- **Stairs:** ±10 cols @48 → `cols×10/48` = ±40 cols @192 (≈±10°)
- **Slope:** ±5 cols @48 → `cols×5/48` = ±20 cols @192 (≈±5°)

## Files Modified
| File | Action |
|------|--------|
| `Controllers/LiDARManager.swift` | Full-res upgrade, confidence filtering, adaptive scan ranges |

## Issues
| # | Description | Status |
|---|-------------|--------|
| 10 | 64×48 too coarse for small obstacle detection (poles, curbs) | ✅ Fixed (full res) |
| 11 | No confidence filtering — noisy points at range/edges | ✅ Fixed |
| 12 | Stair/slope scan ranges were fixed column counts, not angular | ✅ Fixed |

## Next Steps
- **Real-device testing** of full-resolution analysis (verify small obstacle detection, performance/heat)
- **Step 3:** Arbitration Layer — merge macro (Google Maps direction) + micro (LiDAR hazard)
- **Step 4:** ESP32 protocol upgrade (4-byte packet) + 3-motor PWM
