# Project Progress & TODO

> Vibrotactile Navigation System for Blind/Low-Vision Pedestrians
> ESP32-S3 + iOS (iPhone 13 Pro) + Google Maps + LiDAR

---

## Overall Architecture (from Abstract)

```
iPhone App (Central)
├── Macro Navigation ── Google Maps route guidance → AdjustDirection + AngleDiff
├── Micro Safety ────── LiDAR depth sensing → obstacle/terrain hazard detection
└── Arbitration Layer ─ merges macro + micro → haptic command
        │
        │  BLE (2-byte packet, ~5 Hz)
        ▼
ESP32-S3 (Peripheral)
├── Parse command
└── Drive left/right vibrotactile motors (PWM intensity by AngleDiff)
```

---

## Completed

### Stage 1–3: Google Maps 路线基础

- [x] **Google Maps Directions API 集成** — 通过 walking mode 获取路线 polyline (`GoogleMapsHelper.swift`)
- [x] **地图路线绘制** — 解码 polyline 并在 GMSMapView 上绘制蓝色路径
- [x] **Point 数据模型** — 存储 index / latitude / longitude / angle (`Point.swift`)
- [x] **阈值1 可视化** — 每个路径点绘制绿色圆形区域 (radius 可配置)
- [x] **阈值2 可视化** — 相邻路径点间绘制黄色平行四边形区域 (width 可配置)
- [x] **路径角度计算** — 每个点到下一个点的方向角 (以正X轴为0°)

### Stage 4: 实时阈值检测

- [x] **阈值1 检测** — 判断用户是否在路径点圆形区域内 (`checkUserThresholds()`)
- [x] **阈值2 检测** — 判断用户是否在平行四边形区域内 (`isPoint(_:insideQuadrilateral:)`)
- [x] **阈值3 (偏离路线)** — 不在阈值1/2时触发 1s 延迟重规划
- [x] **期望方向显示** — 取用户所在阈值区域中最大 index 对应的 angle

### Stage 5: GPS Outlier 过滤

- [x] **Outlier 检测** — 两次偏离坐标距离 < 5m 时视为 GPS 漂移，不重规划
- [x] **保留最近有效角度** — `lastValidAngle` 在 outlier 时仍显示上次计算结果
- [x] **`lastRecalculationCoordinate`** — 记录上次重规划位置用于 outlier 比对

### Stage 6: 参数化配置

- [x] **threshold_1_radius = 4.0m** (圆形检测半径)
- [x] **threshold_2_width = 8.0m** (平行四边形总宽度)
- [x] **outlier_threshold_distance = 5.0m** (GPS outlier 判定阈值)

### Stage 7: 搜索栏

- [x] **UISearchBar** — 用户输入目的地，按搜索后动态发起新路线请求
- [x] **自动以当前 GPS 位置作为新起点**

### Stage 8: AdjustDirection & AngleDiff 逻辑

- [x] **AngleDiff 计算** — `phone heading - desired angle`，处理 360° 跨越
- [x] **AdjustDirection 分支** — 0=不振动 / 1=左振 / 2=右振 / 3=偏离路线 (`applyAdjustDirectionLogic()`)
- [x] **UI 显示** — 底部 `angleDiffLabel` + `adjustDirectionLabel` 实时更新
- [x] **BLE 发送已启用** — 2 字节 packet `[AdjustDirection, AngleDiff]`，5 Hz 节流，通过 `BLEManager.shared.sendCommand()` 实时发送

### 其他已完成

- [x] **Info.plist** — `NSBluetoothAlwaysUsageDescription` 蓝牙权限描述已配置
- [x] **ESP32 硬件验证** — Motor pin (D8=GPIO6, D10=GPIO8) 交替振动测试通过 (`esp32_s3_test.ino`)

---

## TODO

### Phase A — BLE 双向通信

