# 2026年2月23日 — 每日备忘录

## 今日完成工作

### 1. 全分辨率分析升级：64×48 → 192×192
B2 危险分析流水线从降采样 64×48（stride 3~4）升级为 **全 256×192 分辨率**（stride 1，配合 `forwardCropRatio=0.75` → 192×192 = 36,864 点）。

| 指标 | 旧 (64×48) | 新 (192×192) |
|------|-----------|-------------|
| 分析点数 | 3,072 | 36,864 |
| 内存 | ~50KB | ~550KB |
| 自由空间角度列数 | 48 (≈1°/列) | 192 (≈0.24°/列) |
| 5cm 柱子 @3m | 0–1 px → 漏检 | 2–3 px → 可检测 |

**核心改动：** 移除固定的 `analysisRows=64` / `analysisCols=48` 常量，改为从实际深度缓冲区尺寸动态计算。

### 2. Confidence Map 置信度过滤
引入 ARKit 逐像素置信度图（`ARDepthData.confidenceMap`）过滤不可靠的深度测量：

```swift
// ARConfidenceLevel: 0=low, 1=medium, 2=high
if let cb = confBuffer {
    let confidence = cb[by * confBytesPerRow + bx]
    guard confidence >= 1 else { continue }  // 跳过低置信度点
}
```

**影响：** 去除远距离、反射面、深度边缘的噪声点 — 减少障碍物误检，提升地面估计稳定性。

### 3. 自适应台阶/坡道扫描范围
扫描列范围现在随分辨率等比例缩放，保持一致的角度覆盖：
- **台阶：** ±10 列 @48 → `cols×10/48` = ±40 列 @192（≈±10°）
- **坡道：** ±5 列 @48 → `cols×5/48` = ±20 列 @192（≈±5°）

### 4. LiDAR 可视化开关按钮
在 App UI 右下角新增一个 44×44pt 圆形按钮 "L"，用于切换 16×16 LiDAR 深度网格和 B2 hazard label 的显示/隐藏：
- **默认隐藏**，不干扰正常导航界面
- 点击切换：蓝色（隐藏）↔ 绿色（显示）
- 同时控制 `depthGridContainer` 和 `hazardLabel` 的可见性

### 5. Google Maps 导航逻辑文档
创建 `GoogleMaps_Navigation_Pipeline.md`，完整记录宏观导航（Macro Navigation）的 8 个 Stage：
- **Stage 1**: Directions API 路线请求（`mode=walking`）
- **Stage 2**: Polyline 解码 → `Point[]` 路径点数组（含角度）
- **Stage 3**: 地图可视化（蓝色路线 + 绿色阈值1圆 + 黄色阈值2平行四边形）
- **Stage 4**: GPS 实时阈值检测（圆形 + 四边形两层判定，`maxIndex` 取最远匹配点）
- **Stage 5**: 偏航处理 + GPS outlier 过滤 + 自动重规划
- **Stage 6**: AngleDiff / AdjustDirection 计算（手机朝向 vs 期望朝向）
- **Stage 7**: BLE 2 字节协议 `[dir, magnitude]`，5Hz 节流
- **Stage 8**: 搜索栏动态更新目的地
- 包含 Macro vs Micro 导航对比表

### 6. 端到端时序管线文档
在 `B1_B2_Pipeline.md` 中补充了完整的 LiDAR → 触觉反馈时序链路：
- ARKit 60FPS → 5Hz 节流 → B1/B2 处理 (~15ms) → BLE 传输 (~10ms) → 电机响应 (~5ms)
- 总延迟约 **230ms**（一个分析周期 200ms + 处理 + 传输）
- P0-P5 优先级编码方案详解

### 7. ESP32 电机诊断
- 创建 `esp32_s3_test/motor_test/motor_test.ino` 测试草图
- 修复 ESP32 Arduino Core v3.x API 变更（`ledcSetup` → `ledcAttach`）
- 发现 D5/D8 引脚的电机不振动，创建全引脚扫描测试（D0-D10 逐个 `digitalWrite HIGH`）
- **结论：** 疑似焊接问题，待硬件排查

### 8. 导航阈值逻辑分析
详细分析了 6 种用户位置场景下的阈值判定行为：

| 场景 | 命中 indices | maxIndex | 导向 |
|------|-------------|----------|------|
| t1p1 + t2p1 | [0,0] | 0 | p1→p2 |
| 仅 t2p1 | [0] | 0 | p1→p2 |
| 都不在 | [] | — | 偏航重规划 |
| t1p1+t1p2+t1p3 | [0,1,2] | 2 | p3→p4（⚠️ 可能跳过中间段） |
| t1p1+t2p1+t2p2 | [0,0,1] | 1 | p2→p3 |
| t2p1+t2p2 | [0,1] | 1 | p2→p3 |

**发现问题**：当 `threshold_1_radius` 较大时，场景 4 会导致 `maxIndex` 跳太远。目前 4m 半径下影响较小。

## 修改的文件
| 文件 | 操作 |
|------|------|
| `Controllers/ViewController.swift` | LiDAR 可视化开关按钮（`lidarToggleButton` + `setupLidarToggle` + `toggleLidarGrid`） |
| `Controllers/LiDARManager.swift` | 全分辨率升级、置信度过滤、自适应扫描范围 |
| `B1_B2_Pipeline.md` | 端到端时序管线、P0-P5 优先级编码 |
| `GoogleMaps_Navigation_Pipeline.md` | **新建** — 宏观导航完整逻辑文档 |
| `esp32_s3_test/motor_test/motor_test.ino` | **新建** — ESP32 电机诊断 + 全引脚扫描 |

## 问题记录
| # | 描述 | 状态 |
|---|------|------|
| 10 | 64×48 分辨率太低，小障碍物（柱子、路沿）漏检 | ✅ 已修复（全分辨率） |
| 11 | 无置信度过滤 — 远距离/边缘噪声点干扰 | ✅ 已修复 |
| 12 | 台阶/坡道扫描范围是固定列数而非角度 | ✅ 已修复 |
| 13 | ESP32 D5/D8 电机不振动 | 🔄 疑似焊接问题，待排查 |
| 14 | `maxIndex` 策略在大 t1 半径时可能跳过中间路段 | 📋 已记录，暂不影响 (r=4m) |

## 下一步
- **ESP32 电机焊接排查**（用引脚扫描测试确认硬件问题）
- **真机测试**全分辨率分析（验证小障碍物检测、性能/发热）
- **Step 3：** 仲裁层 — 融合 macro（Google Maps 方向）+ micro（LiDAR 危险信息）
- **Step 4：** ESP32 协议升级（4 字节包）+ 3 电机 PWM
