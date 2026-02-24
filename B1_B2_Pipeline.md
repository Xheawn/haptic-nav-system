# B1 + B2 完整算法流程图

> 本文档描述 `LiDARManager.swift` 和 `ViewController.swift` 中 B1（深度采集 + 可视化）与 B2（世界坐标障碍物检测 + 触觉编码）的完整逻辑流程。

---

## 总览

```
ARFrame (5Hz)
  │
  ├── B1: depthMap → 16×16 Grid → Debug UI (HSB 色相渐变)
  │
  └── B2: depthMap + confidenceMap + camera pose
        │
        ├── Step A: 全分辨率世界坐标投影 (192×192) + 置信度过滤
        ├── Step B: 地面高度估计 (直方图峰值 + EMA)
        ├── Step C: 高度分类 (7 级)
        ├── Step E: 台阶检测 (中央 ±10°)
        ├── Step F: 坡道检测 (中央 ±5°, 线性回归 + R²)
        ├── Step G: 角度自由空间图 (192 列)
        ├── Step H: 安全路径寻找 (走廊宽度 ≥ 0.8m)
        ├── Step I: 时间平滑 (滞后 + EMA)
        └── → FrameAnalysisResult → P0-P5 触觉编码 → L/F/R 电机强度
```

---

## 入口：ARSessionDelegate

```
session(_:didUpdate:)  每帧调用
  │
  ├── 节流检查: now - lastAnalysisTime ≥ 0.2s (5Hz)?
  │     否 → return
  │
  ├── 获取深度数据: frame.smoothedSceneDepth ?? frame.sceneDepth
  │     ├── depthMap:       CVPixelBuffer, Float32, 256×192
  │     └── confidenceMap:  CVPixelBuffer?, UInt8,  256×192
  │
  ├── B1: buildGrid(depthMap) → 16×16 grid
  │
  ├── B2: analyzeHazards(frame, depthMap, confidenceMap) → FrameAnalysisResult
  │
  ├── 主线程回调:
  │     ├── onGridUpdate(grid)       → ViewController 更新 Debug UI
  │     └── onHazardUpdate(analysis) → ViewController 触觉编码
  │
  └── Console Log (2Hz 节流):
        ├── printGrid()     → [LiDAR] 16×16 矩阵
        └── printAnalysis() → [B2] flags/angle/width/near/groundY/pitch
```

---

## B1: 16×16 深度网格

### 流程

```
buildGrid(depthMap)
  │
  ├── 锁定 CVPixelBuffer, 读取 Float32 数据
  │
  ├── 参数:
  │     ├── bufW = 256, bufH = 192
  │     ├── usableX = 256 × 0.75 = 192 (forwardCropRatio 裁掉近地面 25%)
  │     ├── pxPerRow = 192 / 16 = 12
  │     └── pxPerCol = 12  (192 / 16)
  │
  ├── 对每个 cell (row, col):
  │     ├── 映射: display row → buffer x, display col → buffer y (L↔R 镜像)
  │     │     bxStart = row × 12
  │     │     byStart = (15 - col) × 12   ← 镜像
  │     │
  │     ├── 收集 12×12 = 144 个深度值 (跳过 NaN/Inf/≤0)
  │     │
  │     └── percentile10(cellDepths):
  │           ├── k = count × 0.1
  │           └── Quickselect O(n) 找第 k 小值 (median-of-three pivot)
  │               → 代表该 cell 最近 10% 的距离 (保守估计)
  │
  └── 返回 16×16 Float grid (单位: 米)
```

### Debug UI (ViewController)

```
updateDepthGridUI(grid)
  │
  └── 对每个 cell:
        ├── 距离 → HSB 色相连续渐变
        │     hue = 120° × min(distance / 3.0, 1.0)
        │     0m → 0° (红)  ...  3m → 120° (绿)
        │
        └── 显示距离数字 (meters)
```

---

## B2: 世界坐标障碍物检测

### Step A: 世界坐标投影

