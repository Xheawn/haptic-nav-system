# Arbitration Layer Plan

> 宏观导航 (Google Maps) + 微观导航 (LiDAR) → 统一触觉输出
>
> 最后更新：2026-05-13

---

## 设计核心：两种不同触感

| | Micro (LiDAR 避障) | Macro (Google Maps 导航) |
|---|---|---|
| **触感** | 脉冲震动（嗡-停-嗡-停） | 持续震动（嗡————） |
| **含义** | "这里有障碍物" | "你需要转向" |
| **强度/频率** | 距离近 → 脉冲快；距离远 → 脉冲慢 | 角度大 → 强度高；角度小 → 强度低 |
| **ESP32 cmd** | `0x01` → 脉冲模式 | `0x02` → 持续模式 |
| **优先级** | **高** | 低 |
| **更新频率** | 10Hz (LiDAR) | ~1Hz (GPS/Compass) |

用户可以通过触感本身分辨信号来源：
- 感到间歇脉冲 → 附近有障碍物，注意安全
- 感到持续震动 → 导航在指路，需要转弯

---

## System 1: Micro 避障（✅ 已实现）

```
LiDAR (10Hz)
  → analyzeHazards() → FrameAnalysisResult
  → handleHazardUpdate() → P0-P5 → urgency L/F/R (0-255)
  → BLE [0x01, L, F, R]
  → ESP32 脉冲模式: 100ms on / (0-500ms) off
```

| 场景 | 电机 | urgency | 触感 |
|------|------|---------|------|
| P0: 前方<1m完全阻塞 | L+F+R = 255 | 常亮不停 | 嗡———— |
| P1: 阻塞但有距离 | 方向电机 = f(距离) | 快脉冲 | 嗡-嗡-嗡- |
| P2: 需转向避障 | 方向电机 = f(距离) | 中脉冲 | 嗡--嗡--嗡-- |
| P4: 侧面有障碍 | 侧面电机 = f(距离) | 慢-中脉冲 | 嗡----嗡---- |
| P5: 畅通 | 全部 0 | 无 | （静默） |

---

## System 2: Macro 导航（待实现）

### 逻辑

用户手机朝向 (phoneAngle) 与目标方向 (expectedAngle) 的偏差 → 反方向电机持续震动 → 引导用户转正。

```
GPS/Compass (~1Hz)
  → applyAdjustDirectionLogic()
  → adjustDirection (0/1/2/3) + angleDiff (0-180°)
  → 转换为 macroL / macroF / macroR (0-255)
  → 缓存（不直接发 BLE，等仲裁层统一发送）
```

### 方向 → 电机映射

| adjustDirection | 含义 | 电机 | 强度 | 逻辑 |
|---|---|---|---|---|
| 0 (直行, <5°) | 方向正确 | 全部 0 | 无震动 | — |
| 1 (需左转) | 手机偏右了 | **R** 电机持续震 | angleDiff → 70-255 | "右边偏了" → 震右 |
| 2 (需右转) | 手机偏左了 | **L** 电机持续震 | angleDiff → 70-255 | "左边偏了" → 震左 |
| 3 (偏航重规划) | 走错路了 | **F** 电机持续震 | 固定 80 | "前方有问题" |

### angleDiff → 强度映射

```
angleDiff ≤ 5°   → 0 (不震)
angleDiff = 10°  → 70 (最低感知)
angleDiff = 90°  → ~160 (中等)
angleDiff ≥ 180° → 255 (最强)
线性插值: intensity = 70 + (angleDiff - 5) / 175 × 185
```

用户体验：手机转向正确方向时 angleDiff 减小 → 震动减弱 → 直到 <5° 停止震动。

### 独立测试

关闭 LiDAR（或手遮住 LiDAR 传感器），仅测试 macro 导航：
1. 设定目标方向
2. 转动手机偏离 → 应该感到持续震动
3. 偏离越大 → 震动越强
4. 转回正确方向 → 震动减弱至消失

---

## System 3: 仲裁层（待实现）

### 原则

```
安全优先：LiDAR (micro) > Google Maps (macro)
LiDAR 说"停" → 一定停，无论 Google 说什么
LiDAR 说"安全" → 才听 Google 的方向指引
```

### 优先级矩阵

| LiDAR 状态 | Macro 状态 | 发送的 cmd | 电机值 |
|---|---|---|---|
| **P0** (紧急停止) | 任何 | `0x01` 脉冲 | LiDAR 值 |
| **P1** (阻塞) | 任何 | `0x01` 脉冲 | LiDAR 值 |
| **P2** (需转向) | 任何 | `0x01` 脉冲 | LiDAR 值 |
| **P4** (侧面感知) | 有方向指引 | `0x01` 脉冲 | LiDAR 侧面值（macro 暂时抑制）|
| **P4** (侧面感知) | 无/直行 | `0x01` 脉冲 | LiDAR 侧面值 |
| **P5** (畅通) | 需转向 | `0x02` 持续 | Macro 值 |
| **P5** (畅通) | 直行 (<5°) | — | 全部 0（静默）|
| **P5** (畅通) | 偏航重规划 | `0x02` 持续 | F=80 |

### 统一输出点

```swift
// 在 handleHazardUpdate() 末尾（10Hz）:

let lidarActive = (motorL > 0 || motorF > 0 || motorR > 0)

if lidarActive {
    // Micro 优先 → 脉冲模式
    sendBLE(cmd: 0x01, L: motorL, F: motorF, R: motorR)
} else {
    // Macro 接管 → 持续模式
    sendBLE(cmd: 0x02, L: macroMotorL, F: macroMotorF, R: macroMotorR)
}
```

### 时序

- LiDAR 以 10Hz 触发仲裁（主循环）
- Macro 以 ~1Hz 更新缓存值 `macroMotorL/F/R`
- 每次 LiDAR 回调时，取 macro 最新缓存值做仲裁

---

## BLE 协议

```
[0x01, L, F, R]  → 脉冲模式 (LiDAR micro)
                    ESP32: 100ms on / variable off, 强度固定 230 PWM
                    L/F/R = urgency (0=off, 255=常亮, 1-254=脉冲速率)

[0x02, L, F, R]  → 持续模式 (Google Maps macro)
                    ESP32: 直接 ledcWrite(pin, value)
                    L/F/R = PWM 强度 (0=off, 70-255=持续震动强度)
```

---

## 开发顺序

| # | 任务 | 状态 | 预计时间 |
|---|------|------|---------|
| 1 | ✅ Micro 避障 (System 1) | 完成 | — |
| 2 | ESP32 加 cmd=0x02 持续模式 | 待开发 | 30 分钟 |
| 3 | iOS macro 电机编码 + 缓存 (System 2) | 待开发 | 1 小时 |
| 4 | iOS 仲裁层合并 (System 3) | 待开发 | 1 小时 |
| 5 | 分别测试 System 1 / System 2 | 待测试 | 1 小时 |
| 6 | 联合测试 System 3 | 待测试 | 半天 |
