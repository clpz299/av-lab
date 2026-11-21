# L1-05 视频码流分析工具入门

素材依据：
- [article/022 视音频数据处理：H.264视频码流解析](file:///d:/workspace/private/audio_video_streaming-main/article/022-视音频数据处理：H.264视频码流解析.md)
- [article/041 视频码流分析工具](file:///d:/workspace/private/audio_video_streaming-main/article/041-视频码流分析工具.md)
- [article/042 H.264分析器](file:///d:/workspace/private/audio_video_streaming-main/article/042-H.264分析器.md)

## 目标

理解 **H.264 裸流（Annex-B）由 NALU 拼接而成**，掌握从 MP4 导出裸流的正确姿势，并用一个自研命令行分析器 `h264_nalu` 列出每个 NALU 的类型与 I 帧位置，替代重量级 GUI 分析器做快速确认。

## 核心概念（工具实现依据）

- **NALU**：H.264 的最小语法单元，每帧由一到多个 NALU 组成；
- **起始码 StartCode**：`00 00 01`（3 字节）或 `00 00 00 01`（4 字节），用于分隔 NALU，4 字节码通常出现在一帧的开头（SPS/PPS/首片）；
- **NALU 头 1 字节**：`forbidden_zero_bit(1)` + `nal_ref_idc(2)` + `nal_unit_type(5)`；
  - 常见 type：`1`=非 IDR 片、`5`=IDR 片（I 帧）、`6`=SEI、`7`=SPS、`8`=PPS、`9`=AUD；
- **两种封装**：MP4 内部用 **AVCC/长度前缀**（每 NALU 前置 4 字节大端长度，参数集存在 extradata）；裸流/TS/FLV 用 **Annex-B/起始码**。

## 子命令

```
h264_nalu <annexb.h264>      列出裸流中每个 NALU 的 POS/IDC/TYPE/LEN，并汇总 I 帧数
```

退出码：`0` 成功；`1` 参数/文件错误；`2` 未发现起始码（输入不是 Annex-B）。

## 依赖

- 便携工具链（gcc + ffmpeg/ffprobe），见仓库根 README；
- 测试素材由 `scripts/stream_practice.ps1` 用 ffmpeg `testsrc2` + `libx264` 自产（320x240 / 25fps / 2s），无需外部文件。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-05-stream-tools/scripts/stream_practice.ps1 build/bin/h264_nalu.exe
```

## 预期输出

`scripts/stream_practice.ps1` 打印 5 个实验段并断言：

1. **导出裸流**：`-bsf:v h264_mp4toannexb -f h264` 产物应以 `00 00 00 01` 起始；
2. **AVCC 佐证**：`ffprobe` 报告 MP4 内为 `is_avc=1/true`（长度前缀），需转 Annex-B；
3. **列 NALU 并识别 I 帧**：`SPS`/`PPS`/`IDR` 均出现，`-g 25` + 50 帧得到 **2 个 I 帧**；
4. **自动/显式 bsf 一致**：不加 `-bsf` 由容器自动补齐，I 帧数与显式方式相同；
5. **踩坑用例**：把 AVCC 长度前缀数据喂给分析器，返回退出码 `2` 并提示缺少 Annex-B 起始码。

`h264_nalu` 典型输出（对 320x240/25fps/2s 测试片）：

```
-----+-------- NALU Table ------+---------
 NUM |    POS  |    IDC |  TYPE |   LEN   |
-----+---------+--------+-------+---------+
    0|        0|  DISPOS|    SEI|      671|
    1|      674| HIGHEST|    SPS|       26|
    2|      703| HIGHEST|    PPS|        6|
    3|      713| HIGHEST|    IDR|     4440|
    4|     5155|    HIGH|  SLICE|     2477|
    ...
Total NALUs: 55
I/IDR frames: 2
SPS=2 PPS=2 SEI=1 SLICE=48 UNKNOWN=0
forbidden_zero_bit: OK
```

> 注意：`mp4toannexb` 会在**每个 IDR 前重复 SPS/PPS**，所以上表 `SPS=2 PPS=2`；这正是裸流可随机 seek 的前提。
> `IDC` 列即 `nal_ref_idc`：`HIGHEST(3)` 常见于参数集/IDR，`DISPOS(0)` 为可丢弃的非参考片。

## 踩坑清单

- **导出裸流必须转 Annex-B**：从 MP4 直接 `-c copy` 得到的是 AVCC（长度前缀）数据，分析器/播放器按起始码搜索会失败；需 `-bsf:v h264_mp4toannexb`；
- **不加 bsf 也可能“能跑”**：现代 ffmpeg 在 `-f h264` 等需要 Annex-B 的封装器上会**自动补 bsf**，容易让人误以为永远不需要；一旦换容器/管道就暴露；
- **3 字节 vs 4 字节起始码**：一帧开头的参数集/首片用 4 字节，其余用 3 字节，简单按 `00 00 01` 即可统一识别；
- **`nal_ref_idc` 与 `nal_unit_type` 在同一字节**：忘记右移 5 位取 idc 会得到错位结果；
- **GUI 分析器版本不匹配**：Elecard/CodecVisa/H.264 分析器对 H.265、较新 profile 支持不一，先确认待分析的是 H.264 还是 H.265；
- **裸流无宽高信息**：Annex-B 本身不含封装层，宽高需从 SPS 解析（见 L2-01）或依赖容器。

## 工具选型（article/041、article/042）

| 工具 | 平台 | 说明 |
|---|---|---|
| 本工程 `h264_nalu` | 跨平台 CLI | 轻量、可脚本化，做 NALU 列表/I 帧定位 |
| Elecard Stream Analyzer | Windows GUI | 码流可视化、逐帧缩略图 |
| CodecVisa | Windows GUI | 语法元素逐层展开 |
| H.264 分析器（雷霄骅） | Windows GUI (MFC) | 基于 h264bitstream，列 NAL 详情 |

> 本模块只做“入门级”的 NALU 列表与 I 帧识别；**SPS/PPS 字段（宽高、帧率、profile）解析**属于 L2-01。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| 编译器 | gcc 16.2.0 (w64devkit 2.11.0) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
