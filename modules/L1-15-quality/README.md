# L1-15 客观质量指标计算：PSNR / SSIM / SNR

## 目标

**不依赖任何现成质量评测库**，用 C 从零实现三个最常见的客观质量指标——**PSNR、SSIM、SNR**——
把「同一源按不同码率转码」的产物与原图逐帧对比，输出**指标曲线**，并用 **ffmpeg 的 `psnr` 滤镜做交叉验证**，
理解「为什么客观指标能衡量画质、以及它在哪些场景会骗人」。

## 核心概念（脚本实现依据）

公式统一按 **8bit、MAX = 255** 计算。

| 指标 | 公式 | 说明 |
|---|---|---|
| MSE | `(1/N) · Σ (x_i − y_i)²` | 均方误差，PSNR/SNR 的公共底座 |
| PSNR | `10 · log10( MAX² / MSE )` | 峰值信噪比，单位 dB；误差为 0 时为 **+∞** |
| SNR | `10 · log10( Σ x_i² / Σ (x_i − y_i)² )` | 信噪比，与 PSNR 的差别是分母用的是**信号能量**而非 `MAX²` |
| SSIM | `((2·μx·μy + C1)(2·σxy + C2)) / ((μx² + μy² + C1)(σx² + σy² + C2))` | 结构相似度，取值 `[-1, 1]`，越接近 1 越像 |

- 常量：`C1 = (0.01 · MAX)² = 6.5025`，`C2 = (0.03 · MAX)² = 58.5225`
- SSIM 本工具在 **Y 平面按 8×8 块**计算（边缘块取剩余尺寸），再取全图平均；逐帧后再对帧求平均
- PSNR 分 `Y / U / V` 三个平面分别算，另给三者的算术平均 `psnr_avg`

### 为什么工程里要关心这些数字

| 场景 | 用哪个指标 | 原因 |
|---|---|---|
| 编码器/码率调优 | PSNR + SSIM | 快速量化「丢了多少」，低成本可自动化 |
| 结构/纹理保真 | SSIM | 对模糊、块效应更敏感，比 PSNR 更贴近主观 |
| 信号自身强弱 | SNR | 分析噪声相对信号能量，适合采集/传输链路评估 |
| 最终判断 | **主观** | 客观指标会「骗人」——详见踩坑清单 |

## 实验步骤

### A. 自动化实验（本机可跑，一条命令）

```powershell
powershell -NoProfile -File scripts\quality_practice.ps1
```

链路：

1. **生成参考基准**：`testsrc2` → 无损 YUV420P 原始流（`ref_640x360.yuv`）
2. **多码率转码**：`libx264` 按 `2000 / 1000 / 500 / 250 kbps` 各转一份 → 解码回 YUV420P
3. **指标计算**：用 `quality_tools` 对每档产物与参考逐帧算 PSNR/SSIM/SNR
4. **交叉验证**：同一对视频用 **ffmpeg `psnr` 滤镜**再算一遍，断言两者 PSNR(Y) 误差 **< 0.5 dB**
5. **单调性断言**：码率高者的 PSNR / SSIM 不得低于码率低者
6. **产物输出**：`metrics.csv`（数据）+ `curve.txt`（ASCII 曲线）+ `frame_*.png`（各档首帧，供主观对照）
7. **边界与踩坑**：同文件比较（应 `identical=true`、PSNR=∞）、分辨率不一致、像素格式不统一

### B. 手工用工具

```powershell
# 用法: quality_tools <ref.yuv> <test.yuv> <width> <height> [max_frames]
build\bin\quality_tools.exe ref_640x360.yuv br_500k.yuv 640 360
```

输出三部分：逐帧 `frame=..`、汇总 `summary frames=..`、机器可读 `RESULT {...json...}`。

## 依赖

- 工具链：gcc（编译 `quality_tools`）、ffmpeg（生成素材 / 转码 / 交叉验证）
- 脚本：PowerShell 5.1+
- 无需任何第三方质量评测库（PSNR/SSIM/SNR 全部自实现）

## 构建与运行

```powershell
# 仓库根（av-lab）一键构建 + 全量测试
powershell -NoProfile -File tools\build.ps1

# 只构建本模块工具
cmake --build build --target quality_tools
```

模块注册脚本型测试 `L1-15.quality_practice`（依赖 `quality_tools`，通过 `$<TARGET_FILE:quality_tools>` 传路径）。

## 预期输出（实测）

多码率结果（`ref` 640×360、25 帧、25fps、YUV420P）：

| 码率 | PSNR(Y) | PSNR(U) | PSNR(V) | PSNR(avg) | SSIM(Y) | SNR(Y) | ffmpeg PSNR(Y) | Δ(dB) |
|---|---|---|---|---|---|---|---|---|
| 2000k | 52.9460 | 52.0518 | 52.3397 | 52.4458 | 0.9990 | 47.5741 | 52.7199 | 0.2261 |
| 1000k | 46.2107 | 45.6976 | 46.2655 | 46.0579 | 0.9963 | 40.8387 | 46.1217 | 0.0890 |
| 500k  | 39.2094 | 40.2493 | 41.0105 | 40.1564 | 0.9850 | 33.8374 | 39.1355 | 0.0739 |
| 250k  | 34.9976 | 37.0116 | 36.7861 | 36.2651 | 0.9665 | 29.6256 | 34.9854 | 0.0122 |

- 自算 PSNR(Y) 与 ffmpeg `psnr` 滤镜**误差均 < 0.23 dB**（断言阈值 0.5 dB），实现正确
- PSNR / SSIM / SNR 随码率**单调下降**（单调性断言通过）

