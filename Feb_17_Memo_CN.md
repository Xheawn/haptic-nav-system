# 2026年2月17日 — 每日备忘录

## 今日完成工作

### 1. 项目进度文档
- 创建了 `PROGRESS.md`，包含完整项目架构、已完成阶段（Stage 1–8）及分阶段 TODO
- 所有已完成工作以 checkbox 格式记录，与 TODO 格式统一

### 2. BLE 蓝牙通信 — Phase A（核心）

**ESP32 端 (`esp32_s3_test.ino`)**
- 使用 `BLEDevice.h` 将固件重写为 BLE Server
- 设备名: `XIAO_ESP32S3`，广播自定义 Service UUID
- 可写 Characteristic（WRITE + WRITE_NR）用于低延迟命令传输
- 断开连接后自动重新广播
- 修复编译错误: `std::string` → `String`（ESP32 Arduino 库的 `getValue()` 返回的是 Arduino `String` 类型）
- 修复 Serial 输出乱码: 将 `Serial.println` 从 BLE 回调（运行在不同的 FreeRTOS 任务上）移到 `loop()` 中，使用 `volatile` 共享变量 + 100ms 节流 + `snprintf` 原子打印

**iOS 端 (`BLEManager.swift`) — 新文件**
- `CBCentralManager` 单例模式
- 完整管线: 扫描 → 连接 → 发现服务 → 发现特征值
- `sendCommand(_ data: Data)` 使用 `.withoutResponse` 实现低延迟写入
- 断开后自动重连

**ViewController 集成**
- 在 `viewDidLoad` 中启用 `BLEManager.shared.start()`
- 在两处启用 `BLEManager.shared.sendCommand(packet)`:
  - `applyAdjustDirectionLogic()` — 常规导航指令
  - `checkUserThresholds()` — 偏离路线通知（direction=3）
- 5Hz 节流确认正常工作

### 3. 端到端验证
- iPhone 成功实时发送 `[AdjustDirection, AngleDiff]`
- ESP32 Serial Monitor 确认接收: `[BLE] Dir:1  Angle:148`
- BLE 连接在测试期间保持稳定

## 修改/创建的文件
| 文件 | 操作 |
|------|------|
| `esp32_s3_test/esp32_s3_test.ino` | 重写（BLE Server） |
| `Controllers/BLEManager.swift` | **新建** |
| `Controllers/ViewController.swift` | 编辑（取消 BLE 调用的注释） |
| `PROGRESS.md` | **新建** 并更新 |

## 遇到的问题及解决方案
1. **`std::string` 编译错误** — ESP32 Arduino 的 `getValue()` 返回 `String` 而非 `std::string`，类型替换即可
2. **Serial 输出乱码** — BLE 回调运行在不同的 FreeRTOS 任务上，与 `loop()` 线程冲突；改为在回调中只写 `volatile` 变量，在 `loop()` 中安全打印

## 下一步
- **A5:** ESP32 根据收到的 BLE 指令驱动马达 PWM
- **Phase B:** 集成 LiDAR 进行微观障碍物检测
