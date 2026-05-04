# LiDARManager.swift 完整运行指南

> 本文档以**时间线**方式，从 App 启动开始，详细解释 `LiDARManager.swift` 中的
> 每一个函数**何时被谁调用**、**做了什么**、**输出给了谁**，以及它与 `ViewController` 的交互关系。

---

## 目录

1. ["main" 在哪？为什么没有 main？](#1-main-在哪为什么没有-main)
2. [文件整体结构一览](#2-文件整体结构一览)
3. [时间线：从 App 启动到持续运行](#3-时间线从-app-启动到持续运行)
4. [Phase 1: 初始化与启动 (T=0)](#4-phase-1-初始化与启动-t0)
5. [Phase 2: ARKit 帧回调循环 (T>0, 持续运行)](#5-phase-2-arkit-帧回调循环-t0-持续运行)
6. [Phase 2a: B1 — buildGrid()](#6-phase-2a-b1--buildgrid)
7. [Phase 2b: B2 — analyzeHazards()](#7-phase-2b-b2--analyzehazards)
8. [Phase 2c: 回调 ViewController](#8-phase-2c-回调-viewcontroller)
9. [Phase 2d: Console 日志](#9-phase-2d-console-日志)
10. [所有函数调用关系总表](#10-所有函数调用关系总表)
11. [数据结构速查](#11-数据结构速查)
12. [配置参数速查](#12-配置参数速查)

---

## 1. "main" 在哪？为什么没有 main？

**Swift iOS App 没有你能看到的 `main()` 函数。**

在 C/C++/Python 中，程序从 `main()` 开始运行。但在 iOS 中：

1. 系统内部调用 `UIApplicationMain()`（你看不到这行代码）
2. `UIApplicationMain()` 创建 `UIApplication` + 加载 Storyboard
3. Storyboard 告诉系统 "第一个页面用 `ViewController`"
4. 系统实例化 `ViewController` 并调用 `viewDidLoad()`
5. **`viewDidLoad()` 就是你的 "main"** — 你写的所有初始化逻辑从这里开始

```
iOS 内部:
  UIApplicationMain()  ← 你看不到
    → 加载 Storyboard
    → 创建 ViewController
    → 调用 viewDidLoad()  ← ★ 你的代码从这里开始
```

`LiDARManager.swift` 本身**没有入口点**。它是一个工具类，被 `ViewController` 调用后才开始工作。

---

## 2. 文件整体结构一览

```
LiDARManager.swift (1205 行)
│
├── L1-83:    数据结构定义
│   ├── ObstacleType (enum)         — 障碍物类型: wall/pole/lowObstacle/dropOff/tripHazard
│   ├── PointClassification (enum)  — 点分类: invalid/ground/tripHazard/obstacle×3/drop×2
│   ├── PoseSnapshot (struct)       — 相机位姿快照（用于时序验证）
│   ├── ObstacleCluster (struct)    — 单个障碍物簇: 角度/距离/宽度/类型
│   └── FrameAnalysisResult (struct)— B2 分析结果: 安全路径 + 地形 + 阻塞 + 辅助信息
│
├── L87-229:  LiDARManager 类主体
│   ├── 单例: static let shared
│   ├── 可配置参数 (30+ 个)
│   ├── 网格常量
│   ├── 公共状态 + 回调闭包
│   ├── 私有状态（时序平滑变量）
│   ├── start()                     — 启动 ARSession
│   ├── stop()                      — 暂停 ARSession
│   └── init()                      — 私有构造函数
│
├── L233-267: ARSessionDelegate 扩展
│   └── session(_:didUpdate:)       — ★ 60FPS 帧回调，整个管线的入口
│
├── L271-381: Grid 计算扩展
│   ├── buildGrid()                 — B1: 深度图 → 16×16 网格
│   ├── percentile10()              — O(n) 第10百分位
│   ├── kthSmallest()               — Quickselect 算法
│   └── printGrid()                 — 网格控制台打印
│
├── L385-494: B2 管线入口
│   └── analyzeHazards()            — 调度 Step A→I
│
├── L498-579: Step A — 深度 → 世界坐标投影
│   └── projectToWorld()
│
├── L583-706: Step B — 距离分段地面 Y 估计
│   ├── estimateBandGroundY()
│   └── histogramGroundY()
│
├── L710-747: Step C — 高度分类
│   └── classifyPoints()
│
├── L751-814: Step E — 台阶检测
│   └── detectStairs()
│
├── L818-888: Step F — 坡道检测
│   └── detectSlope()
│
├── L892-921: Step G — 角度自由空间图
│   └── computeFreeSpaceMap()
│
├── L925-1106: Step H — 安全路径寻找
│   └── findSafePath()
│
├── L1110-1149: 障碍物类型分类辅助
│   └── classifyObstacleType()
│
├── L1153-1173: 时序平滑
│   └── applyHysteresis()
│
└── L1177-1205: 控制台日志
    └── printAnalysis()
```

---

## 3. 时间线：从 App 启动到持续运行

```
T = 0.000s  ┌─ App 启动 ─────────────────────────────────────────────┐
            │ iOS 创建 ViewController → viewDidLoad() 被调用          │
            │                                                         │
T = 0.006s  │ LiDARManager.shared                                    │
            │   ← 首次访问单例，触发 init()                            │
            │   ← 所有 property 默认值初始化                           │
            │                                                         │
T = 0.007s  │ LiDARManager.shared.start()                            │
            │   ├── 检查 LiDAR 硬件支持                               │
            │   ├── 创建 ARWorldTrackingConfiguration                 │
            │   ├── config.frameSemantics = .sceneDepth               │
            │   ├── session.delegate = self (LiDARManager)            │
            │   └── session.run(config) ← ★ 启动传感器（非阻塞）      │
            │                                                         │
T = 0.008s  │ ViewController 注册两个回调:                            │
            │   onGridUpdate = { self.updateDepthGridUI(grid) }       │
            │   onHazardUpdate = { self.handleHazardUpdate(analysis) }│
            └─────────────────────────────────────────────────────────┘

T = 0.050s  ┌─ ARKit 传感器就绪，开始产生帧 ──────────────────────────┐
            │ ARKit 内部以 ~60FPS 在后台线程产生 ARFrame               │
            └──────────────────────────────────────────────────────────┘

T = 0.200s  ┌─ 第 1 次分析 ──────────────────────────────────────────┐
            │ session(_:didUpdate: frame)  ← ARKit 回调               │
            │   ├── 节流检查: 0.200 - 0 ≥ 0.2? ✅ 通过               │
            │   ├── buildGrid(depthMap)         → grid [[Float]]      │
            │   ├── analyzeHazards(frame, ...)  → FrameAnalysisResult │
            │   │     ├── Step A: projectToWorld()                    │
            │   │     ├── Step B: estimateBandGroundY()               │
            │   │     ├── Step C: classifyPoints()                    │
            │   │     ├── Step E: detectStairs()                      │
            │   │     ├── Step F: detectSlope()                       │
            │   │     ├── Step G: computeFreeSpaceMap()               │
            │   │     ├── Step H: findSafePath()                      │
            │   │     └── Step I: applyHysteresis() × 7 flags         │
            │   │                 + EMA angle + EMA nearDist           │
            │   │                                                     │
            │   └── DispatchQueue.main.async {                        │
            │         onGridUpdate?(grid)    → VC.updateDepthGridUI() │
            │         onHazardUpdate?(anal.) → VC.handleHazardUpdate()│
            │       }                                                 │
            └──────────────────────────────────────────────────────────┘

T = 0.217s  (ARKit 回调了 ~1 帧，但 0.217 - 0.200 < 0.2 → 被节流跳过)
T = 0.233s  (同上，跳过)
...
T = 0.400s  ┌─ 第 2 次分析 ──────────────────────────────────────────┐
            │ session(_:didUpdate:) → 0.400 - 0.200 ≥ 0.2? ✅         │
            │   (同上完整流程)                                         │
            └──────────────────────────────────────────────────────────┘

T = 0.500s  ┌─ 控制台日志 ────────────────────────────────────────────┐
            │ session(_:didUpdate:) → logInterval 检查:                │
            │   0.500 - 0 ≥ 0.5? ✅                                   │
            │   printGrid(grid)                                        │
            │   printAnalysis(analysis)                                │
            │   → [LiDAR] 16×16 Depth Grid (p10, meters): ...         │
            │   → [B2] flags=[SPE SPS] angle=+0.0° width=2.50m ...   │
            └──────────────────────────────────────────────────────────┘

T = 0.600s  第 3 次分析
T = 0.800s  第 4 次分析
T = 1.000s  第 5 次分析 + 第 2 次日志
... ← 无限循环, 每 0.2s 分析一次, 每 0.5s 打印一次
```

---

## 4. Phase 1: 初始化与启动 (T=0)

### 4.1 单例创建 — `LiDARManager.shared`

```swift
// L87-89
class LiDARManager: NSObject {
    static let shared = LiDARManager()  // 全局唯一实例
```

**首次访问** `LiDARManager.shared` 时（在 `viewDidLoad` 中），Swift 自动调用 `init()`：

```swift
// L226-228
private override init() {
    super.init()
}
```

此时所有 property 初始化：
- 30+ 个可配置参数（阈值、频率等）获得默认值
- `depthGrid` = 16×16 的 `Float.greatestFiniteMagnitude`
- `latestAnalysis` = `FrameAnalysisResult.empty`
- `onGridUpdate` / `onHazardUpdate` = nil（还没注册回调）
- `session` = 新的 `ARSession()` 实例
- 滞后计数器、EMA 状态等全部归零

### 4.2 start() — 启动 ARSession

**调用者**: `ViewController.viewDidLoad()` L165

```swift
// L202-219
func start() {
    // 1. 硬件检查
    guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
        return  // 没有 LiDAR → 整个 LiDAR 功能静默关闭
    }

    // 2. 配置 ARSession
    let config = ARWorldTrackingConfiguration()
    config.frameSemantics = .sceneDepth  // 请求逐帧深度图

    // 3. 注册委托（让 ARKit 回调我们）
    session.delegate = self  // self = LiDARManager

    // 4. 启动（非阻塞，传感器在后台线程运行）
    session.run(config)
}
```

**关键**: `session.run(config)` 执行后，`start()` 立即返回。ARKit 在后台线程以 ~60FPS 产生帧，并通过 `session(_:didUpdate:)` 回调 `LiDARManager`。

### 4.3 ViewController 注册回调

**紧接着** `start()` 之后，`ViewController` 注册两个闭包（L166-171）：

```swift
// ViewController.swift L166-171
LiDARManager.shared.onGridUpdate = { [weak self] grid in
    self?.updateDepthGridUI(grid)      // → 更新 16×16 彩色网格 UI
}
LiDARManager.shared.onHazardUpdate = { [weak self] analysis in
    self?.handleHazardUpdate(analysis) // → 计算 P0-P5 电机强度
}
```

这些闭包被**存储**在 `LiDARManager` 的 property 里。当 LiDARManager 完成分析后，在主线程上调用它们。

---

## 5. Phase 2: ARKit 帧回调循环 (T>0, 持续运行)

### session(_:didUpdate:) — 整个管线的唯一入口

```swift
// L235-266
func session(_ session: ARSession, didUpdate frame: ARFrame) {
```

**谁调用它**: ARKit 框架，在后台线程，~60FPS（每 ~16ms 一次）

**做了什么**:

```
session(_:didUpdate:)
  │
  ├── ① 节流: now - lastAnalysisTime < 0.2s? → return (跳过这帧)
  │     → 60FPS 中只有每 12 帧处理 1 帧 (5Hz)
  │
  ├── ② 获取深度数据:
  │     depthData = smoothedSceneDepth ?? sceneDepth
  │     depthMap     = CVPixelBuffer (Float32, 256×192 = 49,152 个深度值)
  │     confidenceMap = CVPixelBuffer (UInt8, 256×192 = 49,152 个置信度值)
  │
  ├── ③ B1: grid = buildGrid(depthMap)              → [[Float]] 16×16
  │
  ├── ④ B2: analysis = analyzeHazards(frame, ...)   → FrameAnalysisResult
  │
  ├── ⑤ DispatchQueue.main.async:
  │     ├── onGridUpdate?(grid)       → ViewController.updateDepthGridUI()
  │     └── onHazardUpdate?(analysis) → ViewController.handleHazardUpdate()
  │
  └── ⑥ 日志 (0.5s 节流):
        ├── printGrid(grid)
        └── printAnalysis(analysis)
```

**为什么要节流**: LiDAR 以 60FPS 产生数据，但分析 + UI 更新不需要那么快。5Hz 够用（人走路速度 ~1.4m/s，0.2s 走 0.28m），而且省电、减少发热。

---

## 6. Phase 2a: B1 — buildGrid()

**被谁调用**: `session(_:didUpdate:)` L247

```
buildGrid(depthMap)
  │
  ├── CVPixelBufferLockBaseAddress   ← 锁定内存（防止 ARKit 同时写入）
  │
  ├── 遍历 16×16 = 256 个 cell:
  │     对于每个 cell:
  │       ├── 计算 buffer 坐标范围 (bx, by)
  │       │     ├── row → buffer x (竖屏旋转)
  │       │     └── col → buffer y (左右镜像翻转)
  │       ├── 收集该区域所有有效深度值 (~144 个像素)
  │       └── percentile10() → 第10百分位深度值
  │             └── kthSmallest() ← Quickselect O(n) 算法
  │
  ├── CVPixelBufferUnlockBaseAddress ← 解锁内存
  │
  └── 返回 grid: [[Float]] 16×16
        → row 0 = 最远 (前方)
        → row 15 = 最近 (脚下)
        → col 0 = 左
        → col 15 = 右
```

### 为什么用第10百分位而不是最小值？

最小值容易受噪声干扰（单个错误深度值就会影响结果）。第10百分位 = "最近的那 10% 深度值中的最大值"，更稳定。

---

## 7. Phase 2b: B2 — analyzeHazards()

**被谁调用**: `session(_:didUpdate:)` L251

这是整个 B2 管线的调度中心，按顺序调用 Step A → I：

```
analyzeHazards(frame, depthMap, confidenceMap)
  │
  ├── 准备工作:
  │     ├── 缩放 camera.intrinsics 到深度图分辨率
  │     ├── 计算相机俯仰角 (pitch)
  │     └── 确定分析分辨率 (rows=192, cols=192)
  │
  ├── Step A: projectToWorld()           ← 深度像素 → 世界 3D 坐标
  │     输入: depthMap + camera.transform + intrinsics
  │     输出: worldPoints[192][192] + validMask[192][192]
  │
  ├── Step B: estimateBandGroundY()      ← 估计地面高度
  │     输入: worldPoints + cameraPos
  │     输出: bandGroundY[3] = [近程地面Y, 中程地面Y, 远程地面Y]
  │     内部调用: histogramGroundY() × 3 次
  │
  ├── Step C: classifyPoints()           ← 每个点的高度分类
  │     输入: worldPoints + bandGroundY
  │     输出: classification[192][192] (8 种分类之一)
  │
  ├── Step E: detectStairs()             ← 台阶检测
  │     输入: worldPoints + classification (中央 ±10° 范围)
  │     输出: (upStairs: Bool, downStairs: Bool)
  │
  ├── Step F: detectSlope()              ← 坡道检测
  │     输入: worldPoints + classification (中央 ±5° 范围)
  │     输出: (upSlope: Bool, downSlope: Bool)
  │
  ├── Step G: computeFreeSpaceMap()      ← 每个方向的最近障碍物距离
  │     输入: worldPoints + classification
  │     输出: freeDistance[192] (每列一个值，单位: 米)
  │
  ├── Step H: findSafePath()             ← 安全路径 + 障碍物簇
  │     输入: freeDistance + classification + worldPoints
  │     输出: (spe, sps, spa, spw, nspf, nearDist, nearAngle,
  │            forwardNearDist, obstacles)
  │     内部调用: classifyObstacleType() × 每个障碍物簇
  │
  └── Step I: 时序平滑
        ├── applyHysteresis() × 7 个布尔 flag
        ├── EMA smooth angle (α=0.3)
        └── 非对称 EMA nearDist (接近 α=0.7, 远离 α=0.3)
        输出: FrameAnalysisResult
```

### Step A: projectToWorld() — 深度 → 世界坐标

```
对于每个深度像素 (bx, by):
  │
  ├── d = depthMap[by][bx]              ← 原始深度值 (米)
  ├── 过滤: d>0, 非NaN, 非Inf, <5m
  ├── 过滤: confidenceMap >= 1 (medium+)
  │
  ├── 反投影到相机坐标:
  │     x_cam =  d × (bx - cx) / fx
  │     y_cam = -d × (by - cy) / fy     ← 负号: 图像Y向下 vs 相机Y向上
  │     z_cam = -d                       ← 负号: 相机朝 -Z 方向
  │
  └── 变换到世界坐标:
        worldPoint = camera.transform × [x_cam, y_cam, z_cam, 1]
```

### Step B: estimateBandGroundY() — 地面高度估计

```
将所有有效点按水平距离分成 3 段:
  Band 0: 0 – 1.5m (近程)
  Band 1: 1.5 – 3.0m (中程)
  Band 2: 3.0 – 5.0m (远程)

对每段:
  ├── 收集所有 Y 值
  ├── histogramGroundY(): 直方图 (bin=5cm), 在最低 30% 区间找峰值
  ├── 缺失数据 → 从邻近段继承
  └── EMA 平滑 (α=0.1, pose-aware 动态调整)
```

### Step C: classifyPoints() — 高度分类

```
对于每个有效点:
  h = point.y - bandGroundY[对应段]

  h < -0.15m        → dropSevere   (严重落差)
  h < -0.10m        → dropMild     (轻微落差)
  |h| ≤ 0.08m       → ground       (地面)
  0.08 < h < 0.15m  → tripHazard   (绊倒风险)
  0.15 ≤ h < 0.50m  → obstacleLow  (低矮障碍)
  0.50 ≤ h < 1.50m  → obstacleMid  (中等障碍)
  h ≥ 1.50m         → obstacleHigh (高大障碍)
```

### Step G: computeFreeSpaceMap() — 自由空间

```
对于 192 列中的每一列 (代表一个水平方向):
  遍历该列所有行:
    如果分类 ∈ {obstacleLow, Mid, High, dropSevere}:
      记录最近的水平距离
  freeDistance[col] = 该方向最近阻塞距离 (无阻塞 = 5.0m)
```

### Step H: findSafePath() — 安全路径

```
1. 标记安全列: freeDistance[col] ≥ 2.0m → safe
2. 连续安全列 → 走廊 (Corridor)
3. 每个走廊计算物理宽度: width = 2 × minDist × tan(角宽度/2)
4. 过滤: 物理宽度 ≥ 0.8m → passable
5. 选最佳走廊:
     优先包含正前方的走廊 (isStraight=true)
     否则选最宽的 (tie-break: 最靠近中心的)
6. 计算 forwardNearDist: 正前方 ±15° 内最近障碍距离 (用于 P0 判定)
7. 构建障碍物簇列表 (blocked 列段 → ObstacleCluster)
```

### Step I: 时序平滑

```
7 个布尔 flag 各自通过 applyHysteresis():
  连续 3 帧 true  → 激活 (防止闪烁开)
  连续 5 帧 false → 关闭 (防止闪烁关)

safePathAngle: EMA α=0.3 (中等跟随速度)
nearestDist: 非对称 EMA (接近时 α=0.7 快响应, 远离时 α=0.3 慢释放)
```

---

## 8. Phase 2c: 回调 ViewController

分析完成后，通过 `DispatchQueue.main.async` 切到主线程，调用 ViewController 注册的回调：

```
LiDARManager (后台线程)                    ViewController (主线程)
  │                                           │
  ├── buildGrid() → grid                      │
  ├── analyzeHazards() → analysis             │
  │                                           │
  └── DispatchQueue.main.async ───────────────┤
                                              │
        onGridUpdate?(grid)                   │
          └── updateDepthGridUI(grid) ────────┤
                │                             │
                └── 遍历 16×16 grid:          │
                      label.text = "2.1"      │
                      label.backgroundColor   │
                        = HSB 渐变色          │
                                              │
        onHazardUpdate?(analysis)             │
          └── handleHazardUpdate(analysis) ───┤
                │                             │
                ├── P0: 前方完全阻塞且<1m     │
                │     → L=255 F=255 R=255     │
                ├── P1: 阻塞但有距离           │
                │     → best-effort 方向引导   │
                ├── P2: 有安全路径但需转向     │
                │     → 角度→L/F/R权重         │
                ├── P3: 地形叠加 (台阶/坡道)  │
                ├── P4: 侧面感知               │
                ├── P5: 畅通 (全0)             │
                │                             │
                ├── EMA 平滑电机强度           │
                ├── 更新 hazardLabel 文本      │
                └── print("[HAPTIC] ...")      │
```

---

## 9. Phase 2d: Console 日志

每 0.5s（2Hz），在分析完成后额外打印：

**printGrid()** — 16×16 网格值
```
[LiDAR] 16×16 Depth Grid (p10, meters):
  [ 3.2| 2.8| 2.5| 2.1| ...| 3.5]
  [ 2.9| 2.4| 1.8| 1.5| ...| 3.1]
  ...
```

**printAnalysis()** — B2 分析结果摘要
```
[B2] flags=[SPE SPS] angle=+0.0° width=2.50m near=1.20m@+15° gY=[-1.15|-1.14|-1.12] obs=2 pitch=-10°
```

各字段含义：
- `flags`: 激活的布尔标志 (SPE=安全路径存在, SPS=直行, NSPF=无安全路径, USE=上台阶, DSE=下台阶, PUS=上坡, PDS=下坡)
- `angle`: 安全路径偏转角 (0°=正前方, +右, -左)
- `width`: 安全路径物理宽度
- `near`: 最近障碍物距离@角度
- `gY`: 三段地面 Y 高度 [近|中|远]
- `obs`: 障碍物簇数量
- `pitch`: 相机俯仰角

---

## 10. 所有函数调用关系总表

| # | 函数 | 行号 | 被谁调用 | 调用了谁 | 频率 |
|---|------|------|----------|----------|------|
| 1 | `init()` | L226 | Swift 运行时（首次访问 `.shared`） | `super.init()` | 1 次 |
| 2 | `start()` | L202 | `ViewController.viewDidLoad()` | `session.run()` | 1 次 |
| 3 | `stop()` | L221 | （未使用，保留给未来） | `session.pause()` | — |
| 4 | `session(_:didUpdate:)` | L235 | ARKit 框架（后台线程） | `buildGrid`, `analyzeHazards`, `printGrid`, `printAnalysis` | ~60Hz（5Hz 有效） |
| 5 | `buildGrid()` | L275 | #4 | `percentile10` | 5Hz |
| 6 | `percentile10()` | L330 | #5 | `kthSmallest` | 5Hz × 256 cells |
| 7 | `kthSmallest()` | L341 | #6 | 自身（递归） | 同上 |
| 8 | `printGrid()` | L370 | #4 | — | 2Hz |
| 9 | `analyzeHazards()` | L388 | #4 | #10–#18 | 5Hz |
| 10 | `projectToWorld()` | L498 | #9 (Step A) | — | 5Hz |
| 11 | `estimateBandGroundY()` | L588 | #9 (Step B) | #12 | 5Hz |
| 12 | `histogramGroundY()` | L677 | #11 | — | 5Hz × 3 bands |
| 13 | `classifyPoints()` | L710 | #9 (Step C) | — | 5Hz |
| 14 | `detectStairs()` | L751 | #9 (Step E) | — | 5Hz |
| 15 | `detectSlope()` | L818 | #9 (Step F) | — | 5Hz |
| 16 | `computeFreeSpaceMap()` | L892 | #9 (Step G) | — | 5Hz |
| 17 | `findSafePath()` | L925 | #9 (Step H) | #18 | 5Hz |
| 18 | `classifyObstacleType()` | L1110 | #17 | — | 5Hz × N obstacles |
| 19 | `applyHysteresis()` | L1153 | #9 (Step I) | — | 5Hz × 7 flags |
| 20 | `printAnalysis()` | L1177 | #4 | — | 2Hz |

---

## 11. 数据结构速查

### FrameAnalysisResult — B2 分析结果

| 字段 | 类型 | 说明 | 值范围 |
|------|------|------|--------|
| `safePathExist` | Bool | 有安全路径 | — |
| `safePathStraight` | Bool | 安全路径在正前方 | — |
| `safePathAngle` | Float | 安全路径方向 (°) | -23 ~ +23 |
| `safePathWidth` | Float | 安全路径宽度 (m) | 0.0 ~ ∞ |
| `noSafePathFound` | Bool | 无安全路径 | — |
| `pathUpSlope` | Bool | 上坡 | — |
| `pathDownSlope` | Bool | 下坡 | — |
| `upStairsExist` | Bool | 上台阶 | — |
| `downStairsExist` | Bool | 下台阶 | — |
| `nearestObstacleDistance` | Float | 最近障碍距离 (m) | 0.0 ~ 5.0 |
| `nearestObstacleAngle` | Float | 最近障碍方向 (°) | -23 ~ +23 |
| `nearestForwardDistance` | Float | 前方 ±15° 最近距离 (m) | 0.0 ~ 5.0 |
| `groundY` | Float | 近程地面 Y (m) | -2 ~ 0 |
| `bandGroundY` | [Float] | 三段地面 Y | 3 个值 |
| `obstacles` | [ObstacleCluster] | 障碍物簇列表 | 0 ~ N 个 |

### ObstacleCluster — 单个障碍物

| 字段 | 类型 | 说明 |
|------|------|------|
| `centerAngle` | Float | 中心方向 (°, 0=前, +=右, -=左) |
| `distance` | Float | 最近距离 (m) |
| `angularWidth` | Float | 角宽度 (°) |
| `physicalWidth` | Float | 物理宽度 (m) |
| `type` | ObstacleType | wall / pole / lowObstacle / dropOff / tripHazard |

---

## 12. 配置参数速查

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `analysisInterval` | 0.2s | 分析频率 (5Hz) |
| `logInterval` | 0.5s | 打印频率 (2Hz) |
| `forwardCropRatio` | 0.75 | 前方视场比例 (裁掉 25% 近地面) |
| `maxAnalysisRange` | 5.0m | 最大分析距离 |
| `minSafeDistance` | 2.0m | "安全" 最小自由距离 |
| `safeWidthConstant` | 0.8m | 最小可通行宽度 |
| `groundTolerance` | ±0.08m | 地面判定容差 |
| `tripHazardHeight` | 0.15m | 绊倒风险高度 |
| `obstacleMinHeight` | 0.15m | 障碍物最低高度 |
| `dropMildThreshold` | -0.10m | 轻微落差阈值 |
| `dropSevereThreshold` | -0.15m | 严重落差阈值 |
| `stairStepHeightMin/Max` | 0.10/0.25m | 台阶高度范围 |
| `stairMinSteps` | 3 | 最少连续台阶数 |
| `slopeAngleThreshold` | 5.0° | 坡道报告阈值 |
| `groundYAlpha` | 0.1 | 地面 Y EMA 系数 |
| `angleAlpha` | 0.3 | 角度 EMA 系数 |
| `boolHysteresisOn` | 3 帧 | 布尔激活所需连续帧数 |
| `boolHysteresisOff` | 5 帧 | 布尔关闭所需连续帧数 |

---

*Last updated: 2026-05-03*
