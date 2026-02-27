# Google Maps 导航逻辑详解

> 本文档描述 `ViewController.swift` 和 `GoogleMapsHelper.swift` 中宏观导航（Macro Navigation）的完整逻辑流程。
> 宏观导航负责：路线规划 → GPS 定位 → 航向判定 → 偏航检测 → BLE 振动指令。

---

## 总览

```
用户输入目的地 (SearchBar)
  │
  ├── Stage 1: Google Directions API → 获取 polyline
  ├── Stage 2: Polyline 解码 → Point[] 路径点数组 (含角度)
  ├── Stage 3: 地图绘制 (路线 + 阈值区域可视化)
  ├── Stage 4: GPS 实时位置 → 阈值检测 (用户在路线上?)
  ├── Stage 5: 偏航处理 + GPS outlier 过滤
  ├── Stage 6: AngleDiff 计算 → AdjustDirection 判定
  ├── Stage 7: BLE 2字节指令 → ESP32 振动电机
  └── Stage 8: 搜索栏动态更新目的地
```

---

## 涉及文件

| 文件 | 职责 |
|------|------|
| `ViewController.swift` | 主控制器：GPS、指南针、阈值检测、BLE 发送、UI |
| `GoogleMapsHelper.swift` | 辅助类：Directions API、polyline 绘制、角度计算、四边形检测 |
| `Point.swift` | 数据模型：路径点 (index, lat, lng, angle) |
| `BLEManager.swift` | BLE 连接管理：扫描、连接、写入 characteristic |

---

## Stage 1: 路线请求

### 触发时机

1. **App 启动**: `viewDidLoad()` → `requestRoute(origin, destination, ...)`
2. **用户搜索**: `searchBarSearchButtonClicked()` → 更新 `destination` → `requestRoute()`
3. **偏航重规划**: `checkUserThresholds()` 检测到用户离开路线 → 1秒延迟后 `requestRoute()`

### 请求流程

```
requestRoute(origin, destination, threshold_1_Radius, threshold_2_Width)
  │
  └── GoogleMapsHelper.fetchDirections(origin, destination, apiKey)
        │
        ├── URL: https://maps.googleapis.com/maps/api/directions/json
        │     ?origin=...&destination=...&mode=walking&key=...
        │
        ├── 解析 JSON:
        │     routes[0].overview_polyline.points → polyline 编码字符串
        │
        └── 回调 → drawRouteOnMap(polyline, mapView, ...)
```

- **模式**: `mode=walking` (步行导航)
- **API Key**: 从 `Secrets.plist` 读取（不提交到 git）

---

## Stage 2: Polyline 解码 → Point 数组

```
drawRouteOnMap(polyline, mapView, threshold_1_Radius, threshold_2_Width)
  │
  ├── GMSPath(fromEncodedPath: polyline) → 解码为坐标序列
  │
  ├── 遍历每个坐标点:
  │     ├── 创建 Point(index, latitude, longitude)
  │     ├── 计算 angle = calculateAngle(当前点 → 下一个点)
  │     │     └── atan2(deltaLat, deltaLon) → 0~360° (正X轴=0°, 逆时针正)
  │     ├── 最后一个点: angle = nil
  │     └── 存入 points[] 数组
  │
  └── 返回 [Point] → 存入 ViewController.routePoints
```

### Point 数据模型

```swift
class Point {
    var index: Int          // 路径中的索引位置
    var latitude: Double    // 纬度
    var longitude: Double   // 经度
    var angle: Double?      // 当前点 → 下一个点的方向角 (°)
                            // 以正X轴(东)为0°, 逆时针为正
                            // 最后一个点为 nil
}
```

### 角度计算

```
calculateAngle(from: start, to: end):
  deltaX = end.longitude - start.longitude
  deltaY = end.latitude - start.latitude
  degrees = atan2(deltaY, deltaX) × (180/π)
  if degrees < 0: degrees += 360
  → 返回 0~360°
```

**注意**: 这里用的是简化的经纬度差值计算角度，而非大圆方位角（bearing）。在小范围内（城市级别）误差可接受。

---

## Stage 3: 地图可视化

绘制三层信息到 GMSMapView 上：

### 3.1 路线线条
```
GMSPolyline(path) → 蓝色线 (strokeWidth=5)
```

### 3.2 阈值1: 圆形区域 (绿色)
```
每个路径点 → GMSCircle(position, radius=threshold_1_radius)
  ├── strokeColor: 绿色 0.8 alpha
  └── fillColor:   绿色 0.3 alpha
```
- **当前值**: `threshold_1_radius = 20.0m` (原始值 4.0m)

