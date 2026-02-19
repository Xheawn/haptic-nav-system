# Feb 17, 2026 — Daily Memo

## Today's Accomplishments

### 1. Project Progress Document
- Created `PROGRESS.md` with full project architecture, completed stages (1–8), and phased TODO
- All completed work documented with checkbox format, matching TODO style

### 2. BLE Communication — Phase A (Core)

**ESP32 端 (`esp32_s3_test.ino`)**
- Rewrote firmware as BLE Server using `BLEDevice.h`
- Device name: `XIAO_ESP32S3`, advertises custom Service UUID
- Writable Characteristic (WRITE + WRITE_NR) for low-latency commands
- Auto-restart advertising on disconnect
- Fixed compilation error: `std::string` → `String` (ESP32 Arduino library returns Arduino `String`)
- Fixed Serial garbled output: moved `Serial.println` out of BLE callback (runs on different FreeRTOS task) into `loop()` with `volatile` shared variables and 100ms throttle + single `snprintf` atomic print

**iOS 端 (`BLEManager.swift`) — NEW FILE**
- `CBCentralManager` singleton
- Scan → Connect → Discover Service → Discover Characteristic pipeline
- `sendCommand(_ data: Data)` with `.withoutResponse` for low latency
- Auto-reconnect on disconnect

**ViewController 集成**
- Enabled `BLEManager.shared.start()` in `viewDidLoad`
- Enabled `BLEManager.shared.sendCommand(packet)` in both:
  - `applyAdjustDirectionLogic()` — normal navigation commands
  - `checkUserThresholds()` — off-route notification (direction=3)
- 5Hz throttle confirmed working

### 3. End-to-End Verification
- iPhone successfully sends `[AdjustDirection, AngleDiff]` in real-time
- ESP32 Serial Monitor confirms receipt: `[BLE] Dir:1  Angle:148`
- BLE connection stable during testing

## Files Modified / Created
| File | Action |
|------|--------|
| `esp32_s3_test/esp32_s3_test.ino` | Rewritten (BLE Server) |
| `Controllers/BLEManager.swift` | **Created** |
| `Controllers/ViewController.swift` | Edited (uncommented BLE calls) |
| `PROGRESS.md` | **Created** & updated |

## Issues Encountered & Resolved
1. **`std::string` compilation error** — ESP32 Arduino `getValue()` returns `String`, not `std::string`
2. **Serial output garbled** — BLE callback runs on different FreeRTOS task; fixed by storing to `volatile` vars and printing only from `loop()`

## Next Steps
- **A5:** ESP32 motor PWM control based on received BLE commands
- **Phase B:** LiDAR integration for micro-level obstacle detection
