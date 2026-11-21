# L1-09 MP4 文件生成与封装入门

素材依据：[article/026 如何生成mp4文件](file:///d:/workspace/private/audio_video_streaming-main/article/026-如何生成mp4文件.md)

## 目标

打通 **MP4 解封装 → 裸流 → 再封装回 MP4** 的完整链路，理解「封装（mux）/ 解封装（demux）」与 MP4 的 box 结构；踩透两个封装坑：裸流时间戳/帧率、AAC 的 ADTS→ASC 转换。

## 核心概念（脚本实现依据）

- **封装（mux）/ 解封装（demux）**：封装把视频/音频**码流**按容器格式（MP4/FLV/TS…）打包；解封装则拆出各条码流。**封装不改变编码**，`-c copy` 即为转封装；
- **MP4 是 box（原子）结构**：顶层常见 `ftyp`（文件类型）、`moov`（元数据/时长/索引）、`mdat`（媒体数据）、`free`；`moov` 默认在文件末尾，`-movflags +faststart` 会把它前移到 `mdat` 之前，便于网络边下边播；
- **AVCC vs Annex-B**：MP4 内 H.264 用**长度前缀**（AVCC），裸流用**起始码**（Annex-B，`00 00 00 01`）；互转靠 `-bsf:v h264_mp4toannexb`；
- **ADTS vs ASC**：AAC 裸流（`.aac`）每帧带 7 字节 ADTS 头；MP4 内的 AAC 去掉 ADTS 头，改用 `esds` 里的 **AudioSpecificConfig(ASC)** 描述；
- **裸流没有时间戳**：H.264 裸流不带时间信息，封装时必须用 `-r`（帧率）告诉复用器如何生成时间戳，否则**时长/播放速度异常**。

## 实验步骤

```
0) 素材：testsrc2 320x240/30fps/2s + 440Hz 正弦，编码成带音视频的 src.mp4
1) 解封装：-bsf:v h264_mp4toannexb -> v.h264（Annex-B）；-f adts -> a.aac（ADTS）
2) 封装：-r 30 -i v.h264 -i a.aac -c copy -bsf:a aac_adtstoasc -> remux.mp4
3) 查看顶层 box：ftyp / free / mdat / moov
4) faststart：+faststart -> moov 前移到 mdat 之前
5) 踩坑：-r 60 -> 视频时长减半（时间戳生成错）
6) 踩坑：ADTS vs ASC：MP4 内 AAC 的 extradata 远小于 7 字节 ADTS 头
```

## 依赖

- 便携工具链（ffmpeg/ffprobe），见仓库根 README；
- 无 C 工具，素材由脚本自产，box 结构由脚本直接读二进制解析。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-09-mp4-mux/scripts/mp4_mux_practice.ps1
```

## 预期输出

脚本打印 7 个实验段并断言，最终 `mp4_mux_practice PASS`，产物在 `build/_artifacts/L1-09-mp4-mux/`。

实测（320x240/30fps/2s 素材）：

| 步骤 | 结果 |
|---|---|
| 解封装 v.h264 | 首 4 字节 `00 00 00 01`（Annex-B 起始码） |
| 解封装 a.aac | 首 2 字节 `ff f1`（ADTS 同步字） |
| 封装 remux.mp4 | `nb_streams=2`，h264 + aac，时长 2.043s |
| 默认 box 顺序 | `ftyp → free → mdat → moov` |
| faststart box 顺序 | `ftyp → moov → free → mdat`（moov 前移） |
| `-r 30` / `-r 60` | 视频时长 1.933s / 0.933s |
| MP4 内 AAC extradata | 2 字节（ASC），远小于 7 字节 ADTS 头 |

## 高频命令速查

```powershell
# 解封装：MP4 -> H.264 裸流（务必转 Annex-B）
ffmpeg -i in.mp4 -c copy -bsf:v h264_mp4toannexb -f h264 out.h264

# 解封装：MP4 -> AAC 裸流（ADTS）
ffmpeg -i in.mp4 -c copy -vn -f adts out.aac

# 封装：H.264 + AAC 裸流 -> MP4（-r 指定帧率，AAC 加 aac_adtstoasc）
ffmpeg -r 30 -i v.h264 -i a.aac -c copy -bsf:a aac_adtstoasc out.mp4

# 边下边播：moov 前移
ffmpeg -i in.mp4 -c copy -movflags +faststart out.mp4

# 查看格式与流信息
ffprobe -v error -show_entries format=format_name,duration,nb_streams -of default=nw=1 in.mp4
ffprobe -v error -show_entries stream=codec_type,codec_name -of default=nw=1 in.mp4
```

## 踩坑清单

- **裸流没有时间戳**：把 H.264 裸流封成 MP4 时若不给 `-r`（或用错帧率），复用器只能按默认/给定帧率生成时间戳，结果是**时长异常、播放变速**；本实验 `-r 60` 让 2s 素材只剩约 1s；
- **AAC 的 ADTS 头**：AAC 裸流是 ADTS（每帧 7 字节头），MP4 内必须是 ASC（`esds`）；从 ADTS 裸流封装到 MP4 时用 `-bsf:a aac_adtstoasc` 显式转换；**新版 ffmpeg 读取 `.aac` 时会自动提取 ASC**，但在 FLV/RTMP 等把 ADTS 当字节流传递的场景仍需显式加该 bsf；
- **AVCC/Annex-B 混淆**：把 MP4 里的 AVCC 数据直接当裸流用会解析失败，导出裸流要加 `-bsf:v h264_mp4toannexb`；
- **moov 位置影响首帧延迟**：默认 moov 在末尾，网络播放需先下完整文件才能起播；点播文件统一加 `-movflags +faststart`；
- **`-c copy` 不会重新编码**：转封装只重排容器，失败多因目标容器不支持源编码（如把未转换的 ADTS 塞进 MP4）。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