```
projectToWorld(depthMap, transform, intrinsics, 192, 192, confidenceMap)
  │
  ├── 相机内参缩放:
  │     capturedImage (1920×1440) → depthMap (256×192)
  │     fx' = fx × (256/1920),  fy' = fy × (192/1440)
  │     cx' = cx × (256/1920),  cy' = cy × (192/1440)
  │
  ├── 分辨率: rows=192, cols=192, stride=1 (全像素)
  │
  ├── 锁定 depthMap + confidenceMap
  │
  └── 对每个像素 (row, col):
        │
        ├── buffer 坐标:
        │     bx = row                    (0..191)
        │     by = (191 - col) × 1        (镜像, 0..191)
        │
        ├── 读取深度: d = floatBuffer[by × stride + bx]
        │     过滤: d > 0, 非NaN, 非Inf, d < 5.0m
        │
        ├── 置信度过滤:                        ← NEW
        │     confidence = confBuffer[by × stride + bx]
        │     0 = low → 跳过
        │     1 = medium, 2 = high → 保留
        │
        ├── 反投影到相机坐标:
        │     x_cam =  d × (bx - cx') / fx'
        │     y_cam = -d × (by - cy') / fy'   ← 取反 (图像Y↓ vs 相机Y↑)
        │     z_cam = -d                        ← 相机朝 -Z 方向看
        │
        └── 世界坐标 = camera.transform × [x_cam, y_cam, z_cam, 1]
              worldPoints[row][col] = (wx, wy, wz)
              validMask[row][col] = true
```

### Step B: 地面高度估计 (直方图法)

> 详细算法见文末「附录：直方图地面高度估计算法」

```
estimateGroundY(worldPoints, validMask, rows, cols, cameraY)
  │
  ├── 收集所有 valid 像素的 world Y 值
  │
  ├── 构建直方图 (binSize = 5cm)
  │
  ├── 在最低 30% Y 范围内找峰值 bin
  │
  ├── newGroundY = minY + (bestBin + 0.5) × 0.05
  │
  └── EMA 平滑: groundY = prev × 0.9 + new × 0.1
```

### Step C: 高度分类

```
classifyPoints(worldPoints, validMask, rows, cols, groundY)
  │
  └── 对每个 valid 像素:
        h = worldY - groundY
        │
        ├── h < -0.15m          → dropSevere  (严重落差)
        ├── h < -0.10m          → dropMild    (轻微落差)
        ├── -0.08m ≤ h ≤ +0.08m → ground      (地面)
        ├── +0.08m < h < +0.15m → tripHazard  (绊倒风险)
        ├── +0.15m ≤ h < +0.50m → obstacleLow (低矮障碍)
        ├── +0.50m ≤ h < +1.50m → obstacleMid (中等障碍)
        └── h ≥ +1.50m          → obstacleHigh(高障碍/墙)
```

### Step E: 台阶检测

```
detectStairs(worldPoints, classification, validMask, rows, cols, cameraPos)
  │
  ├── 扫描范围: 中央 ±10° (cols×10/48 列)
  │
  ├── 对每列:
  │     ├── 收集 ground/tripHazard/obstacleLow 点的 (worldY, hdist_from_camera)
  │     ├── 按 hdist 排序 (近→远)
  │     └── 寻找阶梯模式:
  │           ├── 相邻点 Y 跳变 10~25cm 且前进距离 > 5cm → 算一级台阶
  │           └── ≥3 级同向跳变 → upStairs / downStairs
  │
  └── 返回 (upStairs: Bool, downStairs: Bool)
```

### Step F: 坡道检测

```
detectSlope(worldPoints, classification, validMask, rows, cols, cameraPos)
  │
  ├── 扫描范围: 中央 ±5° (cols×5/48 列), 仅 ground 点
  │
  ├── 收集 (hdist_from_camera, worldY) 对
  │
  ├── 前置检查:
  │     ├── 点数 ≥ 30
  │     └── 水平跨度 ≥ 1.0m
  │
  ├── 线性回归: Y = a × hdist + b
  │     ├── 计算 R² (决定系数)
  │     └── R² > 0.5 才接受 (拒绝噪声拟合)
  │
  ├── slopeAngle = atan(a) → 度
  │     ├── > +5°  → upSlope
  │     └── < -5°  → downSlope
  │
  └── 返回 (upSlope: Bool, downSlope: Bool)
```

### Step G: 角度自由空间图

```
computeFreeSpaceMap(worldPoints, classification, validMask, rows, cols, cameraPos)
  │
  ├── 192 列, 每列 ≈ 0.24° (总 FOV ≈ 46°)
  │
  └── 对每列:
        ├── 遍历所有行, 找「阻塞」分类的最近水平距离:
        │     阻塞 = obstacleLow | obstacleMid | obstacleHigh | dropSevere
        │
        └── freeDistance[col] = 该列最近障碍物距离 (默认 5.0m)
```

### Step H: 安全路径寻找

