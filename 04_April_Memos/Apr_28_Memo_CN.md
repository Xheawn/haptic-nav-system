# 2026年4月28日 — 每日备忘录

## 今日完成工作

### 1. 更新 ESP32 电机测试文件
更新了 `esp32_s3_test/motor_test/motor_test.ino`，当前为 XIAO ESP32-S3 全引脚扫描测试：
- 逐个测试 D0–D10（共 11 个 GPIO 引脚），每个引脚 `digitalWrite(HIGH)` 持续 800ms
- 通过 Serial Monitor 观察哪个引脚能驱动电机振动
- 用于确认实际可用的 GPIO 引脚，解决之前 D5/D8 电机不振动的问题

### 2. 第一版 3 振动电机 Working Prototype 🎉
成功搭建了第一版包含 3 个振动电机模块的硬件原型：
- **Left / Front / Right** 三路电机均可正常工作
- 通过引脚扫描测试确认了可用的 GPIO 引脚
- 之前 Issue #13（D5/D8 电机不振动）已通过硬件调试解决

### 3. 创建 4 月 Memos 目录
新建 `04_April_Memos/` 路径，延续之前 `02_Feb_Memos/` 和 `03_March_Memos/` 的组织结构。

### 4. 项目进度总结（2月–3月回顾）

以下是对之前所有工作的阶段性总结：

#### Phase A: BLE 蓝牙通信 ✅（2/17 完成）
- ESP32 BLE Server（`esp32_s3_test.ino`）：设备名 `XIAO_ESP32S3`，自定义 Service/Characteristic UUID
- iOS BLE Central（`BLEManager.swift`）：扫描→连接→发现服务→`sendCommand()`，断连自动重连
- 2 字节协议：`[AdjustDirection, AngleDiffMagnitude]`，5Hz 节流
- 端到端验证通过：iPhone 实时发送，ESP32 Serial Monitor 确认接收

#### Phase B1: LiDAR 16×16 深度网格 ✅（2/18 完成）
- `LiDARManager.swift`：ARKit `smoothedSceneDepth` → 256×192 深度图 → 16×16 网格
- 每格 Quickselect O(n) 计算第10百分位深度
- `forwardCropRatio=0.75` 裁掉底部 25% 近地面区域
- 分析频率 5Hz，控制台打印 2Hz
- UI：16×16 彩色网格 + HSB 连续渐变（红→绿）

#### Phase B2: 危险分析管线 ✅（2/19 完成，2/22–2/23 修复+升级）
- **Step A**: 深度→世界坐标（`camera.transform` + `camera.intrinsics` 反投影）
- **Step B**: 距离分段地面 Y 估计（3 段直方图峰值 + EMA + pose-aware 动态 alpha）
- **Step C**: 高度分类（8 级：invalid/ground/tripHazard/obstacleLow/Mid/High/dropMild/Severe）
- **Step E**: 台阶检测（中央 ±10° 内 worldY 阶梯模式，≥3 级）
- **Step F**: 坡道检测（地面点线性回归 + R²>0.5 + 距离跨度≥1m）
- **Step G**: 192 列角度自由空间图
- **Step H**: 安全路径寻找（物理宽度 ≥ 0.8m，优先正前方）
- **Step I**: 时序平滑（布尔滞后 3on/5off，EMA 角度/距离）
- **Bug 修复**（2/22）：`projectToWorld` 相机坐标符号 + 距离参考点从世界原点改为相机位置
- **升级**（2/23）：64×48 → 192×192 全分辨率 + 置信度过滤 + 自适应扫描范围

#### P0-P5 触觉编码 ✅（2/19 完成，2/23 优化）
- P0: 紧急停止（前方 ±15° 完全阻塞且 <1m → L/F/R 全 255）
- P1: 受阻但有距离（best-effort gap 方向引导，强度 120~200）
- P2: 转向引导（safePathAngle → L/F/R 权重插值，强度 80~255）
- P3: 地形叠加（台阶 F≥120，坡道 F≥60）
- P4: 两侧感知（L/R ≤80，正前方畅通）
- P5: 畅通（全 0）

#### Macro Navigation (Google Maps) ✅（之前已完成 Stage 1-8）
- Stage 1-3: Directions API → Polyline 解码 → 地图可视化
- Stage 4: 实时 GPS 阈值检测（圆形 t1 + 四边形 t2，`maxIndex` 取最远匹配点）
- Stage 5: 偏航处理 + GPS outlier 过滤 + 自动重规划（1s 延迟）
- Stage 6-7: AngleDiff/AdjustDirection 计算 → BLE 2 字节发送
- Stage 8: 搜索栏动态更新目的地

#### 文档体系 ✅
- `Project_Pipelines/B1_B2_Pipeline.md` — LiDAR 分析管线 + 端到端时序
- `Project_Pipelines/GoogleMaps_Navigation_Pipeline.md` — 宏观导航 8 Stage
- `Project_Pipelines/Apple_APIs_Reference.md` — B1/B2 使用的全部 Apple API
- `Project_Pipelines/ViewController_Workflow.md` — App 启动到实时运行工作流

### 当前状态与待办

| 模块 | 状态 |
|------|------|
| BLE 通信 (Phase A) | ✅ 完成 |
| LiDAR 网格 (B1) | ✅ 完成 |
| 危险分析 (B2) | ✅ 完成 |
| P0-P5 触觉编码 | ✅ 完成 |
| Macro Navigation | ✅ 完成 |
| 3 电机硬件原型 | ✅ **今日完成** |
| ESP32 电机引脚确认 | ✅ **今日完成** |
| 仲裁层（Macro + Micro 融合） | 🔲 待开发 |
| ESP32 协议升级（4 字节包 [cmd,L,F,R]） | 🔲 待开发 |
| ESP32 3 电机 PWM 控制 | 🔲 待开发 |
| 真机端到端测试 | 🔲 待进行 |

## 修改/创建的文件

| 文件 | 操作 |
|------|------|
| `esp32_s3_test/motor_test/motor_test.ino` | 更新（引脚扫描测试） |
| `04_April_Memos/Apr_28_Memo_CN.md` | **新建** — 本日备忘录（中文） |
| `04_April_Memos/Apr_28_Memo.md` | **新建** — 本日备忘录（英文） |

## 问题记录

| # | 描述 | 状态 |
|---|------|------|
| 13 | ESP32 D5/D8 电机不振动 | ✅ 已解决（硬件调试 + 引脚扫描确认） |
| 14 | `maxIndex` 策略在大 t1 半径时可能跳过中间路段 | 📋 已记录，暂不影响 (r=4m) |

## 下一步
- **ESP32 协议升级**：从 2 字节 `[dir, magnitude]` 扩展为 4 字节 `[cmd, L, F, R]`
- **ESP32 3 电机 PWM 控制**：根据 BLE 接收的 L/F/R 强度驱动 3 个电机
- **仲裁层**：融合 Macro（Google Maps 方向）+ Micro（LiDAR P0-P5）导航指令
- **真机端到端测试**：iPhone LiDAR → BLE → ESP32 → 3 电机振动反馈
