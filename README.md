# av-lab · 音视频实验室工程

采用**统一实验室工程 + 模块化子项目**模式：所有模块共用一套构建系统（CMake + CTest）、素材库与工具链脚本。

## 目录结构

```
av-lab/
├── CMakeLists.txt      # 顶层构建
├── tools/              # 工具链解析、一键准备(bootstrap)、构建、素材生成脚本
├── assets/             # 公共测试素材（自动生成，不入库）
├── modules/            # 每个选题一个可独立编译/测试的模块
│   ├── L1-01-env/      # 环境搭建与首个转换实验
│   ├── L1-02-cli/      # ffmpeg/ffplay/ffprobe 命令行实战
│   ├── L1-03-yuv-tools/ # RGB/YUV 像素数据处理工具集
│   ├── L1-04-pcm-tools/ # PCM 音频采样数据处理工具集
│   ├── L1-05-stream-tools/ # H.264 码流分析工具入门（NALU 列表 / I 帧识别）
│   ├── L1-06-media-convert/ # 图片序列 ↔ 视频、视频转 GIF
│   ├── L1-07-filters/  # 滤镜入门：水印 / 裁剪 / 画中画 / 多宫格
│   ├── L1-08-concepts/ # 核心概念压测：帧率 / 码率 / 分辨率 / GOP
│   ├── L1-09-mp4-mux/  # MP4 生成与封装入门（解封装 / 裸流 / box 结构）
│   ├── L1-10-format/   # 常见格式识别与转换（转封装矩阵 / 编码 vs 封装）
│   ├── L1-11-rtmp/     # 直播推拉流初体验（本地 RTMP 服务 / 推流 / 中继）
│   ├── L1-12-hls/      # HLS 切片与 m3u8 播放（TS 切片 / 关键帧对齐 / 滑动窗口）
│   ├── L1-13-webrtc/   # WebRTC 1v1 通话（零依赖信令服务 / 前端 demo / headless E2E）
│   ├── L1-14-miniprogram/ # 微信小程序音视频初探（live-pusher / live-player demo）
│   └── L1-15-quality/  # 客观质量指标（PSNR / SSIM / SNR 工具 + 多码率曲线）
└── docs/               # 设计文档与踩坑复盘
```

## 快速开始（Windows）

```powershell
# 0) 首次：一键准备便携工具链（已就绪则自动跳过）
pwsh -NoProfile -File tools/bootstrap.ps1

# 1) 一键构建 + 跑全量测试
pwsh -NoProfile -File tools/build.ps1
```

## 工具链

工具链以**便携方式**置于仓库同级目录 `.avtoolchain/`（不进版本库）：

| 组件 | 版本 | 路径 |
|---|---|---|
| gcc / g++ | 16.2.0 | `.avtoolchain/w64devkit/w64devkit/bin` |
| cmake | 4.5.1 | `.avtoolchain/cmake/cmake-4.5.1-windows-x86_64/bin` |
| ffmpeg / ffprobe / ffplay | N-129130 | `.avtoolchain/ffmpeg/ffmpeg-master-latest-win64-gpl/bin` |