```
findSafePath(freeDistance, cols, classification, worldPoints, validMask, rows)
  │
  ├── 标记安全列: freeDistance[col] ≥ 2.0m → safe
  │
  ├── 找连续安全走廊:
  │     ├── 计算物理宽度 = 2 × minFreeDist × tan(angularWidth/2)
  │     └── 过滤: 宽度 ≥ 0.8m (safeWidthConstant) → passable
  │
  ├── 选择最佳走廊:
  │     ├── 优先包含中心列 (直行) → isStraight = true
  │     └── 否则选最宽走廊, 按距中心排序
  │
  ├── 最近障碍物: 全局 freeDistance 最小值 → nearDist, nearAngle
  │
  ├── 障碍物聚类: 连续 blocked 列 → ObstacleCluster
  │     └── classifyObstacleType:
  │           ├── drop占多数     → .dropOff
  │           ├── <5°宽 + 有高点 → .pole
  │           ├── high+mid > 1/3 → .wall
  │           └── 仅low          → .lowObstacle / .tripHazard
  │
  └── 返回 (spe, sps, spa, spw, nspf, nearDist, nearAngle, obstacles[])
```

### Step I: 时间平滑

```
applyHysteresis + EMA
  │
  ├── Bool 标志滞后:
  │     ├── 连续 3 帧 rawValue=true  → 激活 (开)
  │     └── 连续 5 帧 rawValue=false → 取消 (关)
  │     应用于: spe, sps, nspf, use, dse, pus, pds
  │
  ├── 安全路径角度 EMA: α = 0.3
  │     smoothedAngle = prev × 0.7 + raw × 0.3
  │
  └── 最近障碍距离 非对称 EMA:
        ├── 接近 (raw < smoothed): α = 0.7 (快速响应)
        └── 远离 (raw > smoothed): α = 0.3 (慢速释放)
```

---

## 触觉编码 (ViewController)

```
handleHazardUpdate(FrameAnalysisResult)
  │
  ├── 优先级判定:
  │     │
  │     ├── P0: nspf=true (无安全路径)
  │     │     → L=255, F=255, R=255 (全部最强震动 → 紧急停止)
  │     │
  │     ├── P2: spe=true, sps=false (需要转向)
  │     │     urgency = 1 - nearDist / 5.0
  │     │     base = 80 + urgency × 175 (80~255)
  │     │     │
  │     │     ├── angle ≥ 0° (向右转):
  │     │     │     R = base × min(1, θ/45°)
  │     │     │     F = base × max(0, 1 - θ/45°)
  │     │     │     L = 0
  │     │     │
  │     │     └── angle < 0° (向左转):
  │     │           L = base × min(1, |θ|/45°)
  │     │           F = base × max(0, 1 - |θ|/45°)
  │     │           R = 0
  │     │
  │     ├── P4: spe=true, sps=true (前方畅通, 侧面感知)
  │     │     对每个 obstacle:
  │     │       sideIntensity = 80 × (1 - dist/2.0), max 80
  │     │       angle < 0 → L, angle > 0 → R
  │     │
  │     └── P5: 无上述情况 → clear (全部 0)
  │
  ├── P3 叠加 (地形警报, 加到 F 电机):
  │     ├── 台阶: F = max(F, 120)
  │     └── 坡道: F = max(F, 60)
  │
  ├── Clamp 0-255
  │
  ├── 电机 EMA 平滑: α = 0.4
  │     motorX = prev × 0.6 + raw × 0.4
  │
  └── 输出:
        ├── hazardLabel: "B2: P2:steer +15° | L=000 F=113 R=089"
        └── console:     "[HAPTIC] P2:steer +15° | L=000 F=113 R=089"
```

---

## 附录：直方图地面高度估计算法

### 设计目标
在充满各种物体（地面、墙壁、家具、人）的场景中，稳定且准确地找到**地面的世界坐标 Y 值**。

### 核心思路
地面在 LiDAR 视野中通常占据大量像素，且这些像素的 world Y 值聚集在一个很窄的范围内。利用直方图找到**最低区域中最密集的 Y 值聚集**，即为地面。

### 详细步骤

