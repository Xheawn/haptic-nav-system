# B1 / B2 流水线使用的 Apple API、库与函数完整参考

> 本文档列出 `LiDARManager.swift` 中 B1（16×16 深度网格）和 B2（危险分析管线）所使用的
> 全部 Apple 框架、类、协议、属性和函数，及其在代码中的具体用途。

---

## 目录

1. [ARKit 框架](#1-arkit-框架)
2. [CoreVideo 框架 (CVPixelBuffer)](#2-corevideo-框架-cvpixelbuffer)
3. [simd 框架](#3-simd-框架)
4. [Foundation 框架](#4-foundation-框架)
5. [Swift 标准库](#5-swift-标准库)
6. [API 调用流程图](#6-api-调用流程图)

---

## 1. ARKit 框架

```swift
import ARKit
```

ARKit 是整个 B1/B2 管线的数据源头，提供 LiDAR 深度图、相机位姿和置信度信息。

### 1.1 ARSession

| API | 用途 |
|-----|------|
| `ARSession()` | 创建 AR 会话实例，管理 LiDAR 传感器的生命周期 |
| `session.delegate = self` | 设置委托，接收逐帧回调 |
| `session.run(config)` | 启动 AR 会话，开始采集 LiDAR 数据 |
| `session.pause()` | 暂停 AR 会话，停止 LiDAR 采集 |

**代码位置**: `LiDARManager.start()` / `stop()`

### 1.2 ARSessionDelegate 协议

| API | 用途 |
|-----|------|
| `func session(_ session: ARSession, didUpdate frame: ARFrame)` | 每帧回调（~60FPS），是 B1/B2 分析的入口。代码中对其进行 5Hz 节流后执行分析 |

**代码位置**: `extension LiDARManager: ARSessionDelegate`

### 1.3 ARWorldTrackingConfiguration

| API | 用途 |
|-----|------|
| `ARWorldTrackingConfiguration()` | 创建 6DOF 世界跟踪配置（利用 LiDAR + IMU + 视觉惯性里程计） |
| `.supportsFrameSemantics(.sceneDepth)` | **静态方法**：检查设备是否支持 LiDAR 深度（iPhone 12 Pro / iPad Pro 以上） |
| `.frameSemantics = .sceneDepth` | 启用逐帧场景深度输出（LiDAR 深度图） |

**代码位置**: `LiDARManager.start()`

### 1.4 ARFrame

每帧由 `ARSession` 回调传入，包含该时刻所有传感器数据。

| 属性 | 类型 | 用途 |
|------|------|------|
| `frame.timestamp` | `TimeInterval` | 帧时间戳，用于 5Hz 节流（`analysisInterval`）和 2Hz 日志节流 |
| `frame.camera` | `ARCamera` | 获取相机内参和位姿（见下方 1.5） |
| `frame.smoothedSceneDepth` | `ARDepthData?` | **首选**：时序平滑后的 LiDAR 深度数据（Apple 内部卡尔曼滤波） |
| `frame.sceneDepth` | `ARDepthData?` | **后备**：原始 LiDAR 深度数据（当 smoothed 不可用时） |
| `frame.capturedImage` | `CVPixelBuffer` | RGB 图像缓冲区，仅用于获取其分辨率以计算内参缩放比 |

**代码位置**: `analyzeHazards(frame:depthMap:confidenceMap:)`

### 1.5 ARCamera

| 属性 | 类型 | 用途 |
|------|------|------|
| `camera.transform` | `simd_float4x4` | 相机在世界坐标系中的 6DOF 位姿矩阵。用于：(1) 深度像素反投影到世界坐标；(2) 提取相机位置 `columns.3`；(3) 提取相机前向量 `columns.2` 计算 pitch |
| `camera.intrinsics` | `simd_float3x3` | 相机内参矩阵（针对 `capturedImage` 分辨率）。包含 fx, fy, cx, cy。代码中按深度图/RGB 分辨率比进行缩放后用于反投影 |

**代码位置**: `analyzeHazards()` Step A

#### transform 矩阵结构

```
camera.transform = simd_float4x4:
  columns.0 = [right.x, right.y, right.z, 0]    ← X 轴（右）
  columns.1 = [up.x,    up.y,    up.z,    0]    ← Y 轴（上）
  columns.2 = [fwd.x,   fwd.y,   fwd.z,   0]    ← -Z 轴（前向取反）
  columns.3 = [tx,      ty,      tz,      1]    ← 相机世界位置
```

#### intrinsics 矩阵结构

```
camera.intrinsics = simd_float3x3:
  [fx,  0,  0]
  [ 0, fy,  0]
  [cx, cy,  1]

  fx, fy = 焦距（像素单位）
  cx, cy = 主点偏移（像素单位）
```

### 1.6 ARDepthData

由 `frame.smoothedSceneDepth` 或 `frame.sceneDepth` 返回。

| 属性 | 类型 | 用途 |
|------|------|------|
| `depthData.depthMap` | `CVPixelBuffer` | LiDAR 深度图，格式 `Float32`，分辨率 256×192。每个像素 = 到相机的距离（米） |
| `depthData.confidenceMap` | `CVPixelBuffer?` | 逐像素置信度图，格式 `UInt8`，分辨率 256×192。值：0=low, 1=medium, 2=high |

**B1 用途**: `depthMap` → `buildGrid()` → 16×16 网格
**B2 用途**: `depthMap` + `confidenceMap` → `projectToWorld()` → 世界坐标点云

### 1.7 ARConfidenceLevel

| 值 | 含义 | 代码中的处理 |
|----|------|-------------|
| 0 (low) | 低置信度（远距离/反射面/边缘） | `guard confidence >= 1 else { continue }` → 跳过 |
| 1 (medium) | 中置信度 | 保留 |
| 2 (high) | 高置信度 | 保留 |

**代码位置**: `projectToWorld()` 中的置信度过滤

---

## 2. CoreVideo 框架 (CVPixelBuffer)

CoreVideo 不需要单独 import，通过 ARKit 间接引入。用于直接操作 LiDAR 深度图和置信度图的原始内存。

### 2.1 缓冲区元信息函数

| 函数 | 返回类型 | 用途 |
|------|----------|------|
| `CVPixelBufferGetWidth(depthMap)` | `Int` | 获取深度图宽度（256） |
| `CVPixelBufferGetHeight(depthMap)` | `Int` | 获取深度图高度（192） |
| `CVPixelBufferGetBytesPerRow(depthMap)` | `Int` | 每行字节数，用于计算 `floatsPerRow`。注意：可能因内存对齐而 > width × sizeof(Float) |

**B1 用途**: `buildGrid()` 中获取缓冲区尺寸和内存布局
**B2 用途**: `projectToWorld()` 中获取深度图和置信度图尺寸

### 2.2 缓冲区内存锁定

| 函数 | 用途 |
|------|------|
| `CVPixelBufferLockBaseAddress(depthMap, .readOnly)` | 锁定像素缓冲区基地址，允许 CPU 读取。**必须在读取前调用** |
| `CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)` | 解锁缓冲区。代码中用 `defer` 确保即使异常退出也能解锁 |
| `CVPixelBufferLockFlags.readOnly` | 只读锁标志，允许 GPU 同时写入 |

**代码位置**: `buildGrid()` 和 `projectToWorld()` 开头的 lock/defer-unlock 模式

### 2.3 缓冲区数据访问

| 函数 | 返回类型 | 用途 |
|------|----------|------|
| `CVPixelBufferGetBaseAddress(depthMap)` | `UnsafeMutableRawPointer?` | 获取缓冲区原始内存指针。返回 nil 表示锁定失败 |

**后续操作**:
```swift
// 深度图：Float32 每像素
let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
let d = floatBuffer[by * floatsPerRow + bx]  // 读取像素 (bx, by) 的深度值

// 置信度图：UInt8 每像素
let confBuffer = confBase.assumingMemoryBound(to: UInt8.self)
let confidence = confBuffer[by * confBytesPerRow + bx]  // 读取置信度
```

### 2.4 像素寻址公式

```
深度值 = floatBuffer[by * floatsPerRow + bx]
  其中 floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

置信度 = confBuffer[by * confBytesPerRow + bx]
```

**注意**: 使用 `bytesPerRow` 而非 `width` 是因为 Apple 的 CVPixelBuffer 可能有行尾 padding。

---

## 3. simd 框架

```swift
import simd
```

Apple 的 SIMD（Single Instruction Multiple Data）数学库，用于向量和矩阵运算。所有 3D 坐标计算都基于此。

### 3.1 向量类型

| 类型 | 用途 |
|------|------|
| `simd_float3` | 3D 向量 (x, y, z)。用于：世界坐标点 `worldPoints[r][c]`、相机位置 `camPos`、相机前向量 `fwd` |
| `simd_float4` | 4D 齐次坐标 (x, y, z, w)。用于：相机坐标点转世界坐标时的矩阵乘法输入 `simd_float4(x_cam, y_cam, z_cam, 1.0)` |

### 3.2 矩阵类型

| 类型 | 用途 |
|------|------|
| `simd_float3x3` | 3×3 矩阵。用于 `camera.intrinsics`（相机内参）和缩放后的 `scaledIntrinsics` |
| `simd_float4x4` | 4×4 矩阵。用于 `camera.transform`（相机位姿），完成相机坐标→世界坐标的变换 |

### 3.3 矩阵运算

| 操作 | 代码示例 | 用途 |
|------|---------|------|
| 矩阵 × 向量 | `let wp = transform * camPoint` | 将相机坐标系下的 3D 点变换到世界坐标系 |
| 列访问 | `transform.columns.2` | 提取旋转矩阵的 Z 列（相机前向） |
| 列访问 | `transform.columns.3` | 提取平移列（相机世界位置） |
| 元素访问 | `scaledIntrinsics[0][0]` (fx) | 读取/修改内参矩阵的焦距和主点 |

### 3.4 坐标变换完整流程

```
像素 (bx, by) + 深度 d
  ↓ 反投影 (使用 intrinsics: fx, fy, cx, cy)
相机坐标 (x_cam, y_cam, z_cam)
  ↓ 齐次化
simd_float4(x_cam, y_cam, z_cam, 1.0)
  ↓ transform * camPoint (使用 ARCamera.transform)
世界坐标 simd_float3(wp.x, wp.y, wp.z)
```

反投影公式：
```swift
x_cam =  d * (bx - cx) / fx
y_cam = -d * (by - cy) / fy   // Y 翻转（图像Y ↓ vs 相机Y ↑）
z_cam = -d                      // 深度沿 -Z 方向
```

---

## 4. Foundation 框架

```swift
import Foundation
```

### 4.1 基础类

| API | 用途 |
|-----|------|
| `NSObject` | `LiDARManager` 的基类，因为 `ARSessionDelegate` 需要 `NSObjectProtocol` |
| `TimeInterval` (= `Double`) | 帧时间戳类型，用于 5Hz/2Hz 节流计算 |

### 4.2 GCD (Grand Central Dispatch)

| API | 用途 |
|-----|------|
| `DispatchQueue.main.async { ... }` | 将 UI 回调（`onGridUpdate` / `onHazardUpdate`）调度到主线程执行。ARSessionDelegate 回调在后台线程，UI 更新必须在主线程 |

**代码位置**: `session(_:didUpdate:)` 中通知 ViewController

---

## 5. Swift 标准库

### 5.1 内存操作

| API | 用途 |
|-----|------|
| `MemoryLayout<Float32>.size` | 获取 Float32 的字节大小（4），用于计算 `floatsPerRow = bytesPerRow / 4` |
| `UnsafeMutableRawPointer` | `CVPixelBufferGetBaseAddress` 的返回类型 |
| `UnsafeMutablePointer<Float32>` | 深度图原始内存指针 |
| `UnsafeMutablePointer<UInt8>` | 置信度图原始内存指针 |
| `.assumingMemoryBound(to: Float32.self)` | 将 `UnsafeMutableRawPointer` 转换为特定类型指针，避免逐字节读取 |
| `.assumingMemoryBound(to: UInt8.self)` | 同上，用于置信度图 |

### 5.2 数学函数

| 函数 | 用途 |
|------|------|
| `sqrtf(_:)` | 计算水平距离 `hdist = sqrt(dx² + dz²)` — 用于距离分段、台阶检测、坡道检测、自由空间距离 |
| `asin(_:)` | 从前向量 Y 分量计算相机 pitch 角：`pitch = asin(fwd.y) × 180/π` |
| `atan(_:)` | 从线性回归斜率计算坡道角度：`slopeAngle = atan(a) × 180/π` |
| `tan(_:)` | 角宽度→物理宽度换算：`width = 2 × dist × tan(angWidth/2)` |
| `abs(_:)` | 取绝对值 — 用于 pitch 变化、地面 Y 跳变、斜率分母检查等 |
| `min(_:_:)` | 取最小值 — 用于距离取最近值、数组下标保护 |
| `max(_:_:)` | 取最大值 — 用于参数下限保护、列数计算 |
| `Float.pi` | π 常量，用于弧度/角度转换 |
| `Float.greatestFiniteMagnitude` | 最大有限浮点值，用作深度网格和距离的初始值（"无穷远"占位符） |
| `Float.isNaN` | 检查深度值是否为 NaN（无效测量） |
| `Float.isInfinite` | 检查深度值是否为无穷（传感器失败） |

### 5.3 数组操作

| API | 用途 |
|-----|------|
| `Array(repeating:count:)` | 创建固定大小的 2D 数组（网格、分类矩阵、世界坐标矩阵等） |
| `.reserveCapacity(_:)` | 预分配数组内存，避免 `append` 时反复扩容（B1 网格、B2 距离带） |
| `.append(_:)` | 动态添加元素（深度值、Y 值、步级差异等） |
| `.reduce(0, +)` | 求和 — 用于线性回归的 ΣX, ΣY |
| `.filter { ... }` | 过滤 — 筛选可通行走廊（`physicalWidth >= safeWidthConstant`） |
| `.map { ... }` | 映射 — 网格打印格式化 |
| `.sort { ... }` | 原地排序 — 台阶检测中按距离排序 |
| `.sorted { ... }` | 返回排序后的副本 — 走廊选择排序 |
| `.swapAt(_:_:)` | 元素交换 — Quickselect 算法中的分区操作 |
| `.min()` / `.max()` | 数组最小/最大值 — 直方图范围、距离跨度 |
| `.count` | 元素数量 |
| `.isEmpty` | 空检查 |
| `.first` | 取第一个元素 |
| `.joined(separator:)` | 字符串数组拼接 — 日志输出 |
| `.removeFirst()` | 移除首元素 — `poseHistory` 滑动窗口（保持最近 10 帧） |

### 5.4 格式化与输出

| API | 用途 |
|-----|------|
| `String(format:_:)` | C 风格格式化（`%.1f`, `%+.0f°` 等）— 网格打印、分析日志 |
| `print(_:)` | 控制台输出 — 调试日志 |

---

## 6. API 调用流程图

### B1: 16×16 深度网格

```
ARSessionDelegate.session(_:didUpdate:)
  │
  ├── ARFrame.timestamp                    ← 节流判断
  ├── ARFrame.smoothedSceneDepth           ← 获取深度数据
  │     └── ARDepthData.depthMap           ← CVPixelBuffer (Float32, 256×192)
  │
  └── buildGrid(from: depthMap)
        ├── CVPixelBufferLockBaseAddress()
        ├── CVPixelBufferGetWidth()         → 256
        ├── CVPixelBufferGetHeight()        → 192
        ├── CVPixelBufferGetBaseAddress()   → UnsafeMutableRawPointer
        ├── .assumingMemoryBound(to: Float32.self)
        ├── CVPixelBufferGetBytesPerRow()   → floatsPerRow
        ├── floatBuffer[by * floatsPerRow + bx]  ← 逐像素读取深度
        ├── Quickselect (percentile-10)     ← Swift Array + swapAt
        └── CVPixelBufferUnlockBaseAddress()  (defer)
```

### B2: 危险分析管线

```
ARSessionDelegate.session(_:didUpdate:)
  │
  ├── ARFrame.camera.transform             ← simd_float4x4 位姿
  ├── ARFrame.camera.intrinsics            ← simd_float3x3 内参
  ├── ARFrame.capturedImage                ← CVPixelBufferGetWidth/Height (缩放比)
  ├── ARDepthData.depthMap                 ← CVPixelBuffer (Float32)
  ├── ARDepthData.confidenceMap            ← CVPixelBuffer (UInt8)
  │
  ├── Step A: projectToWorld()
  │     ├── CVPixelBufferLock/Unlock (depthMap + confidenceMap)
  │     ├── CVPixelBufferGetBaseAddress → assumingMemoryBound
  │     ├── 置信度过滤: confBuffer[...] >= 1
  │     ├── 反投影: intrinsics (fx, fy, cx, cy)
  │     ├── simd_float4(x_cam, y_cam, z_cam, 1.0)
  │     └── transform * camPoint → simd_float3 世界坐标
  │
  ├── Step B: estimateBandGroundY()
  │     ├── simd_float3 算术 (dx, dz 距离计算)
  │     └── 直方图 + EMA 平滑 (Swift 标准库数组操作)
  │
  ├── Step C: classifyPoints()
  │     └── simd_float3 高度差计算 (pt.y - bandGroundY[band])
  │
  ├── Step E: detectStairs()
  │     ├── sqrtf() 距离计算
  │     └── Array.sort() 距离排序
  │
  ├── Step F: detectSlope()
  │     ├── sqrtf() 距离计算
  │     ├── 线性回归 (reduce, 手动累加)
  │     └── atan() 斜率→角度
  │
  ├── Step G: computeFreeSpaceMap()
  │     └── sqrtf() + min() 逐列最近障碍距离
  │
  ├── Step H: findSafePath()
  │     ├── tan() 角宽度→物理宽度
  │     ├── Array.filter() 筛选可通行走廊
  │     └── Array.sorted() 走廊评分排序
  │
  ├── Step I: applyHysteresis()
  │     └── Dictionary 计数器 (Swift 标准库)
  │
  └── DispatchQueue.main.async { onGridUpdate / onHazardUpdate }
```

---

## 附录：各步骤 Apple API 依赖汇总

| 步骤 | ARKit | CoreVideo | simd | Foundation | Swift Stdlib |
|------|-------|-----------|------|------------|-------------|
| 帧获取 + 节流 | ARSession, ARSessionDelegate, ARFrame.timestamp | — | — | TimeInterval | — |
| 深度数据获取 | ARFrame.smoothedSceneDepth, ARDepthData.depthMap/.confidenceMap | — | — | — | — |
| 相机位姿获取 | ARCamera.transform, ARCamera.intrinsics | — | simd_float4x4, simd_float3x3 | — | — |
| B1 网格构建 | — | CVPixelBufferLock/Unlock/GetBaseAddress/GetWidth/GetHeight/GetBytesPerRow | — | — | assumingMemoryBound, MemoryLayout, Array, swapAt |
| B2-A 世界投影 | — | CVPixelBufferLock/Unlock/GetBaseAddress (×2: depth+conf) | simd_float3, simd_float4, 矩阵乘法 | — | assumingMemoryBound, Float.isNaN/isInfinite |
| B2-B 地面估计 | — | — | simd_float3 (点坐标) | — | Array, min/max, 直方图 |
| B2-C 高度分类 | — | — | simd_float3 (高度差) | — | — |
| B2-E 台阶检测 | — | — | simd_float3 | — | sqrtf, Array.sort, filter |
| B2-F 坡道检测 | — | — | simd_float3 | — | sqrtf, atan, reduce |
| B2-G 自由空间 | — | — | simd_float3 | — | sqrtf, min |
| B2-H 路径查找 | — | — | — | — | tan, filter, sorted, Float.pi |
| B2-I 时序平滑 | — | — | — | — | Dictionary, abs |
| UI 通知 | — | — | — | DispatchQueue.main.async | — |

---

*Last updated: 2026-02-27*