### 3.3 阈值2: 平行四边形区域 (黄色)
```
每对相邻路径点 (point[i], point[i+1]) → 平行四边形
  │
  ├── 计算方位角 bearing = atan2(Δlon, Δlat)
  ├── 垂直方向 = bearing ± 90°
  ├── 4 个顶点:
  │     startLeft  = start + halfWidth @ (bearing+90°)
  │     startRight = start + halfWidth @ (bearing-90°)
  │     endLeft    = end   + halfWidth @ (bearing+90°)
  │     endRight   = end   + halfWidth @ (bearing-90°)
  │
  └── GMSPolygon → 黄色填充
```
- **当前值**: `threshold_2_width = 8.0m` (总宽，半宽=4m)

### 可视化示意

```
        ● point[0]                    ● point[1]
        │                              │
   ┌────┼────────────────────────────┼────┐
   │    │     阈值2 黄色平行四边形      │    │  ← 宽 8m
   └────┼────────────────────────────┼────┘
        │                              │
      (绿色圆 r=20m)              (绿色圆 r=20m)
        ───── 蓝色路线 ──────────→
```

---

## Stage 4: GPS 实时阈值检测

### 触发

```
CLLocationManagerDelegate.didUpdateLocations
  → checkUserThresholds(userCoord, outlier_threshold_distance)
```

GPS 更新频率约 1Hz（`kCLLocationAccuracyBest`）。

### 检测逻辑

```
checkUserThresholds(userCoord, outlier_threshold_distance)
  │
  ├── 遍历所有 routePoints:
  │     │
  │     ├── 阈值1检测 (圆形):
  │     │     distance(user, point[i]) ≤ 20m ?
  │     │     是 → threshold1Indices.append(i)
  │     │
  │     └── 阈值2检测 (平行四边形):
  │           构建 quad = createQuadrilateral(point[i], point[i+1])
  │           isPoint(user, insideQuadrilateral: quad) ?
  │           是 → threshold2Indices.append(i)
  │
  ├── 情况 A: 用户在阈值1 或 阈值2 内 (在路线上)
  │     ├── isOffRoute = false
  │     ├── maxIndex = max(所有匹配的 index)  ← 取最远的匹配点
  │     ├── desiredAngle = routePoints[maxIndex].angle
  │     ├── 更新 UI: "Expected Orientation: xxx°"
  │     ├── applyAdjustDirectionLogic(desiredAngle)
  │     └── resetThreshold3Timer()
  │
  └── 情况 B: 用户不在任何阈值内 (偏航)
        ├── isOffRoute = true
        ├── AdjustDirection = 3 (off-route)
        ├── BLE 发送 [3, 0]
        └── → Stage 5 偏航处理
```

### 四边形点内判定算法

```
isPoint(P, insideQuadrilateral [A,B,C,D]):
  cross1 = cross(A→B, A→P)
  cross2 = cross(B→C, B→P)
  cross3 = cross(C→D, C→P)
  cross4 = cross(D→A, D→P)

  所有叉积同号 → 点在四边形内
```

---

## Stage 5: 偏航处理 + GPS Outlier 过滤

当用户在阈值3 (不在路线上) 时：

```
情况 B (偏航) 续:
  │
  ├── 首次偏航 (threshold3Timer == nil):
  │     │
  │     ├── GPS Outlier 检测:
  │     │     distance(当前位置, 上次重规划位置) < 5m?
  │     │     是 → 判定为 GPS 漂移，不重规划
  │     │         └── 保留 lastValidAngle 继续显示
  │     │
  │     └── 非 Outlier:
  │           ├── 记录 lastRecalculationCoordinate = 当前位置
  │           └── 启动 1秒定时器 → requestRoute(当前位置, destination)
  │               └── 重新获取路线 → 更新 routePoints
  │
  └── 重复偏航 (timer 已存在):
        └── 等待 timer 触发，不重复请求
```

### 关键参数

| 参数 | 值 | 作用 |
|------|-----|------|
| `threshold_1_radius` | 20.0m | 圆形检测半径 |
| `threshold_2_width` | 8.0m | 平行四边形总宽 |
| `outlier_threshold_distance` | 5.0m | GPS outlier 阈值 |
| 重规划延迟 | 1.0s | 偏航后等待时间 |

---

## Stage 6: AdjustDirection + AngleDiff 计算

### 触发时机

1. **位置更新** (`didUpdateLocations`): 阈值检测后如果在路线上 → `applyAdjustDirectionLogic(desiredAngle)`
2. **航向更新** (`didUpdateHeading`): 如果不偏航且有 `lastValidAngle` → `applyAdjustDirectionLogic(desiredAngle)`

### 手机朝向转换

```
CLHeading.trueHeading → 以正北为 0°, 顺时针
  ↓ 转换
convertedAngle = (90 - trueHeading) mod 360
  → 以正东(X轴)为 0°, 逆时针为正
  → 与 Point.angle 坐标系一致
```

### AngleDiff 计算逻辑

