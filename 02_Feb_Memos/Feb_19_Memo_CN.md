# 2026年2月19日 — 每日备忘录

## 今日完成工作

### 1. 深度网格 UI 连续渐变颜色
- 将原来的 4 档离散颜色编码（红/橙/黄/绿）替换为 **HSB 色相连续渐变**
- 色相 0°（红色）对应 0m → 色相 120°（绿色）对应 3.0m，线性插值
- ≥3.0m 及 `inf` 值显示为纯绿色
- 在 `ViewController.swift` 中新增可配置参数 `maxColorDistance = 3.0`
- 更加直观：每 0.1m 差异在视觉上都可区分

### 2. 文献综述（8 篇论文）
详细审阅了 8 篇关于辅助导航、障碍物检测和视障触觉反馈的学术论文，创建了英文和中文两个版本的综述文档。

**审阅的论文：**
1. **Liu 等 (CHI 2022)** — Microsoft Soundscape 用户参与度分析（4,700+ 视障用户，ML 参与度预测）
2. **Tsai 等 (ACM TACCESS 2024)** — iOS 惯性室内寻路 + 回溯（手机放口袋，Apple Watch 交互）
3. **See 等 (Applied Sciences 2022)** — 智能手机深度成像，23 点采样障碍物检测
4. **MAIDR Meets AI (ASSETS 2024)** — 视障用户的多模态 LLM 数据可视化（相关性有限）
5. **Crabb 等 (Sensors 2023)** — 面向视障旅行者的轻量化视觉惯性室内定位
6. **Zuschlag 等 (arXiv 2022)** — 3D 摄像头 + 触觉反馈袖套，2D 振动电机阵列
7. **Rodriguez 等 (Sensors 2012)** — RANSAC 地面平面估计 + 极坐标网格 + 声学反馈 ⭐
8. **Huang 等 (Sensors 2015)** — RANSAC 地面移除 + 区域生长障碍物分割 ⭐

**为我们系统识别的关键方法（Step 2 优先级 1）：**
- 垂直梯度 ΔV — 检测台阶、路沿、落差
- 水平梯度 ΔH — 检测障碍物边缘、柱子
- 列求和障碍物密度（U-视差概念）— 左/右安全性对比
- 时间平滑（EMA）— 减少网格闪烁
- 地面平面估计（轻量 RANSAC）
- 连通域分析 — 将危险 cell 聚合为障碍物簇

### 3. 2月18日备忘录更新
- 新增 API key 安全修复、GitHub 仓库搭建、B2 文献调研等章节
- 新增问题 #5-6（API key 暴露、git push 冲突）
- 更新文件表格，新增 B2 参考文献部分

### 4. B2 障碍物分析流水线 — 完整实现 ⭐
实现了完整的 LiDAR 障碍物检测与安全路径寻找系统。

**架构决策（来自设计讨论）：**
- 使用完整 256×192 深度数据进行分析（16×16 网格仅用于 debug UI）
- ARKit VIO 已融合 IMU —— 不需要单独调用 IMU 模块
- 将深度像素投影到**世界坐标**（通过 `camera.transform` + 缩放后的 `camera.intrinsics`）→ 手机晃动/倾斜无影响
- 用**世界 Y 高度比较**替代 RANSAC（更简单，天然处理多平面）
- 3 电机触觉编码（L/F/R）替代原来的 2 电机

**LiDARManager.swift — 新增约 650 行：**
- **数据结构**: `FrameAnalysisResult`（spe/sps/spa/nspf/dse/use/pds/pus + 障碍物簇）、`ObstacleCluster`、`PointClassification`（6 级）、20+ 可配置参数
- **Step A**: 深度 → 世界坐标（64×48 降采样，intrinsics 从相机图像分辨率缩放到深度图分辨率）
- **Step B**: 地面高度估计（最低 30% Y 值直方图峰值 + EMA α=0.1）
- **Step C**: 高度分类（地面 ±8cm / 绊倒风险 / 低/中/高障碍物 / 轻度/严重落差）
- **Step E**: 台阶检测（中央 ±10 列 worldY 阶梯模式，≥3 级连续台阶）
- **Step F**: 坡道检测（地面点线性回归，阈值 ±5°）
- **Step G**: 48 列角度自由空间图（每方向的 freeDistance）
- **Step H**: 安全路径寻找（连续安全列段，物理宽度 ≥ safeWidthConstant 0.8m，优先正前方）
- **Step I**: 时间平滑（布尔滞后 3帧开/5帧关，EMA 角度/距离，非对称 EMA 最近障碍物距离）
- **Console log**: `[B2] flags=[SPE SPS] angle=+0.0° width=2.50m near=1.20m@+15° groundY=-1.150 obs=2`

**ViewController.swift — 新增约 100 行：**
- **hazardLabel**: 屏幕 debug 标签（模式 + L/F/R 强度 + 距离信息）
- **handleHazardUpdate()**: P0-P5 优先级触觉编码：
  - P0: 停止（3 电机全 255，无安全路径）
  - P1: 前方落差（F 电机快脉冲）—— 未来 ESP32 模式
  - P2: 转向引导（角度 → L/F/R 权重插值，距离决定紧迫度）
  - P3: 地形叠加（台阶 = F≥120，坡道 = F≥60）
  - P4: 两侧感知（L/R ≤80，侧面有障碍，F=0）
  - P5: 畅通（全部 0）
- **Console log**: `[HAPTIC] P2:steer +15° | L=000 F=113 R=089`

**编译: ✅ 成功**

## 修改/创建的文件
| 文件 | 操作 |
|------|------|
| `Controllers/LiDARManager.swift` | **大幅编辑**（约 650 行：B2 分析流水线） |
| `Controllers/ViewController.swift` | 编辑（HSB 渐变 + B2 hazard 标签 + 触觉编码） |
| `Literature_Review.txt` | **新建**（英文，8 篇论文） |
| `Literature_Review_CN.txt` | **新建**（中文，8 篇论文） |
| `Feb_18_Memo.md` | 更新（新增 §2-4、问题、参考文献） |
| `Feb_18_Memo_CN.md` | 更新（新增 §2-4、问题、参考文献） |
| `Feb_19_Memo.md` | **新建** + 更新 |
| `Feb_19_Memo_CN.md` | **新建** + 更新 |

## 下一步
- **Step 3:** 仲裁层 — 融合 macro（Google Maps 方向）+ micro（LiDAR 危险信息）
- **Step 4:** ESP32 协议升级（4 字节包：CommandType + L/F/R 强度）+ 3 电机 PWM
- **硬件:** 确定 Front 电机 GPIO 引脚，真机测试
- 真机测试 B2 分析输出（验证 groundY、安全路径、障碍物检测）
