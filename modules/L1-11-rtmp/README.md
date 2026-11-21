# L1-11 直播/点播概念与推拉流初体验

素材依据：[article/010 直播概念和流程框架](file:///d:/workspace/private/audio_video_streaming-main/article/010-直播概念和流程框架.md)

## 目标

理解直播「**推流端 → 服务端 → 播放端**」三方模型与 **RTMP 推流/拉流** 链路。本模块**零外部依赖**：用 ffmpeg 的 `rtmp` listen 模式充当本地 RTMP 服务端，完成一次真实 RTMP 推流→收流，并演示拉流本质、地址结构、连接失败排查与服务端中继分发。

## 核心概念（脚本实现依据）

- **直播三方模型**：推流端（采集/编码/推流）→ 服务端（接收/转码/分发）→ 播放端（拉流/解码/渲染）；本文实验聚焦「推流 → 服务端」与「服务端 → 下游」；
- **推流（publish）**：客户端主动把码流**推送**到服务端，RTMP 地址即 `rtmp://host:port/app/streamName`；
- **拉流（play）**：客户端**连接**服务端并**拉取**码流（一对多分发的基础）；
- **RTMP**：基于 TCP 的实时消息协议（默认端口 **1935**），用 chunk 分包，常封装 FLV 数据；延迟低（1~3s），适合互动直播；
- **GOP Cache**：服务端缓存最近一个 GOP，新观众接入时从最近 I 帧开始发，保证秒开——代价是端到端延迟；
- **`-re`**：按源帧率**实时**推流（模拟直播节奏）；不加则尽快推完，得到的是"文件上传"而非"直播"。

## 实验步骤

```
0) 素材：testsrc2 320x240/25fps/3s + 440Hz 正弦 -> src.mp4（H.264 + AAC）
1) 推流：-re -c copy -f flv rtmp://127.0.0.1:1935/live/test
   服务端：ffmpeg -listen 1 -f flv -i rtmp://... -c copy -f flv live_rec.flv（落地）
2) 拉流本质：推流端 listen tcp://127.0.0.1:8899?listen=1，拉流端连接拉取 -> pull.ts（并发边推边拉）
3) RTMP 地址结构：解析 rtmp://host[:port]/app/streamName，端口缺省 1935
4) 踩坑：连不存在的 RTMP 服务（rtmp://127.0.0.1:1999/...）-> 连接失败
5) 服务端分发：RTMP 中继链 hub(1936) -> edge(1937) -> 边缘落地
```

## 依赖

- 便携工具链（ffmpeg/ffprobe，需含 `rtmp` 协议），见仓库根 README；
- 无 C 工具，本地 RTMP 服务由 `scripts/rtmp_server.ps1`（ffmpeg listen 模式）提供，无需安装 Nginx/SRS；
- 生产部署参考同目录 [nginx-rtmp.conf](file:///d:/workspace/private/audio_video_streaming-main/av-lab/modules/L1-11-rtmp/nginx-rtmp.conf)。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-11-rtmp/scripts/rtmp_practice.ps1

# 手动起一个本地 RTMP 服务（收流并落地）
powershell -NoProfile -File modules/L1-11-rtmp/scripts/rtmp_server.ps1 -Port 1935 -Stream test -Loop
```

## 预期输出

脚本打印 6 个实验段并断言，最终 `rtmp_practice PASS`，产物在 `build/_artifacts/L1-11-rtmp/`。

实测（320x240/25fps/3s 素材）：

| 步骤 | 结果 |
|---|---|
| RTMP 推流 + 服务端收流 | `live_rec.flv` 151733 B，h264 + aac，时长 3.098s |
| 并发边推边拉（TCP） | `pull.ts` 173712 B，h264 + aac |
| RTMP 地址解析 | `rtmp://127.0.0.1/live/test` → port 缺省 **1935**；`...:1936/...` → 1936 |
| 连接不存在的 RTMP | exit **-138**，`Cannot open connection tcp://127.0.0.1:1999` |
| 中继链 hub→edge | 边缘 `chain_rec.flv` 151733 B，h264 + aac |

## 高频命令速查

```powershell
# 推流（模拟直播：-re 按实时帧率推；换编码用 -c:v libx264）
ffmpeg -re -i src.mp4 -c copy -f flv rtmp://127.0.0.1:1935/live/test

# 本地 RTMP 服务：以 listen 模式收流并落地（本工程用法）
ffmpeg -listen 1 -f flv -i rtmp://127.0.0.1:1935/live/test -c copy -f flv live_rec.flv

# 播放/拉流（本地播放需要 ffplay 及可用的 RTMP play 服务，如 Nginx-rtmp/SRS）
ffplay rtmp://127.0.0.1:1935/live/test

# 通用「服务端/播放端」模型：一端 listen，另一端连接拉取
ffmpeg -re -i src.mp4 -c copy -f mpegts "tcp://127.0.0.1:8899?listen=1"   # 推流端
ffmpeg -i "tcp://127.0.0.1:8899" -c copy pull.ts                          # 拉流端

# 服务端中继分发（hub 收流后转发到 edge）
ffmpeg -listen 1 -f flv -i rtmp://127.0.0.1:1936/live/hub -c copy -f flv rtmp://127.0.0.1:1937/live/edge
```

## 踩坑清单

- **ffmpeg 的 `-listen 1` 只是"收流服务"，不支持并发 play**：它能以 RTMP 服务端身份接一个推流端，但**不接受"拉流(play)"客户端**（实测并发 play 报 `Cannot open connection`）。要做多观众拉流分发，必须上 **Nginx-rtmp / SRS**（见 `nginx-rtmp.conf`）；
- **推流地址写错/端口未监听**：典型报错 `Cannot open connection tcp://... <host>:<port>` 与 `Error opening output ...rtmp://...`（exit=-138）。排查顺序：端口是否监听（默认 1935）→ 防火墙放行 → URL 的 `app`/`streamName` 是否与服务端配置一致；
- **`-re` 漏了就不是直播**：不加 `-re`，ffmpeg 会把整个文件尽快推完（脱离实时节奏），看起来"直播瞬间结束"；
- **地址结构记牢**：`rtmp://host:port/app/streamName`，**端口可省（默认 1935）**，`app` 对应服务端 `application` 段，`streamName` 是流标识；OBS 推流地址/串流密钥就是这两段的拆分；
- **服务端未监听时是"连接失败"而非"协议错误"**：本质是 TCP 连不上，与 RTMP 协议内容无关。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| ffmpeg | N-129130 (BtbN win64-gpl)，含 `rtmp/rtmps/rtmpt` 协议 |
| 本地 RTMP 服务 | ffmpeg `-listen 1`（零依赖），端口 1935 |
