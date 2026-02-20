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

## 修改/创建的文件
| 文件 | 操作 |
|------|------|
| `Controllers/ViewController.swift` | 编辑（HSB 渐变颜色） |
| `Literature_Review.txt` | **新建**（英文，8 篇论文） |
| `Literature_Review_CN.txt` | **新建**（中文，8 篇论文） |
| `Feb_18_Memo.md` | 更新（新增 §2-4、问题、参考文献） |
| `Feb_18_Memo_CN.md` | 更新（新增 §2-4、问题、参考文献） |
| `Feb_19_Memo.md` | **新建** |
| `Feb_19_Memo_CN.md` | **新建** |

## 下一步
- **Step 2:** 实现 ΔV + ΔH 梯度分析 + 列求和密度 + EMA 时间平滑 → 输出 `HazardResult`
- **Step 3:** 仲裁层，融合 Google Maps 导航方向 + LiDAR 危险信息
- **Step 4:** ESP32 协议扩展，支持 STOP/地形指令 + 马达振动模式
- 在真机上测试 HSB 渐变效果