```
输入: 所有 valid 像素的 world Y 值 (可能 10,000~30,000 个)
  │
  ├── 1. 收集 Y 值
  │     遍历 192×192 网格, validMask[r][c] = true 的取 worldPoints[r][c].y
  │     → yValues[] (数千~数万个值)
  │
  ├── 2. 空值处理
  │     如果 yValues 为空:
  │       fallback = cameraY - 1.2m (假设手机握在 1.2m 高度)
  │       → 直接用 fallback 初始化 smoothedGroundY
  │
  ├── 3. 构建直方图
  │     binSize = 0.05m (5cm 精度)
  │     minY = yValues 最小值
  │     maxY = yValues 最大值
  │     numBins = (maxY - minY) / 0.05 + 1
  │     │
  │     对每个 y ∈ yValues:
  │       bin = (y - minY) / 0.05  → 取整
  │       histogram[bin] += 1
  │
  │     示例 (室内平地, 手机在 0m 高度, 地面在 -1.2m):
  │     ┌─────────────────────────────────────────────────────┐
  │     │  Y值(m)  │ -1.25 -1.20 -1.15 -1.10 ... 0.00 ... 0.80 │
  │     │  点数    │   45   320   280    30  ...  150 ...  80   │
  │     │           ▲                         ▲           ▲
  │     │       地面峰值                   相机高度      桌面
  │     └─────────────────────────────────────────────────────┘
  │
  ├── 4. 在最低 30% 范围内找峰值
  │     searchBins = numBins × 30%
  │     │
  │     为什么只搜索最低 30%?
  │     → 地面是场景中最低的大面积表面
  │     → 排除墙壁中部/上部、天花板、高处物体的干扰
  │     → 即使桌面/椅子也在地面之上, 不会被误选
  │     │
  │     在 histogram[0..searchBins-1] 中找最大 count 的 bin
  │     → bestBin
  │
  ├── 5. 计算地面 Y
  │     newGroundY = minY + (bestBin + 0.5) × 0.05
  │     │             ↑       ↑         ↑
  │     │          全局最低Y  峰值bin    bin中心偏移
  │
  └── 6. EMA 指数移动平均
        α = 0.1 (很小, 地面不会突变)
        │
        如果 smoothedGroundY 已有值:
          smoothedGroundY = prev × 0.9 + newGroundY × 0.1
        否则:
          smoothedGroundY = newGroundY (首帧初始化)
        │
        → 返回 smoothedGroundY
```

### 为什么选择直方图而非其他方法

| 方法 | 优点 | 缺点 |
|------|------|------|
| **直方图峰值** (当前) | O(n), 无参数拟合, 对异常值鲁棒 | 假设地面是最低密集区 |
| RANSAC 平面拟合 | 理论上更精确 | O(n×iter), 多平面时不稳定, 计算昂贵 |
| 简单 min(Y) | 最简单 | 一个噪声点就会偏移, 完全不鲁棒 |
| 中位数 | 简单 | 当障碍物占多数时地面被淹没 |
| 最低 10% 均值 | 较鲁棒 | 大落差场景会拉低估计 |

### 关键设计参数

| 参数 | 值 | 作用 |
|------|-----|------|
| `binSize` | 0.05m | 直方图分辨率。太小→噪声敏感; 太大→精度不够 |
| 搜索范围 | 最低 30% | 限制搜索区域。确保只在低处找地面, 忽略墙壁/家具 |
| EMA α | 0.1 | 时间平滑强度。0.1 = 90%保留旧值, 10%接受新值 → 约 10 帧 (2秒@5Hz) 收敛 |

### 边界情况处理

- **无 valid 点**: fallback = cameraY - 1.2m
- **所有 Y 值相同**: range = 0 → 直接返回该值
- **室外倾斜地面**: 直方图仍能找到地面的平均高度; 坡道由 Step F 单独检测
- **台阶**: 直方图会找到当前脚下平台的高度; 台阶由 Step E 检测
- **大落差 (悬崖边)**: 地面像素仍占多数, 落差点被归入较低 bin 但数量少, 不影响峰值

---

## 端到端时序管线

### 时间线 (analysisInterval = 0.2s, 5Hz)

```
时间(s)     iPhone 端                           ESP32 端
──────────────────────────────────────────────────────────────
0.000       ARKit 启动
0.000-0.015 帧#1: 采集+B1+B2处理+BLE发送(~15ms)
0.015       ─── BLE 传输 ~10ms ───────────────→ 收到帧#1 L/F/R
0.025                                           电机输出帧#1的PWM值
  ...       (空闲等待下一个0.2s窗口)              电机保持帧#1的值不变
0.200-0.215 帧#2: 采集+处理+BLE发送
0.225                                           电机切换到帧#2的值
  ...                                           电机保持帧#2的值不变
0.400-0.415 帧#3: 采集+处理+BLE发送
0.425                                           电机切换到帧#3的值
  ...
0.600-0.615 帧#4
0.800-0.815 帧#5
1.000-1.015 帧#6                                ← 第一秒处理了5帧
```

### 各阶段延迟分解

