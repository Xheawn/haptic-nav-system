# 2026年2月27日 — 每日备忘录

## 今日完成工作

### 1. Apple API 完整参考文档
创建 `Project_Pipelines/Apple_APIs_Reference.md`，系统梳理 B1/B2 管线中使用的全部 Apple 框架、类、协议、属性和函数：

| 框架 | 主要 API | 用途 |
|------|---------|------|
| **ARKit** | ARSession, ARSessionDelegate, ARWorldTrackingConfiguration, ARFrame, ARCamera, ARDepthData | LiDAR 深度采集、相机位姿、置信度图 |
| **CoreVideo** | CVPixelBufferLock/Unlock/GetBaseAddress/GetWidth/GetHeight/GetBytesPerRow | 直接操作深度图和置信度图的原始内存 |
| **simd** | simd_float3, simd_float4, simd_float3x3, simd_float4x4, 矩阵×向量 | 3D 坐标变换（深度像素→世界坐标） |
| **Foundation** | NSObject, TimeInterval, DispatchQueue.main.async | 基类、时间戳、主线程调度 |
| **Swift Stdlib** | MemoryLayout, assumingMemoryBound, sqrtf/asin/atan/tan, Array 操作 | 内存操作、数学计算、数据处理 |

包含完整的 API 调用流程图和各步骤 API 依赖汇总表。

### 2. ViewController 工作流程文档
创建 `Project_Pipelines/ViewController_Workflow.md`，从 App 启动到实时运行的完整工作流详解：

- **App 启动 → viewDidLoad 触发**：iOS App 生命周期，property 初始化时机
- **viewDidLoad 11 步逐行分析**：每一步做了什么、调用了哪些函数、同步/异步
- **4 个实时数据循环**：
  - **Loop A**: GPS ~1Hz → `checkUserThresholds` → `applyAdjustDirectionLogic`
  - **Loop B**: 指南针 ~10Hz → 更新 `currentPhoneAngle` → `applyAdjust`
  - **Loop C**: LiDAR 5Hz → B1/B2 分析 → `handleHazardUpdate` → P0-P5 电机强度
  - **Loop D**: BLE 事件驱动 → 扫描/连接/重连 → `sendCommand`
- **Loop A 与 Loop B 协作关系**：A 提供"该往哪走"，B 提供"手机现在朝哪"
- **完整数据流图**：传感器层 → iOS 回调层 → ViewController 处理层 → BLE 输出层
- **前 3 秒时间轴**：精确到毫秒的启动顺序示例

### 3. 导航阈值决策逻辑分析
详细解析 `checkUserThresholds` 核心决策分支（L552-L611）：

- **情况 A（在路线上）**：`maxIndex` 选取逻辑 — 取最大 index 代表用户走得最远的位置
- **情况 B（偏航）**三个子步骤：
  - B1: 立即反馈 — `isOffRoute=true`，BLE 发送 `[3, 0]`
  - B2: GPS Outlier 检测 — 距上次偏航位置 < 5m 则判定为 GPS 漂移，不重规划
  - B3: 延迟 1 秒重规划 — 防止 GPS 跳动导致频繁 API 请求

### 4. GitHub 权限确认
确认 Public repo 默认设置下的权限模型：
- 外部用户只能 Fork/Clone/提 PR/提 Issue
- **不能**直接 push 或合并 PR — 需要 repo owner 审批
- 只有在 Settings → Collaborators 添加的用户才有 write 权限

## 新建/修改的文件

| 文件 | 操作 |
|------|------|
| `Project_Pipelines/Apple_APIs_Reference.md` | **新建** — B1/B2 Apple API 完整参考 |
| `Project_Pipelines/ViewController_Workflow.md` | **新建** — ViewController 工作流程详解 |
| `02_Feb_Memos/Feb_27_Memo_CN.md` | **新建** — 本日备忘录 |

## 问题记录

| # | 描述 | 状态 |
|---|------|------|
| 13 | ESP32 D5/D8 电机不振动（焊接问题） | 🔄 待排查 |
| 14 | `maxIndex` 策略在大 t1 半径时可能跳过中间路段 | 📋 已记录 |

## 下一步
- **ESP32 电机焊接排查**
- **真机测试**全分辨率分析（性能/发热/小障碍物检测验证）
- **仲裁层**：融合 Macro（Google Maps）+ Micro（LiDAR）导航指令
- **ESP32 协议升级**：4 字节包 `[cmd, L, F, R]` + 3 电机 PWM 控制
