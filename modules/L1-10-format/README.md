# L1-10 常见音视频格式识别与转换

素材依据：[case_interview/001 面试题10 常见的音视频格式有哪些](file:///d:/workspace/private/audio_video_streaming-main/case_interview/001-README.md)

## 目标

搞清「**封装格式（容器）**」与「**编码格式**」是两件独立的事：先识别文件的容器与编码，再做 **-c copy 无损转封装**（mp4/flv/mkv/avi/ts/mov 六种容器矩阵）；踩透三个格式坑：编码 vs 封装混淆、容器不支持某编码导致转封装失败、MKV 多音轨选择。

## 核心概念（脚本实现依据）

- **容器（format_name）≠ 编码（codec_name）**：容器是「盒子」（MP4/FLV/MKV/AVI/TS…），编码是「盒中之物」（H.264/H.265/MPEG-4、AAC/MP3…）。同一个 MP4 里既可以是 H.264，也可以是 MPEG-4；说“MP4 编码”是概念错误；
- **ffprobe 的 format_name 可能是别名集合**：MP4/MOV 共用一套 demuxer，`format_name` 会返回 `mov,mp4,m4a,3gp,3g2,mj2`；MKV 返回 `matroska,webm`；TS 返回 `mpegts`；
- **转封装（remux）= `-c copy`**：只换容器、不重编码，故**画质无损、速度极快**；代价是源编码必须被目标容器支持；
- **转码（transcode）= 重新编码**：如 `-c:v libx264`，会解码再编码，画质有损、耗时，但可跨容器自由选择编码；
- **容器的编码白名单**：MP4 不支持 VP8（`codec not currently supported in container`）；MKV/TS 支持更宽松（MKV 可多音轨、PCM 等）。

## 实验步骤

```
0) 素材：testsrc2 320x240/25fps/2s + 440Hz 正弦 -> src.mp4（H.264 + AAC）
1) 格式识别：把 src.mp4 重编码为 mpeg4 -> 仍是 MP4 容器，编码变成 mpeg4（证明封装≠编码）
2) 转换矩阵：-c copy 转封装到 mp4/flv/mkv/avi/ts/mov，逐一探测 容器 + 编码 + 体积
3) 踩坑：VP8 -c copy -> mp4 失败（容器不支持该编码），再用 -c:v libx264 重编码修复
4) 踩坑：MKV 多音轨：造 2 条音轨的 mkv，用 -map 0:a:1 选第 2 条导出
5) 汇总：导出 format_matrix.csv
```

## 依赖

- 便携工具链（ffmpeg/ffprobe），见仓库根 README；
- 无 C 工具，素材由脚本自产，格式识别全部走 ffprobe。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-10-format/scripts/format_practice.ps1
```

## 预期输出

脚本打印 5 个实验段并断言，最终 `format_practice PASS`，产物在 `build/_artifacts/L1-10-format/`。

实测（320x240/25fps/2s 素材）：

| 目标容器 | format_name | 编码 | 体积(B) |
|---|---|---|---|
| mp4 | `mov,mp4,m4a,3gp,3g2,mj2` | video:h264 audio:aac | 99329 |
| flv | `flv` | video:h264 audio:aac | 99142 |
| mkv | `matroska,webm` | video:h264 audio:aac | 98071 |
| avi | `avi` | video:h264 audio:aac | 137322 |
| ts | `mpegts` | video:h264 audio:aac | 113176 |
| mov | `mov,mp4,m4a,3gp,3g2,mj2` | video:h264 audio:aac | 99380 |

| 验证点 | 结果 |
|---|---|
| 重编码 mpeg4.mp4 | 容器仍为 MP4，编码 `video:mpeg4`（与 h264 不同） |
| VP8 -c copy -> mp4 | 失败 `exit=-22`，`Could not find tag for codec vp8 ... not currently supported in container` |
| VP8 重编码修复 | `-c:v libx264` 后成功，编码 `video:h264` |
| MKV 多音轨 | 2 条音轨；`-map 0:a:1` 导出第 2 条（17338 B） |

## 高频命令速查

```powershell
# 识别：先看容器（封装）
ffprobe -v error -show_entries format=format_name,format_long_name -of default=nw=1:nk=1 in.mp4

# 识别：再看每条流的编码
ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 in.mp4
ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 in.mp4

# 转封装（无损，只换容器）
ffmpeg -i in.mp4 -c copy out.mkv

# 转码（有损/耗时，跨容器换编码）
ffmpeg -i in.mp4 -c:v libx264 -pix_fmt yuv420p -c:a aac out.mp4

# MKV 多音轨：列出所有轨
ffprobe -v error -show_entries stream=index,codec_type,codec_name -of csv=p=0 in.mkv
# 选第 2 条音轨导出
ffmpeg -i in.mkv -map 0:a:1 -c copy out.wav
```

## 踩坑清单

- **把编码当封装**：`format_name` 是容器，`codec_name` 是编码。看到 `mov,mp4,...` 只能说明容器属 MP4 家族，不代表视频编码是 H.264；
- **ffprobe CSV 字段顺序陷阱**：`-show_entries stream=codec_type,codec_name -of csv=p=0` 输出的列顺序由 **ffprobe 内部字段顺序**决定（实测是 `codec_name` 在前），**不随请求顺序变化**；要稳妥就按 `-select_streams v/a` 分开探测，或改用 `default=nw=1:nk=1`；
- **转封装失败 = 容器不支持源编码**：`Could not find tag for codec vp8 in stream #0, codec not currently supported in container`（exit=-22）。此时要么换支持该编码的容器（VP8→WebM/MKV），要么重编码为目标容器支持的编码（`-c:v libx264`）；
- **转封装 vs 转码的代价**：能用 `-c copy` 就别重编码；只有跨容器遇到编码白名单限制、或需要换编码器时才转码；
- **多轨文件默认只取第一条**：MKV 里多条音频/字幕轨，`ffmpeg -i in.mkv out.wav` 默认只导第 1 条；要用 `-map 0:a:1` 按「流类型:第几条」显式指定；
- **`-map` 是精确选择流的手段**：`0:v`（第 0 输入的全部视频）、`0:a:1`（第 0 输入的第 2 条音频），不写 `-map` 时 ffmpeg 用默认选流规则（各类型只选一条，且偏好高分辨率/更多声道）。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
