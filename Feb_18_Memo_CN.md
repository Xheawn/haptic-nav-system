# 2026年2月18日 — 每日备忘录

## 今日完成工作

### 1. LiDAR 16×16 深度网格 — Phase B1 完成

**LiDARManager.swift — 大幅重写**
- 从 `frame.sceneDepth` 切换到 `frame.smoothedSceneDepth`（Apple 多帧时间平滑算法）
- 从基础的 3 列最小深度升级为 **16×16 网格**（256 个单元格，每格覆盖 16×12 缓冲区像素）
- 每个单元格使用 **第10百分位深度**，通过 O(n) Quickselect 算法计算（替代了之前的全排序）
- 竖屏方向修正: buffer x 轴 → 显示行，buffer y 轴 → 显示列
- 左右镜像修正: 反转列索引，使网格与真实场景左右方向一致
- 新增 `forwardCropRatio = 0.75` — 裁掉底部 25% 的视场角（近地面区域），将全部 16 行分配给前方探测区域
  - 原理: 手机平放时，深度缓冲区 x=0 对应最远/前方，x=255 对应最近/脚下
  - 裁掉后每格从 16×12=192 像素减少到 12×12=144 像素，仍足够计算可靠的第10百分位
  - 换来的是前方区域的空间分辨率提高约 33%
- 分析频率从 10 Hz 降至 **5 Hz** 以缓解手机发热
- 所有阈值均可配置: `dangerCloseDistance`、`dangerDistance`、`cautionDistance`、`forwardCropRatio` 等

**ViewController.swift — Debug 网格 UI**
- 屏幕中央 16×16 彩色网格覆盖层
- 4 档颜色编码:
  - 🔴 红色: < 0.5m（极度危险）
  - 🟠 橙色: 0.5m – 1.0m（危险）
  - 🟡 黄色: 1.0m – 2.0m（注意）
  - 🟢 绿色: > 2.0m（安全）
- 通过 `LiDARManager.shared.onGridUpdate` 回调以 5 Hz 实时更新
- 临时覆盖层，用于验证——后续会移除或添加开关

**Info.plist**
- 添加 `NSCameraUsageDescription` 以获取 ARKit LiDAR 访问权限

### 2. 文档更新
- 更新 `PROGRESS.md`: Phase B1 标记为完成，附完整细节
- 创建英文版备忘录及本中文版

## 修改/创建的文件
| 文件 | 操作 |
|------|------|
| `Controllers/LiDARManager.swift` | **新建** 后多次迭代 |
| `Controllers/ViewController.swift` | 编辑（debug 网格 UI + LiDAR 集成） |
| `Info.plist` | 编辑（相机权限） |
| `PROGRESS.md` | 更新（B1 完成） |
| `Feb_18_Memo.md` | **新建** |
| `Feb_18_Memo_CN.md` | **新建** |

## 遇到的问题及解决方案
1. **网格方向错误** — 深度缓冲区是 256×192 的 landscape-right 原始方向；竖屏时 x 和 y 轴对调。修复方法: 显示行映射到 buffer x，显示列映射到 buffer y。
2. **左右镜像** — 轴对调后左右仍然反转。修复方法: 反转列索引 `byStart = (cols - 1 - col) * pxPerCol`。
3. **手机发热 + UI 卡顿** — 16×16 网格以 10 Hz 频率运行全排序 O(n log n) 开销过大。修复方法: (a) 使用 Quickselect O(n) 计算第10百分位，(b) 分析频率降至 5 Hz。
4. **前方数据不够** — 用户需要更多前方障碍物探测，减少近地面数据。修复方法: `forwardCropRatio = 0.75` 裁掉缓冲区底部 25% 并将行数重新分配给前方区域。

## 可配置参数（LiDARManager）
| 参数 | 值 | 说明 |
|------|------|------|
| `dangerCloseDistance` | 0.5m | 红色阈值 |
| `dangerDistance` | 1.0m | 橙色阈值 |
| `cautionDistance` | 2.0m | 黄色阈值 |
| `forwardCropRatio` | 0.75 | 前方视场聚焦（裁掉 25% 近地面） |
| `hGradientThreshold` | 1.0m | 水平梯度阈值（Step 2 使用） |
| `vGradientThreshold` | 0.5m | 垂直梯度阈值（Step 2 使用） |
| `analysisInterval` | 0.2s | 5 Hz 分析频率 |
| `logInterval` | 0.5s | 2 Hz 控制台打印频率 |

## 下一步
- **Step 2:** 梯度分析（水平 ΔH + 垂直 ΔV）用于障碍物边缘和地形不连续性检测 → 输出 `HazardResult`
- **Step 3:** 仲裁层，融合 Google Maps 导航方向 + LiDAR 危险信息
- **Step 4:** ESP32 协议扩展，支持 STOP/地形指令 + 马达振动模式
