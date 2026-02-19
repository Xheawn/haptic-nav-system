# Haptic Navigation System

A vibrotactile navigation system for visually impaired users, combining **iOS** (ARKit LiDAR + Google Maps) with **ESP32-S3 BLE** haptic feedback.

## Overview

This system provides two layers of navigation guidance through vibration motors:

- **Macro layer** — Google Maps turn-by-turn directions encoded as left/right vibrations with intensity proportional to angle difference
- **Micro layer** — Real-time LiDAR obstacle detection via a 16×16 depth grid, alerting users to nearby hazards

## Architecture

```
iPhone 13 Pro                          ESP32-S3
┌──────────────────────┐    BLE     ┌──────────────────┐
│  Google Maps API     │───────────▶│  Command Parser  │
│ ARKit LiDAR (256×192)│  2-byte    |  Motor L (PWM)   │
│  ViewController      │  packet    │  Motor R (PWM)   │
│  BLEManager          │            └──────────────────┘
│  LiDARManager        │
└──────────────────────┘
```

## Features

- **BLE Communication** — Low-latency `.withoutResponse` writes at 5 Hz
- **16×16 LiDAR Depth Grid** — Percentile-10 per cell via O(n) Quickselect
- **Portrait Orientation Correction** — Proper axis mapping for handheld use
- **Forward-Biased FOV** — Configurable `forwardCropRatio` to prioritize forward detection
- **4-Tier Hazard Coloring** — Red (<0.5m) / Orange (0.5–1.0m) / Yellow (1.0–2.0m) / Green (>2.0m)
- **Auto-Reconnect** — BLE connection recovery on disconnect

## Setup

### iOS App

1. Open `navigationTest.xcodeproj` in Xcode
2. Create `navigationTest/Secrets.plist` with your Google Maps API key:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>GOOGLE_MAPS_API_KEY</key>
       <string>YOUR_API_KEY_HERE</string>
   </dict>
   </plist>
   ```
3. Add `Secrets.plist` to your Xcode project (drag into the navigator)
4. Build and run on an iPhone with LiDAR (iPhone 12 Pro or later)

### ESP32-S3

1. Open `esp32_s3_test/esp32_s3_test.ino` in Arduino IDE
2. Install the ESP32 board package
3. Select board: **XIAO_ESP32S3**
4. Upload to the ESP32-S3

## BLE Protocol

```
Service UUID:        4fafc201-1fb5-459e-8fcc-c5c9c331914b
Characteristic UUID: beb5483e-36e1-4688-b7f5-ea07361b26a8

Packet: 2 bytes
  Byte 0: AdjustDirection  (0=none, 1=left, 2=right, 3=off-route)
  Byte 1: AngleDiff magnitude (0–180, uint8)
```

## Requirements

- iPhone 12 Pro or later (LiDAR required)
- iOS 15+
- Seeed XIAO ESP32-S3
- Google Maps Directions API key
- Arduino IDE with ESP32 board support

## License

MIT License — see [LICENSE](LICENSE) for details.
