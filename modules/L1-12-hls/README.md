# L1-12 HLS 切片与 m3u8 播放实验

素材依据：[article/008 流媒体协议介绍（HLS 段）](file:///d:/workspace/private/audio_video_streaming-main/article/008-流媒体协议介绍.md)、[case_interview/002 第60题](file:///d:/workspace/private/audio_video_streaming-main/case_interview/002-README.md)

## 目标

把 MP4 切成 **m3u8 + TS 切片**（HLS），用 `m3u8` 解析小工具看懂播放列表结构，并以「播放器视角」经 m3u8 拉流回放；踩透三个坑：**hls_time 受 GOP 影响**、**非关键帧切片导致花屏**、**直播滑动窗口**。

## 核心概念（脚本实现依据）

- **HLS = 用点播的技术实现直播**：服务端把流切成一个个很短的 TS 文件，客户端不断下载并顺序播放，实现直播；传输走 **HTTP**（默认端口 8080，见面试题60），天然穿透防火墙/代理；
- **m3u8 是播放列表（文本索引）**：`#EXTM3U` 开头，`#EXT-X-TARGETDURATION`（最大切片时长）、`#EXT-X-MEDIA-SEQUENCE`（首个切片的序号）、`#EXT-X-PLAYLIST-TYPE:VOD|EVENT`、`#EXTINF`（每条切片时长+URI）、`#EXT-X-ENDLIST`（列表结束）；
- **切片必须是关键帧对齐**：播放器可从任意切片独立起播的前提是**每片以 IDR 关键帧开头**；因此 `-hls_time` 只是**目标值**，实际切片点在「≥ 目标时长后的下一个关键帧」；
- **GOP 决定切片粒度**：GOP（`-g`）比 `-hls_time` 大时，切片被拉长到 GOP 长度，`-hls_time` 形同失效；
- **TS 封装**：MPEG-TS 定长 188 字节包，以同步字节 `0x47` 开头；切片从 MP4（AVCC）转 TS 时，ffmpeg 会自动做 `h264_mp4toannexb`（起始码）；
- **直播用滑动窗口**：`-hls_list_size N` 只保留最近 N 片并递增 `#EXT-X-MEDIA-SEQUENCE`；`-hls_list_size 0` 表示保留全部（点播 VOD）。

## 实验步骤

```
0) 素材：testsrc2 320x240/25fps/8s + 440Hz 正弦 -> src.mp4（GOP=1s，关键帧每 1s 一个）
1) 切片：-c copy -hls_time 2 -hls_list_size 0 -hls_playlist_type vod -> vod.m3u8 + vod_XXX.ts
2) TS 段结构：首字节 0x47，长度是 188 的整数倍
3) 播放器视角：ffmpeg -i vod.m3u8 -c copy -> 回放出 2 流、时长≈8s
4) 踩坑：源 GOP=10s 时 hls_time=2 失效 -> 只切出 1 段、TARGETDURATION=8
5) 踩坑：-hls_flags split_by_time 强行按时间切 -> 出现不含关键帧的段（花屏）
6) 直播滑动窗口：-hls_list_size 3 -> 只留 3 片，MEDIA-SEQUENCE 前移，无 PLAYLIST-TYPE
7) 用 m3u8_info.ps1 解析并打印播放列表
```

## 依赖

- 便携工具链（ffmpeg/ffprobe），见仓库根 README；
- 无 C 工具；m3u8 由 `scripts/m3u8_info.ps1` 纯文本解析。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-12-hls/scripts/hls_practice.ps1

# 解析任意 m3u8
powershell -NoProfile -File modules/L1-12-hls/scripts/m3u8_info.ps1 -M3u8 out.m3u8
```

## 预期输出

脚本打印 8 个实验段并断言，最终 `hls_practice PASS`，产物在 `build/_artifacts/L1-12-hls/`。

实测（320x240/25fps/8s 素材）：

| 步骤 | 结果 |
|---|---|
| VOD 切片（GOP=1s） | 4 段，每段 2.000000s，TARGETDURATION=2，PLAYLIST-TYPE:VOD，含 ENDLIST |
| 每段关键帧数 | 均为 2（段首即关键帧，可独立解码） |
| TS 段结构 | `vod_000.ts` 首字节 `0x47`，106032 B（188 整数倍） |
| 经 m3u8 回放 | 2 条流，时长 8.034s |
| GOP=10s 切片 | **1 段**，TARGETDURATION=**8**（hls_time=2 失效） |
| split_by_time 切片 | 4 段，各段关键帧数 `[1, 0, 0, 0]`（后 3 段无关键帧 → 花屏） |
| 滑动窗口 list_size=3 | 3 段，MEDIA-SEQUENCE=1，无 PLAYLIST-TYPE |

## 高频命令速查

```powershell
# 点播 VOD：切成 m3u8 + ts（-c copy 不重编码）
ffmpeg -i src.mp4 -c copy -f hls -hls_time 2 -hls_list_size 0 -hls_playlist_type vod `
       -hls_segment_filename seg_%03d.ts out.m3u8

# 直播：滑动窗口只保留最近 3 片，不写 ENDLIST
ffmpeg -re -i src.mp4 -c copy -f hls -hls_time 4 -hls_list_size 3 live.m3u8

# 关键帧对齐（切片可控的前提）：固定 GOP 与场景切换
ffmpeg -i src.mp4 -c:v libx264 -g 50 -keyint_min 50 -sc_threshold 0 -c:a aac -f hls ...

# 播放/拉流（本地播放 m3u8，或经 HTTP 服务提供）
ffplay out.m3u8
ffmpeg -i out.m3u8 -c copy replay.mp4
```

## 踩坑清单

- **`-hls_time` 是"目标"不是"硬切"**：ffmpeg 只在关键帧处切片。源 `-g 250`（GOP=10s）时，`-hls_time 2` 根本切不动，只能出 1 段、`TARGETDURATION` 被迫增大到 8。**要做 2s 切片，源的 GOP 必须 ≤ 2s**；
- **切片必须从关键帧开始**：`-hls_flags split_by_time` 允许"到点就切、不看关键帧"，实测切出的后 3 段关键帧数为 0——这类段无法独立解码，播放器**从该段起播或切换时会花屏/黑屏**。生产切片务必保证 GOP 对齐；
- **`-sc_threshold 0` 不可忘**：开启场景切换检测时，编码器会在场景变化处插入额外关键帧，破坏 GOP 的规律性，导致切片时长抖动；
- **`-hls_list_size 0` vs `N`**：0 = 保留全部切片（点播）；N = 滑动窗口只留最近 N 片（直播），`MEDIA-SEQUENCE` 会递增；直播模式的 m3u8 **没有 `#EXT-X-ENDLIST`**；
- **本地 m3u8 的路径是相对的**：`#EXTINF` 后的切片名相对 m3u8 所在目录解析；把 m3u8 和 ts 分开存放或改名，会导致播放器找不到切片；
- **浏览器/播放器兼容**：Safari/原生 iOS 支持 HLS；Chrome 需 hls.js（MSE）；本地 `file://` 打开 m3u8 常被 CORS/协议限制拦截，**建议用 `http://` 提供**。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| ffmpeg | N-129130 (BtbN win64-gpl)，含 `hls` 复用器与 `hls` 解复用器 |
