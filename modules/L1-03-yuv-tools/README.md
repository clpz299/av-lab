# L1-03 RGB / YUV 像素数据处理工具集

素材依据：[article/020 视音频数据处理：RGB、YUV像素数据处理](file:///d:/workspace/private/audio_video_streaming-main/article/020-视音频数据处理：RGB、YUV像素数据处理.md)

## 目标

用一个单文件命令行工具 `yuv_tools` 覆盖 8bit 像素数据的常见处理，理解 **Planar / Packed 两种存储布局**与 **YUV ↔ RGB 转换**，并能肉眼回放验证。

## 存储布局（工具实现的核心约束）

| 格式 | 布局 | 一帧大小 | 说明 |
|---|---|---|---|
| YUV420P | Planar | `w*h*3/2` | Y 后接 U、V；U/V 各 `w*h/4` |
| YUV444P | Planar | `w*h*3` | Y、U、V 各 `w*h` |
| RGB24 | Packed | `w*h*3` | 每像素连续 R,G,B |

## 子命令

```
split420    <in.yuv> <w> <h> <num> <outdir>      分离 420P 的 Y/U/V
split444    <in.yuv> <w> <h> <num> <outdir>      分离 444P 的 Y/U/V
gray420     <in.yuv> <w> <h> <num> <out.yuv>     U/V 置 128 -> 灰度
half420     <in.yuv> <w> <h> <num> <out.yuv>     Y 整除 2 -> 变暗
border420   <in.yuv> <w> <h> <border> <num> <out.yuv>  四周加白边
graybar420  <w> <h> <ymin> <ymax> <barnum> <out.yuv>   生成灰阶测试图
psnr420     <a.yuv> <b.yuv> <w> <h> <num>        计算 Y 分量 PSNR
splitrgb24  <in.rgb> <w> <h> <num> <outdir>      分离 R/G/B
rgb24tobmp  <in.rgb> <w> <h> <out.bmp>           RGB24 封装为 BMP
rgb24toyuv  <in.rgb> <w> <h> <num> <out.yuv>     RGB24 -> YUV420P
colorbar24  <w> <h> <out.rgb>                    生成 RGB24 彩条
```

## 依赖

- 便携工具链（gcc + ffmpeg），见仓库根 README；
- 测试素材由 `scripts/yuv_practice.ps1` 用 ffmpeg `lavfi` 自产（testsrc2 / smptebars），无需外部文件。

## 构建与运行

```powershell
# 全量构建 + 测试
pwsh -NoProfile -File tools/build.ps1

# 单独跑本模块测试
pwsh -NoProfile -File modules/L1-03-yuv-tools/scripts/yuv_practice.ps1 build/modules/L1-03-yuv-tools/yuv_tools.exe
```

## 预期输出

`scripts/yuv_practice.ps1` 打印 10 个实验段并断言：
- 分量分离产物大小正确；
- 灰度化后 U/V 区全为 128；
- 亮度减半后 `Y == 原值/2` 且 U/V 未被改动；
- 加边框后四角为 255、内部像素不变；
- 灰阶图第 0/5 条亮度为 0/141，U/V 全 128；
- PSNR：自比对应为 `inf`，不同图像为 `(0,100]`；
- RGB24 分离、BMP 封装（ffprobe 复核分辨率）、RGB→YUV 转换、彩条（白/红/黑段）逐项通过。

最终打印 `yuv_practice PASS`，产物在 `build/_artifacts/L1-03-yuv-tools/`。

## 踩坑清单

- **YUV 无头信息**：宽高靠调用方约定，填错即花屏；420P 的 U/V 各是 `w*h/4`（不是 `w*h/2`）。
- **`border` 边界不对称**：素材判定式为 `k<border || k>(w-border)`，右/下比左/上各少 1 像素——本工具保留该行为作为踩坑对照。
- **`graybar` 亮度用截断**：`ymin + (int)(t*lum_inc)`，小数值直接截断，故第 5 条是 141 而非 142。
- **BMP 行序**：BMP 默认自底向上，用负高度（`biHeight = -h`）改为自顶向下，否则图像上下颠倒。
- **RGB↔BMP 通道序**：BMP 存 B,G,R，与 RGB24 的 R,G,B 相反，必须交换首尾字节。
- **PSNR 除零**：两图完全相同时 MSE=0，PSNR 为 `inf`，属正常，不宜判为实现错误。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| 编译器 | gcc 16.2.0 (w64devkit 2.11.0) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
