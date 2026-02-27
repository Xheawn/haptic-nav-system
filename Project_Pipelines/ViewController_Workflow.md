# ViewController 完整工作流程详解

> 本文档从用户打开 App 的那一刻开始，逐行追踪 `ViewController` 的初始化流程，
> 然后详细说明每个实时数据循环（GPS、指南针、LiDAR、BLE）如何持续运行并相互配合。

---

## 目录

1. [App 启动 → viewDidLoad 触发](#1-app-启动--viewdidload-触发)
2. [viewDidLoad 逐行分析](#2-viewdidload-逐行分析)
3. [实时数据循环总览](#3-实时数据循环总览)
4. [Loop A: GPS 位置更新循环](#4-loop-a-gps-位置更新循环)
5. [Loop B: 指南针航向更新循环](#5-loop-b-指南针航向更新循环)
6. [Loop C: LiDAR 深度分析循环](#6-loop-c-lidar-深度分析循环)
7. [Loop D: BLE 连接管理循环](#7-loop-d-ble-连接管理循环)
8. [用户交互: 搜索栏更新目的地](#8-用户交互-搜索栏更新目的地)
9. [用户交互: LiDAR 可视化开关](#9-用户交互-lidar-可视化开关)
10. [完整数据流图](#10-完整数据流图)

---

## 1. App 启动 → viewDidLoad 触发

### iOS App 生命周期

```
用户点击 App 图标
  │
  ├── iOS 创建进程 → 执行 main()
  ├── UIApplicationMain() 初始化 UIApplication
  ├── 加载 Main.storyboard (或 SceneDelegate)
  ├── 实例化 ViewController
  │     └── 所有 property 的默认值和闭包初始化器此时执行：
  │           ├── apiKey: 从 Secrets.plist 加载 Google Maps API Key
  │           ├── origin / destination: 设置默认起终点
  │           ├── locationManager: CLLocationManager() 创建
  │           ├── searchBar, locationLabel, headingLabel 等 UILabel: 创建并配置样式
  │           ├── lidarToggleButton: 创建蓝色圆形按钮
  │           └── hazardLabel: 创建 B2 调试标签
  │
  ├── ViewController 的 view 被加载到内存
  └── ★ viewDidLoad() 被调用 ★
```

### 什么是 viewDidLoad？

`viewDidLoad()` 是 `UIViewController` 生命周期方法，在 view 第一次被加载到内存后调用**一次**。它是做初始化设置的标准位置 — 创建 UI、启动传感器、发起网络请求等。**不是每次页面出现都调用**，只在第一次加载时调用一次。

---

## 2. viewDidLoad 逐行分析

```swift
override func viewDidLoad() {        // ← iOS 系统调用，App 启动后执行一次
    super.viewDidLoad()               // ← 调用父类实现（UIViewController 内部设置）

    setupMapView()                    // ① 初始化 Google 地图
    setupLocationManager()            // ② 启动 GPS + 指南针 → 开始 Loop A 和 Loop B
    setupLabels()                     // ③ 布局所有 UI 标签
    requestRoute(origin, destination, // ④ 发起 Directions API 请求 → 异步获取路线
                 threshold_1_radius,
                 threshold_2_width)
    BLEManager.shared.start()         // ⑤ 启动蓝牙扫描 → 开始 Loop D
    setupDepthGridUI()                // ⑥ 创建 16×16 深度网格 UI
    LiDARManager.shared.start()       // ⑦ 启动 ARSession → 开始 Loop C
    LiDARManager.shared.onGridUpdate = { [weak self] grid in
        self?.updateDepthGridUI(grid) // ⑧ 注册回调: LiDAR 网格数据 → 更新网格 UI
    }
    LiDARManager.shared.onHazardUpdate = { [weak self] analysis in
        self?.handleHazardUpdate(analysis) // ⑨ 注册回调: 危险分析结果 → 电机强度计算
    }
    setupHazardLabel()                // ⑩ 布局 B2 调试标签
    setupLidarToggle()                // ⑪ 布局 LiDAR 开关按钮 + 默认隐藏网格
}
```

下面逐个展开每一步：

---

### ① setupMapView()

```
setupMapView()
  ├── GMSServices.provideAPIKey(apiKey)    ← 激活 Google Maps SDK
  ├── GMSCameraPosition(lat, lng, zoom)    ← 设置初始相机位置 (UW 校区)
  ├── GMSMapView(options)                  ← 创建地图视图
  └── view.addSubview(mapView)             ← 添加到视图层级（最底层）
```

**结果**: 屏幕上出现 Google 地图，以 UW 为中心。

---

### ② setupLocationManager()

```
setupLocationManager()
  ├── locationManager.delegate = self         ← ViewController 成为 CLLocationManagerDelegate
  ├── locationManager.desiredAccuracy = Best  ← 请求最高精度 GPS
  ├── locationManager.requestWhenInUseAuthorization()  ← 弹出权限对话框（首次）
  ├── locationManager.startUpdatingLocation()  ← ★ 启动 Loop A: GPS 位置更新
  └── locationManager.startUpdatingHeading()   ← ★ 启动 Loop B: 指南针航向更新
```

**关键**: 这一步之后，iOS 系统会**持续**回调以下两个方法：
- `didUpdateLocations` → 约 1Hz（每秒一次）
- `didUpdateHeading` → 约 10Hz（每秒十次）

这两个回调不需要手动触发，iOS 会在后台持续调用它们。

---

### ③ setupLabels()

```
setupLabels()
  ├── view.addSubview(searchBar)              ← 搜索栏
  ├── view.addSubview(locationLabel)          ← "Current Location: ..."
  ├── view.addSubview(headingLabel)           ← "Orientation of your Phone: ..."
  ├── view.addSubview(desiredDirectionLabel)  ← "Expected Orientation: ..."
  ├── view.addSubview(angleDiffLabel)         ← "AngleDiff: ..."
  ├── view.addSubview(adjustDirectionLabel)   ← "AdjustDirection: ..."
  ├── searchBar.delegate = self               ← 搜索栏回调注册
  └── NSLayoutConstraint.activate(...)        ← Auto Layout 约束布局
```

**结果**: UI 标签叠加在地图上方，从上到下排列。

---

### ④ requestRoute(origin, destination, ...)

```
requestRoute("Maple Hall...", "CSE Building...", 4.0, 8.0)
  │
  └── GoogleMapsHelper.shared.fetchDirections(origin, destination, apiKey)
        │                                              ↑ 异步！不阻塞 UI
        ├── HTTP GET: googleapis.com/directions/json?mode=walking
        │     (此时 viewDidLoad 继续执行下面的 ⑤⑥⑦...)
        │
        ├── ...网络响应返回（约 200-500ms 后）...
        │
        └── completion(polyline)
              └── DispatchQueue.main.async {
                    self.routePoints = drawRouteOnMap(polyline, mapView, ...)
                  }
                    ├── 解码 polyline → [Point] 数组（含角度）
                    ├── 绘制蓝色路线、绿色圆、黄色平行四边形
                    └── ★ routePoints 被赋值 → Loop A 的 checkUserThresholds 开始生效
```

**关键**: 这是一个**异步**操作。`requestRoute` 立即返回，`viewDidLoad` 继续往下执行。路线数据在网络请求完成后才可用。在 `routePoints` 被赋值之前，`checkUserThresholds` 会因为 `routePoints.isEmpty` 而直接 return。

---

### ⑤ BLEManager.shared.start()

```
BLEManager.shared.start()
  └── CBCentralManager(delegate: self, queue: nil)
        └── iOS 蓝牙硬件初始化（异步）
              └── 就绪后自动回调 centralManagerDidUpdateState(.poweredOn)
                    └── startScanning()
                          └── scanForPeripherals(withServices: [kServiceUUID])
                                └── ★ 启动 Loop D: BLE 扫描/连接循环
```

**关键**: BLE 初始化也是异步的。蓝牙芯片就绪后才开始扫描。

---

### ⑥ setupDepthGridUI()

```
setupDepthGridUI()
  ├── 创建 depthGridContainer (黑色半透明背景)
  ├── 创建 16×16 = 256 个 UILabel (每个 22×22pt)
  ├── 用 Auto Layout 排列成网格
  └── 存入 depthGridLabels[][] 二维数组
```

**结果**: 16×16 深度网格 UI 创建完成（后面 ⑪ 会设为隐藏）。

---

### ⑦ LiDARManager.shared.start()

```
LiDARManager.shared.start()
  ├── 检查 supportsFrameSemantics(.sceneDepth)  ← 设备是否有 LiDAR
  ├── ARWorldTrackingConfiguration()
  │     └── .frameSemantics = .sceneDepth         ← 启用深度输出
  ├── session.delegate = self (LiDARManager)
  └── session.run(config)
        └── ★ 启动 ARSession → 开始 Loop C: 60FPS 帧回调
```

---

### ⑧⑨ 注册 LiDAR 回调

```swift
// ⑧ 网格数据回调
LiDARManager.shared.onGridUpdate = { grid in
    self?.updateDepthGridUI(grid)     // 更新 16×16 网格 UI 的颜色和数值
}

// ⑨ 危险分析回调
LiDARManager.shared.onHazardUpdate = { analysis in
    self?.handleHazardUpdate(analysis) // FrameAnalysisResult → L/F/R 电机强度
}
```

**关键**: 这只是**注册**回调闭包，不会立即执行。当 LiDARManager 在 Loop C 中完成分析后，会通过 `DispatchQueue.main.async` 调用这些闭包。

---

### ⑩⑪ setupHazardLabel() + setupLidarToggle()

```
setupHazardLabel()
  └── 将 hazardLabel 添加到 view 并约束到 angleDiffLabel 上方

setupLidarToggle()
  ├── 将 lidarToggleButton 添加到 view 右下角
  ├── 绑定 toggleLidarGrid 事件
  └── depthGridContainer.isHidden = true    ← 默认隐藏
      hazardLabel.isHidden = true           ← 默认隐藏
```

---

### viewDidLoad 完成后的状态

```
屏幕上可见:
  ┌──────────────────────────┐
  │ [搜索栏] Please Enter... │
  │ Current Location: ...    │
  │ Orientation: ...         │
  │ Expected Orientation: ...│
  │                          │
  │   ┌── Google 地图 ───┐   │
  │   │  蓝色路线         │   │
  │   │  绿色圆           │   │
  │   │  黄色平行四边形    │   │ ← 路线数据异步到达后绘制
  │   └──────────────────┘   │
  │                      [L] │ ← LiDAR 开关按钮（蓝色）
  │ B2: -- (隐藏)            │
  │ AngleDiff: --            │
  │ AdjustDirection: --      │
  └──────────────────────────┘

后台运行中的循环:
  ├── Loop A: GPS ~1Hz (已启动)
  ├── Loop B: 指南针 ~10Hz (已启动)
  ├── Loop C: LiDAR 60FPS→5Hz (已启动)
  └── Loop D: BLE 扫描中 (已启动)
```

---

## 3. 实时数据循环总览

viewDidLoad 完成后，**4 个独立的实时数据循环**同时运行，各自由 iOS 系统驱动回调：

```
┌─────────────────────────────────────────────────────────────────┐
│                    ViewController (主线程)                        │
│                                                                 │
│  Loop A: GPS ~1Hz ──→ checkUserThresholds ──→ applyAdjust ──┐  │
│  Loop B: 指南针 ~10Hz ──→ applyAdjustDirectionLogic ────────┤  │
│  Loop C: LiDAR 5Hz ──→ handleHazardUpdate ──────────────────┤  │
│                                                              ↓  │
│                                              BLE sendCommand    │
│                                                    ↓            │
│  Loop D: BLE 管理 ──→ 自动连接/重连 ──→ ESP32 电机              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Loop A: GPS 位置更新循环

**触发源**: iOS `CLLocationManager`，约 1Hz
**入口**: `didUpdateLocations`

```
iOS CLLocationManager 后台线程产生 GPS 定位
  ↓ 主线程回调
didUpdateLocations(locations)
  │
  ├── 更新 locationLabel: "Current Location: lat, lng"
  │
  └── checkUserThresholds(userCoord, outlier_threshold_distance)
        │
        ├── routePoints 为空? → return (路线未就绪)
        │
        ├── 遍历所有 routePoints:
        │     ├── 阈值1检测: distance(user, point[i]) ≤ 4m? → threshold1Indices
        │     └── 阈值2检测: isPoint(user, quad[i,i+1])? → threshold2Indices
        │
        ├── 情况 A: 在路线上 (有命中)
        │     ├── isOffRoute = false
        │     ├── maxIndex = max(所有命中 index)
        │     ├── desiredAngle = routePoints[maxIndex].angle
        │     ├── lastValidAngle = desiredAngle        ← 保存供 Loop B 使用
        │     ├── desiredDirectionLabel = "Expected Orientation: xxx°"
        │     ├── applyAdjustDirectionLogic(desiredAngle) ← 见下方 §4.1
        │     └── resetThreshold3Timer()
        │
        └── 情况 B: 偏航
              ├── isOffRoute = true
              ├── adjustDirection = 3
              ├── BLE 发送 [3, 0]
              ├── GPS outlier 检测:
              │     距离上次重规划位置 < 5m? → 判定为 GPS 漂移, return
              └── 启动 1s Timer → requestRoute(当前位置, destination)
                                    └── 新路线 → routePoints 更新
```

### §4.1 applyAdjustDirectionLogic(desiredAngle)

```
applyAdjustDirectionLogic(desiredAngle)
  │
  ├── phoneAngle = currentPhoneAngle    ← 由 Loop B 实时更新
  ├── rawAngleDiff = phoneAngle - desiredAngle
  │
  ├── |diff| ≤ 5°  → adjustDirection = 0 (无需调整)
  ├── diff > 5, ≤ 180  → adjustDirection = 2 (右转)
  ├── diff > 5, > 180  → adjustDirection = 1 (左转, 补角)
  ├── diff < -5, > -180 → adjustDirection = 1 (左转)
  ├── diff < -5, ≤ -180 → adjustDirection = 2 (右转, 补角)
  │
  ├── updateAdjustUI(adjustDirection, angleDiff)  ← 更新底部 UI
  │
  └── BLE 发送 [adjustDirection, magnitude]  (5Hz 节流)
        └── BLEManager.shared.sendCommand(Data([dir, mag]))
```

---

## 5. Loop B: 指南针航向更新循环

**触发源**: iOS `CLLocationManager`，约 10Hz
**入口**: `didUpdateHeading`

```
iOS 磁力计/陀螺仪产生航向数据
  ↓ 主线程回调
didUpdateHeading(newHeading)
  │
  ├── 坐标转换:
  │     originalHeading = trueHeading (正北=0°, 顺时针)
  │     convertedAngle = (90 - originalHeading) mod 360
  │     → 转为: 正东=0°, 逆时针为正 (与 Point.angle 坐标系一致)
  │
  ├── headingLabel = "Orientation of your Phone: xxx°"
  ├── currentPhoneAngle = convertedAngle   ← ★ 供 Loop A 的 applyAdjust 使用
  │
  ├── 不偏航 且有 lastValidAngle?
  │     └── applyAdjustDirectionLogic(lastValidAngle)  ← 用最新航向重新计算
  │           └── (同 §4.1)
  │
  └── 偏航中?
        └── updateAdjustUI(adjustDirection: 3)  ← 保持显示偏航状态
```

### Loop A 和 Loop B 的协作

```
Loop A (1Hz):  GPS位置 → checkUserThresholds → desiredAngle → lastValidAngle
                                                                    ↓
Loop B (10Hz): 手机朝向 → currentPhoneAngle → applyAdjust(lastValidAngle)
                                                    ↓
                                            adjustDirection + angleDiff
                                                    ↓
                                            BLE → ESP32 → 振动电机

Loop A 提供 "该往哪走" (desiredAngle)
Loop B 提供 "手机现在朝哪" (currentPhoneAngle)
两者配合计算 "该怎么调整" (adjustDirection)
```

---

## 6. Loop C: LiDAR 深度分析循环

**触发源**: `ARSession` 内部，60FPS
**入口**: `ARSessionDelegate.session(_:didUpdate:)`
**节流**: 5Hz (`analysisInterval = 0.2s`)

```
ARSession 后台线程采集 LiDAR 数据
  ↓ ARSessionDelegate 回调 (后台线程)
session(_:didUpdate: frame)
  │
  ├── 节流: now - lastAnalysisTime < 0.2s? → return (跳过这帧)
  │
  ├── 获取深度数据:
  │     depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
  │     depthMap = depthData.depthMap          ← CVPixelBuffer, Float32, 256×192
  │     confidenceMap = depthData.confidenceMap ← CVPixelBuffer, UInt8, 256×192
  │
  ├── B1: buildGrid(depthMap) → 16×16 grid
  │     └── 每个 cell = 对应区域深度值的 percentile-10
  │
  ├── B2: analyzeHazards(frame, depthMap, confidenceMap)
  │     ├── Step A: projectToWorld()      ← 深度像素 → 世界坐标
  │     ├── Step B: estimateBandGroundY() ← 距离分段地面估计
  │     ├── Step C: classifyPoints()      ← 高度分类
  │     ├── Step E: detectStairs()        ← 台阶检测
  │     ├── Step F: detectSlope()         ← 坡道检测
  │     ├── Step G: computeFreeSpaceMap() ← 角度自由空间
  │     ├── Step H: findSafePath()        ← 安全路径查找
  │     └── Step I: applyHysteresis()     ← 时序平滑
  │     → 输出: FrameAnalysisResult
  │
  └── DispatchQueue.main.async {           ← ★ 切到主线程
        onGridUpdate?(grid)                ← 触发 ⑧ updateDepthGridUI
        onHazardUpdate?(analysis)          ← 触发 ⑨ handleHazardUpdate
      }
```

### ⑧ updateDepthGridUI(grid)

```
updateDepthGridUI(grid)                    ← 主线程, 5Hz
  └── 遍历 16×16 grid:
        ├── label.text = "2.1" (深度值)
        └── label.backgroundColor = 红(近) → 绿(远) 渐变色
```

### ⑨ handleHazardUpdate(analysis)

```
handleHazardUpdate(analysis)               ← 主线程, 5Hz
  │
  ├── 优先级判定:
  │     ├── P0: noSafePathFound && nearestForwardDistance < 1.0m
  │     │     → rawL=255, rawF=255, rawR=255 (全亮 = 紧急停止)
  │     │
  │     ├── P1: noSafePathFound && distance ≥ 1.0m
  │     │     → 根据 best-effort gap angle 分配 L/F/R (120~200 强度)
  │     │
  │     ├── P2: safePathExist && !safePathStraight
  │     │     → 根据 safePathAngle 分配 L/F/R (80~255 强度)
  │     │
  │     ├── P4: safePathExist && safePathStraight
  │     │     → 侧面障碍物感知: 仅 L 或 R 轻振 (0~80)
  │     │
  │     └── P5: clear (无障碍)
  │           → rawL=0, rawF=0, rawR=0
  │
  ├── P3: 地形叠加 (台阶/坡道)
  │     → 在 F 电机上叠加 60~120 强度
  │
  ├── EMA 平滑: motorL/F/R = prev*(1-0.4) + raw*0.4
  │
  ├── 更新 hazardLabel (调试信息)
  │
  └── print("[HAPTIC] P2:steer +15° | L=000 F=120 R=200")
```

---

## 7. Loop D: BLE 连接管理循环

**触发源**: iOS `CBCentralManager`，事件驱动
**入口**: `BLEManager.shared.start()`

```
start()
  └── CBCentralManager(delegate, queue)
        └── (蓝牙硬件初始化，异步)

centralManagerDidUpdateState(.poweredOn)    ← 蓝牙就绪
  └── startScanning()
        └── scanForPeripherals(withServices: [kServiceUUID])

didDiscover(peripheral)                     ← 发现 ESP32
  ├── stopScan()
  └── connect(peripheral)

didConnect(peripheral)                      ← 连接成功
  └── discoverServices([kServiceUUID])

didDiscoverServices                         ← 发现服务
  └── discoverCharacteristics([kCharacteristicUUID])

didDiscoverCharacteristics                  ← 发现特征
  └── writeCharacteristic = char            ← ★ 准备就绪，可以发送数据

--- 之后 sendCommand() 可用 ---

sendCommand(Data([dir, magnitude]))         ← 由 Loop A/B 调用
  └── peripheral.writeValue(data, type: .withoutResponse)
        └── ESP32 接收 → 控制振动电机

didDisconnect(peripheral)                   ← 断连
  ├── connectedPeripheral = nil
  └── startScanning()                       ← 自动重新扫描和连接
```

### BLE 数据包格式

```
目前的协议 (Macro Navigation, 2字节):
  Byte 0: AdjustDirection (0=none, 1=left, 2=right, 3=off-route)
  Byte 1: AngleDiff magnitude (0~180)

未来协议 (Micro Navigation, 4字节, 待实现):
  Byte 0: Command type
  Byte 1: Left motor intensity (0~255)
  Byte 2: Front motor intensity (0~255)
  Byte 3: Right motor intensity (0~255)
```

---

## 8. 用户交互: 搜索栏更新目的地

```
用户在搜索栏输入 "HUB, University of Washington" → 按搜索
  ↓
searchBarSearchButtonClicked(searchBar)
  ├── destination = "HUB, University of Washington"
  ├── searchBar.resignFirstResponder()      ← 收起键盘
  ├── origin = 当前 GPS 位置 (如可用)
  └── requestRoute(origin, destination, ...)
        └── (异步) → 新的 routePoints → 地图重绘 → Loop A 使用新路线
```

---

## 9. 用户交互: LiDAR 可视化开关

```
用户点击右下角蓝色 "L" 按钮
  ↓
toggleLidarGrid()
  ├── depthGridContainer.isHidden = false   ← 显示 16×16 网格
  ├── hazardLabel.isHidden = false          ← 显示 B2 调试信息
  └── 按钮变绿色

再次点击
  ├── depthGridContainer.isHidden = true
  ├── hazardLabel.isHidden = true
  └── 按钮变蓝色
```

**注意**: 隐藏/显示只控制 UI 可见性。LiDAR 分析在后台**始终运行**，不受开关影响。

---

## 10. 完整数据流图

```
┌──────────────── 传感器层 ────────────────┐
│                                          │
│  GPS (~1Hz)   磁力计 (~10Hz)   LiDAR (60FPS→5Hz)  BLE (事件驱动)
│    │              │                │                    │
└────┼──────────────┼────────────────┼────────────────────┼──┘
     │              │                │                    │
     ↓              ↓                ↓                    ↓
┌────────────── iOS 回调层 ────────────────────────────────────┐
│                                                              │
│  didUpdateLocations  didUpdateHeading  session(didUpdate)    │
│    │                    │                │                   │
│    │                    │          ┌─────┴──────┐            │
│    │                    │          │ B1: grid   │            │
│    │                    │          │ B2: hazards│            │
│    │                    │          └─────┬──────┘            │
│    │                    │                │                   │
│    │                    │      DispatchQueue.main.async      │
│    ↓                    ↓                ↓                   │
└──────────────────────────────────────────────────────────────┘
     │                    │                │
     ↓                    ↓                ↓
┌────────────── ViewController 处理层 ─────────────────────────┐
│                                                              │
│  checkUserThresholds   (uses             handleHazardUpdate  │
│    │                currentPhoneAngle)     │                 │
│    │                    │                  │                 │
│    ├── 在路线上:        │              P0/P1/P2/P4/P5       │
│    │   desiredAngle ────┤              → rawL, rawF, rawR   │
│    │   → lastValidAngle │                  │                 │
│    │                    ↓                  │                 │
│    │            applyAdjustDirectionLogic  │                 │
│    │              │                        │                 │
│    │              ├── adjustDirection       │                 │
│    │              ├── angleDiff             │                 │
│    │              ↓                        ↓                 │
│    │          updateAdjustUI          hazardLabel.text       │
│    │              │                        │                 │
│    └── 偏航:      │                        │                 │
│        Timer →    │                        │                 │
│        requestRoute                        │                 │
│                   │                        │                 │
└───────────────────┼────────────────────────┼─────────────────┘
                    │                        │
                    ↓                        ↓ (未来合并)
┌────────────── BLE 输出层 ────────────────────────────────────┐
│                                                              │
│  Macro: [dir, magnitude]    Micro: [cmd, L, F, R] (待实现)  │
│    │                                                         │
│    ↓                                                         │
│  BLEManager.sendCommand()                                    │
│    │                                                         │
│    ↓                                                         │
│  ESP32 XIAO_S3 → 振动电机 (L / F / R)                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 时间轴示例（App 启动后前 3 秒）

```
T=0.000s  viewDidLoad 开始
T=0.001s  ① setupMapView — 地图创建
T=0.002s  ② setupLocationManager — GPS/指南针启动
T=0.003s  ③ setupLabels — UI 布局
T=0.004s  ④ requestRoute — HTTP 请求发出（异步）
T=0.005s  ⑤ BLEManager.start — 蓝牙初始化
T=0.006s  ⑥ setupDepthGridUI — 网格 UI 创建
T=0.007s  ⑦ LiDARManager.start — ARSession 启动
T=0.008s  ⑧⑨ 回调注册
T=0.009s  ⑩⑪ hazardLabel + toggle 设置
T=0.010s  viewDidLoad 完成 ← 整个过程 ~10ms

T=0.050s  BLE: centralManagerDidUpdateState(.poweredOn) → 开始扫描
T=0.100s  Loop B: 第一次 didUpdateHeading → 显示手机朝向
T=0.200s  Loop C: 第一次 LiDAR 分析 → grid + hazard 回调
T=0.300s  Loop A: 第一次 didUpdateLocations → routePoints 为空, return
T=0.400s  Loop C: 第二次 LiDAR 分析
T=0.500s  Directions API 响应返回 → routePoints 赋值 → 地图绘制
T=0.600s  Loop C: 第三次 LiDAR 分析
T=0.800s  BLE: didDiscover ESP32 → 开始连接
T=1.000s  Loop A: 第二次 GPS → checkUserThresholds → routePoints 有值!
           → 计算 desiredAngle → applyAdjust → BLE 发送
T=1.100s  BLE: didConnect → discoverServices → discoverCharacteristics → 就绪
T=1.200s  Loop C: LiDAR → handleHazardUpdate → P5:clear
T=2.000s  Loop A: 第三次 GPS → 阈值检测 → 导向更新
T=2.100s  Loop B: didUpdateHeading → applyAdjust(lastValidAngle) → BLE
...持续运行...
```

---

*Last updated: 2026-02-27*