其他实测结论：

| 场景 | 实测结果 |
|---|---|
| 同文件比较 | `SSIM=1.0000`、`PSNR=inf`（JSON 中为 `null`）、`identical=true` ✔ |
| 分辨率不一致 | ffmpeg `psnr` 滤镜报 `Width and height of input videos must be same.`，`exit≠0` ✔ |
| 像素格式不统一 | `quality_tools` 按 420P 解析 444P → 单帧字节数翻倍 → 告警「帧数不一致」✔ |
| 反向印证 | ffmpeg `psnr` 遇 420P/444P 混用会**静默插转换、不报错**（更隐蔽）✔ |
| ctest 用例 | `L1-15.quality_practice` **Passed**（3.02 sec） |
| 全量 ctest | **18 / 18 全绿**（L1-01 ~ L1-15） |

`curve.txt` 实测（节选）：

```text
PSNR(Y) dB  (34.9976 ~ 52.946)
    2000k | ######################################## 52.946
    1000k | ######################### 46.2107
     500k | ######### 39.2094
     250k |  34.9976

SSIM       (0.9665 ~ 0.999)
    2000k | ######################################## 0.999
    1000k | ##################################### 0.9963
     500k | ####################### 0.985
     250k |  0.9665
```

产物路径：`build/_artifacts/L1-15-quality/`（`metrics.csv` / `curve.txt` / `frame_*.png`）。

## 高频命令速查

| 需求 | 命令 |
|---|---|
| 跑本模块实验 | `powershell -NoProfile -File scripts\quality_practice.ps1` |
| 手工比较两个 YUV | `quality_tools.exe ref.yuv test.yuv 640 360` |
| 看指标数据 | `Get-Content build\_artifacts\L1-15-quality\metrics.csv` |
| 看曲线 | `Get-Content build\_artifacts\L1-15-quality\curve.txt` |
| 只跑本模块测试 | `ctest -R L1-15`（需先 `tools\build.ps1` 配好工具链 PATH） |

## 踩坑清单

1. **分辨率不一致无法直接比**：ffmpeg `psnr` 滤镜要求两路输入分辨率相同，否则直接报 `Width and height of input videos must be same.` 并退出；比较前必须对齐尺寸。
2. **像素格式不统一更隐蔽**：ffmpeg 7 的 `psnr` 滤镜遇到 420P vs 444P 会**静默插入格式转换**、`exit=0`，不报错却在「不公正比较」；自实现工具（只按 420P 解析字节）反而会因帧数翻倍而告警——**不能盲信工具不报错**。
3. **PSNR 为无穷大（全 0 误差）**：两帧完全相同时 `MSE=0`，`PSNR=+∞`。JSON 无法表示 `Infinity`，本工具用 `null`；脚本解析时须判 `$null -eq ...`，别直接当数字运算。
4. **YUV420P 帧大小陷阱**：单帧字节数 = `w·h·1.5`（不是 `w·h·3`）。按 RGB24（`w·h·3`）或 444P 的规格去读 420P 文件，帧数会算错。
5. **宽高必须是偶数**：YUV420P 的 U/V 平面是 `(w/2)·(h/2)`，奇数宽高无法整除；本工具显式拒绝奇数尺寸。
6. **不同码率≠线性可比**：`-b:v` 是目标码率，实际码率受场景复杂度影响；跨内容比较 PSNR 意义有限，只有**同源同场景**的曲线才可读。
7. **只看 PSNR 会误判**：PSNR 高不代表画质好——高 PSNR 也可能糊成一片（见下条）；PSNR 低也不代表难看。必须结合 SSIM + **主观对照图**（本模块输出的 `frame_*.png`）。
8. **SSIM 的实现差异**：不同实现的窗口/块大小/是否高斯加权都不一样，数值不可跨实现直接比大小；本工具固定 **8×8 无重叠块**，只用于**同工具内的相对比较**。
9. **PowerShell 变量在字符串里的冒号**：`"rate=$FPS:duration=$DUR"` 会被解析成作用域变量 `$FPS:` → 值变空，生成命令变成 `rate==1`；必须写 `${FPS}`（本模块首轮 ctest 就踩了这个坑）。
10. **原始 `rawvideo` 无元数据**：`.yuv` 文件不带宽高/像素格式信息，`quality_tools` 必须靠命令行参数指定 `width/height`，填错就整段错位。

## 测试实现说明（为什么这么测）

质量指标的正确性验证不能只「跑通」，要有**独立参照系**：

- **交叉验证而非自证**：用 **ffmpeg `psnr` 滤镜**这个成熟实现做参照，断言自算 PSNR(Y) 与它误差 < 0.5 dB。若只断言「我的工具输出了数字」，实现错了也照样绿。
- **单调性作为逻辑断言**：码率越高、`-b:v` 越大，PSNR/SSIM 理应不降。这是不依赖外部工具的「方向正确性」校验。
- **边界必须显式构造**：同文件比较（`identical`、`PSNR=∞`）、决议不一致、像素格式不统一，都是只在边界才暴露的问题，脚本里逐一构造并断言。
- **踩坑要「双向印证」**：既验证自实现工具会告警，也验证 ffmpeg 会静默放过，才能说明这个坑真实且隐蔽。

## 实测环境

- Windows + PowerShell 5.1
- CMake 4.5.1 / CTest
- gcc（w64devkit）+ ffmpeg（master-latest-win64-gpl）
- 素材：`testsrc2` 合成（无版权依赖），YUV420P 640×360 / 25 帧