- [x] **A1: ESP32 BLE Server** — 重写 `esp32_s3_test.ino`，BLEDevice 广播 + 可写 Characteristic + volatile 共享变量 + loop() 安全打印
- [x] **A2: iOS BLEManager.swift** — CBCentralManager 单例，扫描→连接→发现→写入，自动重连，`.withoutResponse` 低延迟写入
- [x] **A3: ViewController 集成** — 启用 `BLEManager.shared.start()` 和 `sendCommand()`，5 Hz 节流正常工作
- [x] **A4: 端到端验证** — iPhone 实时发送 `[AdjustDirection, AngleDiff]` → ESP32 Serial 打印确认，通信稳定

- [ ] **A5: ESP32 马达 PWM 驱动**
  - 收到 `[AdjustDirection, AngleDiff]` 后驱动马达：
    - `0` → 两个马达都停
    - `1` → 左马达 PWM (强度 = AngleDiff 映射)
    - `2` → 右马达 PWM
    - `3` → 特殊模式 (偏离路线警示，如双马达短脉冲)
  - PWM 占空比与 AngleDiff 成正比，编码紧迫感

### Phase B — LiDAR 微观安全层

- [x] **B1: LiDAR 深度采集 + 16×16 Grid**
  - ARKit `smoothedSceneDepth` (256×192 Float32) 实时采集
  - 16×16 grid，每 cell percentile-10 (Quickselect O(n))
  - Portrait 方向修正 (buffer x→display row, buffer y→display col, L↔R 镜像)
  - `forwardCropRatio=0.75` 前方聚焦 (裁掉 25% 近地面区域)
  - 4 档颜色 debug UI overlay (红<0.5m / 橙0.5-1.0m / 黄1.0-2.0m / 绿>2.0m)
  - 5 Hz 分析 + 2 Hz console log，Quickselect 优化减少发热

- [ ] **B2: 梯度分析 + 障碍物检测**
  - 水平梯度 ΔH: 检测墙壁/柱子等立面障碍物边缘
  - 垂直梯度 ΔV: 检测台阶/路沿/地面落差
  - 绝对距离阈值: center cols < dangerDistance → DANGER
  - Free space: 左半 vs 右半平均深度 → 转向建议
  - 输出 `HazardResult { level, steerSuggestion, nearestDepth, terrainAlert }`

- [ ] **B3: Safety Arbitration Layer**
  - 融合 macro (Google Maps 方向) 和 micro (LiDAR 风险) 信息
  - 输出最终 haptic command: `clear / steer_left / steer_right / stop`
  - Safety-first 原则：micro 安全优先于 macro 导航

- [ ] **B4: 紧迫感编码**
  - 脉冲频率 (pulse frequency) 映射危险等级
  - 更新 ESP32 解析逻辑以支持多种模式

### Phase C — 用户评估

- [ ] **C1: 评估指标设计**
  - Path deviation (路径偏差)
  - Hazard events (危险事件次数)
  - Completion time (完成时间)
  - Perceived workload (NASA-TLX 等量表)

- [ ] **C2: Baseline 对比**
  - Google Maps audio-only guidance 作为 baseline
  - 有视力参与者闭眼行走测试 (pilot)
  - 校园路线: Odegaard → HUB

- [ ] **C3: 正式用户测试**
  - IRB approval (如需要)
  - 招募 blind/low-vision 参与者
  - 数据收集与分析

### Phase D — 工程优化 (可并行)

- [ ] **D1: 独立电池供电方案**
  - ESP32 + 马达供电设计
  - 手机壳集成方案

- [ ] **D2: 低功耗优化**
  - BLE 连接参数调优
  - ESP32 deep sleep 策略

- [ ] **D3: UI/UX 完善**
  - BLE 连接状态显示
  - 振动模式设置界面
  - 无障碍 (Accessibility) 支持

---

## Shared BLE Protocol

```
Service UUID:        4fafc201-1fb5-459e-8fcc-c5c9c331914b
Characteristic UUID: beb5483e-36e1-4688-b7f5-ea07361b26a8

Packet: 2 bytes
  Byte 0: AdjustDirection  (0=none, 1=left, 2=right, 3=off-route)
  Byte 1: AngleDiff magnitude (0–180, clamped & rounded to uint8)
```

---

*Last updated by Shawn: 2026-02-18*