```
applyAdjustDirectionLogic(desiredAngle):
  │
  ├── rawAngleDiff = phoneAngle - desiredAngle
  │
  ├── rawAngleDiff > 5 且 ≤ 180:
  │     AdjustDirection = 2 (右转)
  │     AngleDiff = rawAngleDiff
  │
  ├── rawAngleDiff > 5 且 > 180:
  │     AdjustDirection = 1 (左转)
  │     AngleDiff = 360 - rawAngleDiff
  │
  ├── rawAngleDiff < -5 且 ≤ -180:
  │     AdjustDirection = 2 (右转)
  │     AngleDiff = 360 + rawAngleDiff
  │
  ├── rawAngleDiff < -5 且 > -180:
  │     AdjustDirection = 1 (左转)
  │     AngleDiff = |rawAngleDiff|
  │
  └── |rawAngleDiff| ≤ 5:
        AdjustDirection = 0 (无需调整)
        AngleDiff = rawAngleDiff
```

### 角度定义图示

```
             90° (北)
              │
              │
  180° (西) ──┼── 0° (东)    ← X 轴正方向
              │
              │
            270° (南)

  phoneAngle:   手机实际朝向 (转换后)
  desiredAngle: 路径期望朝向 (Point.angle)
  AngleDiff:    phoneAngle - desiredAngle
```

---

## Stage 7: BLE 指令发送

### 协议格式 (当前: 2字节 Macro Navigation)

```
Byte 0: AdjustDirection
  0 = 无需调整 (±5° 内)
  1 = 左转振动
  2 = 右转振动
  3 = 偏航 (off-route)

Byte 1: AngleDiff magnitude (0~180, uint8)
```

### 发送节流

```
if (now - lastBLECommandSentAt) < 0.2s:
  跳过 (节流到 5Hz)
else:
  BLEManager.shared.sendCommand(Data([direction, magnitude]))
```

### BLE 连接

```
BLEManager (CBCentralManager):
  ├── 扫描: XIAO_ESP32S3 (Service UUID: 4fafc201-...)
  ├── 连接: 自动重连
  ├── 写入: .withoutResponse (低延迟)
  └── Characteristic UUID: beb5483e-...
```

---

## Stage 8: 搜索栏动态目的地

```
UISearchBarDelegate.searchBarSearchButtonClicked:
  ├── destination = searchBar.text
  ├── origin = 当前 GPS 位置 (如果可用)
  └── requestRoute(origin, destination, ...)
```

---

## 完整数据流时序

```
时间轴 (典型场景: 用户在路线上行走)
─────────────────────────────────────────────────────
T+0.0s   GPS didUpdateLocations
           ├── checkUserThresholds → 在阈值1内
           ├── maxIndex=5, desiredAngle=45°
           └── applyAdjustDirectionLogic(45°)
                ├── phoneAngle=50°, diff=5° → dir=0 (无需调整)
                └── BLE: [0, 5]

T+0.1s   Heading didUpdateHeading
           ├── trueHeading=40° → convertedAngle=50°
           └── applyAdjustDirectionLogic(45°)
                ├── diff=5° → dir=0
                └── BLE: 节流跳过 (<0.2s)

T+0.3s   Heading didUpdateHeading
           ├── trueHeading=70° → convertedAngle=20°
           └── applyAdjustDirectionLogic(45°)
                ├── diff=-25° → dir=1 (左转)
                └── BLE: [1, 25]

T+1.0s   GPS didUpdateLocations
           ├── checkUserThresholds → 不在任何阈值内
           ├── isOffRoute = true, dir=3
           ├── BLE: [3, 0]
           └── 启动 1s 定时器

T+2.0s   定时器触发
           └── requestRoute(当前位置, 目的地)
                → Directions API → 新路线 → routePoints 更新
```

---

## Macro vs Micro 导航对比

| 维度 | Macro (本文档) | Micro (B2 LiDAR) |
|------|---------------|------------------|
| **传感器** | GPS + 磁力计 | LiDAR 深度相机 |
| **范围** | 全局路线 (km 级) | 局部障碍 (0-5m) |
| **更新率** | GPS ~1Hz, 指南针 ~10Hz | 5Hz (analysisInterval) |
| **输出** | AdjustDirection (左/右/无/偏航) | L/F/R 电机强度 (0-255) |
| **BLE 协议** | 2 字节: [dir, angle] | 4 字节 (计划中): [cmd, L, F, R] |
| **反馈方式** | 单侧振动 (左或右) | 三电机独立强度 |
| **文件** | ViewController + GoogleMapsHelper | LiDARManager |

### 未来融合 (Step 3: Arbitration Layer)

```
Macro: "向左转 25°"  ──┐
                       ├── Arbitration Layer → 最终 L/F/R 输出
Micro: "右前方障碍物"  ──┘

优先级: Micro P0 (紧急停止) > Micro P1-P2 > Macro 转向 > Micro P4 (侧面)
```

---

*Last updated: 2026-02-23*