| 阶段 | 耗时 | 说明 |
|------|------|------|
| LiDAR 硬件采集 | ~16ms | ARKit 内部 60FPS，我们节流到 5FPS |
| 节流等待 | 0~200ms | 最坏情况刚错过上一个窗口 |
| B1: buildGrid (16×16) | ~1-2ms | percentile-10 quickselect |
| B2: analyzeHazards (192×192) | ~5-15ms | 取决于 valid 像素数量 |
| ├─ Step A: projectToWorld | ~3-5ms | 矩阵乘法 × 36864 像素 |
| ├─ Step B: estimateBandGroundY | ~1-2ms | 3 波段直方图 + EMA |
| ├─ Step C: classifyPoints | ~1-2ms | 逐点高度分类 |
| ├─ Step E-F: stairs/slope | ~1ms | 中央列扫描 + 线性回归 |
| ├─ Step G-H: freespace/path | ~1-2ms | 192 列 → 走廊评分 |
| └─ Step I: temporal smoothing | ~0.1ms | 滞后计数器 + EMA |
| main thread dispatch | ~1ms | DispatchQueue.main.async |
| handleHazardUpdate (P0-P5) | ~0.1ms | 优先级判定 + L/F/R 编码 |
| BLE 传输 (.withoutResponse) | ~7-15ms | BLE 4.2 典型值 |
| ESP32 loop 轮询延迟 | 0~20ms | delay(20) |
| PWM → 电机机械响应 | ~5-10ms | ERM 振动电机启动延迟 |
| **典型端到端延迟** | **~25-50ms** | 从采集完成到电机开始振动 |

### 关键设计要点

- **ESP32 无状态保持**: 收到 PWM 值后持续输出，不需要 iPhone 持续发送。电机在两帧之间 (~185ms) 保持上一帧的强度不变
- **人体感知阈值**: 人对振动强度变化的感知约 50-100ms，5Hz 更新率 (200ms) 足够"实时"
- **帧间对比机制**:
  - `PoseSnapshot` 历史 (10 帧 ≈ 2s): 对比 ΔcameraY, ΔcameraPitch, ΔgroundY → 动态 EMA α
  - Bool 滞后计数器: 连续 3 帧 true 才激活, 连续 5 帧 false 才关闭
  - EMA 平滑: 角度 (α=0.3), 距离 (非对称 α=0.3/0.7), 电机强度 (α=0.4), 地面Y (α=0.1)
- **可调参数**: `analysisInterval` 可降至 0.1s (10Hz) 获得更快响应，但功耗和发热增加

---

## P0-P5 触觉优先级编码

```
FrameAnalysisResult
  │
  ├── P0: 紧急停止
  │     条件: noSafePathFound AND nearestForwardDistance < 1.0m
  │     前方 ±15° 锥形区域完全阻塞且距离 < 1m
  │     输出: L=255, F=255, R=255 (全电机最大)
  │
  ├── P1: 前方阻塞但有距离 (降级转向)
  │     条件: noSafePathFound AND nearestForwardDistance ≥ 1.0m
  │     找到最宽间隙 (即使 < 0.8m) 的方向，引导用户转向
  │     输出: base=120~200, 按 best-effort gap 角度分配 L/F/R
  │
  ├── P2: 转向引导
  │     条件: safePathExist AND NOT safePathStraight
  │     存在 ≥ 0.8m 的安全通道但不在正前方
  │     输出: base=80~255 (按距离紧迫度), 按 safePathAngle 分配 L/F/R
  │
  ├── P3: 地形警告 (叠加层)
  │     条件: upStairsExist OR downStairsExist → F≥120
  │           pathUpSlope OR pathDownSlope → F≥60
  │     叠加在其他优先级之上
  │
  ├── P4: 侧面感知
  │     条件: safePathExist AND safePathStraight (前方畅通)
  │     两侧有障碍物时轻微提示
  │     输出: 侧面电机 0~80 (距离 < 2m 时线性增强)
  │
  └── P5: 全清
        条件: 以上均不满足
        输出: L=0, F=0, R=0
```

### 前方锥形区域 (Forward Cone)

```
        ←─── FOV 46° ───→
        ┌─────────────────┐
        │   ·   ·   ·   · │
        │  ╱─────────────╲ │ ← ±15° 前方锥形 (用于 P0 判定)
        │ ╱               ╲│
        │╱     P0 区域     ╲│
        ├───────────────────┤
        │← 边缘 →│← 中央 →│← 边缘 →│
        │ ±15~23° │  ±15°  │ ±15~23°│
        │ 不触发P0 │ 触发P0 │ 不触发P0│
        └───────────────────┘
              用户位置
```

FOV 边缘 (±15°~±23°) 的障碍物只参与 P2/P4 侧面感知，不触发 P0 紧急停止。
这避免了走廊中侧墙误触发 P0 的问题。
