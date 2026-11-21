# L1-13 WebRTC 快速上手：浏览器 1v1 通话 Demo

素材依据：[article/019 WebRTC能给我带来什么？](file:///d:/workspace/private/audio_video_streaming-main/article/019-WebRTC能给我带来什么？.md)、[practice_project/README（RTCStartupDemo）](file:///d:/workspace/private/audio_video_streaming-main/practice_project/README.md)

## 目标

用**一个零依赖的信令服务器 + 一个纯 WebRTC 官方 API 的前端页面**，把两个标签页连成一次 1v1 音视频通话；并把这套链路变成可自动化回归的测试——信令协议级测试（不需要浏览器）与端到端通话测试（headless 浏览器 + 假摄像头）。

## 核心概念（脚本实现依据）

- **WebRTC 只解决"怎么传"，不解决"怎么找到对方"**：规范里定义了媒体传输（SRTP over DTLS over ICE/UDP）、编解码协商（SDP），但**没有定义双方如何交换 SDP 与 ICE 候选**——这就是**信令（signaling）**，必须由业务自己做，本项目用 WebSocket 实现；
- **三个核心 API**：`getUserMedia()` 采集本地音视频；`RTCPeerConnection` 建立点对点连接、协商编解码、收发 RTP；信令通道（WebSocket）负责搬运 `offer`/`answer`/`candidate`；
- **SDP 是"能力说明书"**：`createOffer()` 生成本地能力描述，`setLocalDescription()` 后开始收集 ICE 候选，`setRemoteDescription()` 应用对端描述；
- **ICE 候选是"边收边发"的**：`onicecandidate` 会**多次**触发（host / srflx / relay 候选陆续产生），每拿到一个就要立刻经信令发给对方——**只在 ICE 完成后统一发会显著增加建连延迟，甚至死等**；
- **媒体不会自动播放**：必须自己把 `ontrack` 收到的轨道塞进 `<video>`（或 `MediaStream`）才会渲染，这是新手最常见的"连上了但没画面"；
- **安全上下文是硬约束**：`getUserMedia` 只在 https 或 `http://localhost`、`http://127.0.0.1` 这类"可信来源"可用；用局域网 IP（如 `http://192.168.1.10`）打开页面会直接拿不到摄像头；
- **只有 host 候选时跨网段必然失败**：本 Demo 默认不配 STUN/TURN，双方都只能给出自己网卡的 host 候选；**同机/同局域网可通，跨 NAT 必须引入 STUN 才能得到 srflx 候选，对称 NAT 下还需 TURN 中继**；
- **服务端只是"信令搬运工"**：媒体是点对点直连的，信令服务器不转发媒体；1v1 房间上限 2 人，多人需走 SFU/MCU。

## 实验步骤

```
1) 信令协议测试（Node 内置 WebSocket 客户端冒充终端）：
   单端加入 / 两端到齐都收到 ready / 后加入者为 offerer /
   offer 中继 / answer 中继 / ICE 候选中继 / 第三人被拒(满员) / 对端离开收到 bye /
   连接不存在的信令服务应失败（对应"信令服务器没启动"的踩坑）
2) 端到端通话测试（headless Chromium）：
   起信令服务器 -> 起浏览器(--use-fake-device-for-media-stream) ->
   CDP 打开两个标签页自动加入同房间 -> 轮询 window.__state 断言：
   本地采集 2 轨 / peerConnection connected / iceConnected /
   收到对端 2 轨 / 远端视频有解码尺寸 / 有真实 RTP 字节流动 / 发起-应答角色正确
3) 人工体验：node server/signal_server.js 8613，两个标签页开 ?room=demo
```

## 依赖

- **Node.js**（运行信令服务器与测试；用 Node 内置 `WebSocket` 客户端，**不需要 npm install**）；
- **Chromium 系浏览器**（Chrome/Edge/Chromium），仅端到端测试需要；缺失时该步自动跳过；
- 信令服务器为纯 `http` + `crypto` 手写 RFC6455 帧，**零第三方依赖**。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-13-webrtc/scripts/webrtc_practice.ps1

# 手动起服务、手动体验
node modules/L1-13-webrtc/server/signal_server.js 8613
# 浏览器两个标签页打开：http://127.0.0.1:8613/?room=demo
```

## 预期输出

脚本打印 3 个实验段并断言，最终 `L1-13 WebRTC 实验全部通过`，产物（日志）在 `build/_artifacts/L1-13-webrtc/`。

实测（Windows 10 / Chrome，假摄像头 640x480）：

| 步骤 | 结果 |
|---|---|
| 信令协议测试 | 9/9 通过（含满员拒绝、离线连接失败） |
| 端到端角色分配 | 一端 `offerer`、一端 `answerer` |
| peerConnection / iceConnection | 两端均 `connected` |
| 本地采集轨道 | 两端各 2 轨（video+audio） |
| 远端轨道 / 画面尺寸 | 两端各 2 轨，640x480 |
| inbound-rtp bytesReceived | 约 51951 / 68627 字节（确有媒体在流动） |

## 高频命令速查

```javascript
// 1) 采集
const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
localVideo.srcObject = stream;

// 2) 建连
const pc = new RTCPeerConnection({ iceServers: [] });       // 跨 NAT 需填 STUN/TURN
stream.getTracks().forEach((t) => pc.addTrack(t, stream));
pc.ontrack = (ev) => remoteStream.addTrack(ev.track);       // 不挂 video 就没画面
pc.onicecandidate = (ev) => ev.candidate && signal({ type: 'ice', payload: ev.candidate });

// 3) 协商（发起方）
const offer = await pc.createOffer();
await pc.setLocalDescription(offer);
signal({ type: 'signal', payload: pc.localDescription });

// 3') 协商（应答方）
await pc.setRemoteDescription(remoteOffer);
const answer = await pc.createAnswer();
await pc.setLocalDescription(answer);
signal({ type: 'signal', payload: pc.localDescription });

// 4) 对端候选
await pc.addIceCandidate(candidate);
```

## 踩坑清单

- **信令服务器必须先启动**：只写前端不写信令，`WebSocket` 直接连不上，页面停在"连接中"；协议测试里专门断言了「连不存在的信令服务会失败」；
- **不是 https / localhost 就没有 `navigator.mediaDevices`**：用局域网 IP 访问页面时 `getUserMedia` 直接不可用（`navigator.mediaDevices` 为 `undefined`），必须先解决 HTTPS 或改用 `127.0.0.1`；
- **只有 host 候选 = 跨网段连不通**：不配 STUN/TURN 时，局域网外/跨 NAT 必然失败；症状是 `iceConnectionState` 长期停在 `checking`/`failed`，此时要去看 `onicecandidateerror`；
- **`ontrack` 不处理 = 黑屏**：连接状态是 `connected`、`getStats()` 也有字节，但 `<video>` 始终黑——因为远端流没被挂上去；
- **`onicecandidate` 里判空**：候选收集结束时会回调一次 `candidate === null`，直接 `JSON.stringify(ev.candidate)` 发过去会让对端 `addIceCandidate(null)` 报错；
- **自动播放策略**：Chrome 默认禁止带声音的自动播放，演示页要加 `muted` 或由用户手势触发；headless 测试用 `--autoplay-policy=no-user-gesture-required`；
- **信令服务器不转发媒体**：它只搬 SDP/ICE；把服务器关掉后已建立的连接仍能继续通话（媒体是 P2P 直连的），这常被误解为"服务器在转发流"；
- **headless 只能开一个命令行 target**：`chrome --headless=new url1 url2` 会报 `Multiple targets are not supported in headless mode`，第二个标签页要用 CDP 的 `PUT /json/new` 创建。

## 测试实现说明（为什么这么测）

- **信令与媒体分层测试**：信令部分完全用 Node 客户端覆盖（快、稳、无浏览器依赖）；媒体部分才动用真实浏览器，用 `--use-fake-device-for-media-stream` 提供确定性假摄像头，避免 CI 上没有摄像头；
- **判据不只看 `connected`**：断言里额外要求 `bytesReceived > 0` 和远端视频解码尺寸 > 0，否则"信令通了但媒体没通"会被误判为通过；
- **浏览器缺失自动跳过**：端到端测试找不到 Chromium 时输出 `SKIP` 并以 0 退出，保证无浏览器环境也能跑通其余用例；可通过环境变量 `AVWEB_BROWSER` 指定浏览器路径。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| Node.js | v22.23.4（内置 `WebSocket` 客户端，无需 npm 包） |
| 浏览器 | Google Chrome / Microsoft Edge（headless，`--use-fake-device-for-media-stream`） |
| 假摄像头输出 | 640x480 |
| 信令服务器 | 自研零依赖（http + crypto 手写 WebSocket 帧），默认端口 8613 |
