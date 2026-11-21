# L1-02 ffmpeg / ffplay / ffprobe 命令行实战

## 目标

用三条命令走完一个最小闭环：**探测信息 → 提取音视频 → 播放验证**，并沉淀一份可复用的命令速查。

## 实验链路

`scripts/cli_practice.ps1` 依次完成：

1. 用 `lavfi` 生成测试源 `src.mp4`（320x240@15 + 440Hz 正弦音轨，5s，无需外部素材）；
2. `ffprobe` 打印流信息（index/type/codec/分辨率/采样率/声道）；
3. `ffmpeg -map ... -c copy` 分离提取 **纯视频** `video_only.mp4` 与 **纯音频** `audio_only.m4a`；
4. `ffmpeg -vf scale=160:120` 生成缩略版 `scaled.mp4`；
5. `ffprobe` 复核：确认 `video_only` 仅含视频流、`audio_only` 仅含音频流、缩放分辨率为 160x120。

命令速查见 `scripts/cheatsheet.ps1`。

## 依赖

- 便携工具链位于仓库同级 `.avtoolchain/`（见根目录 README）；
- 无需联网。

## 构建与运行

```powershell
# 在 av-lab/ 下执行（跑全量测试）
pwsh -NoProfile -File tools/build.ps1

# 或单独运行
pwsh -NoProfile -File modules/L1-02-cli/scripts/cli_practice.ps1
pwsh -NoProfile -File modules/L1-02-cli/scripts/cheatsheet.ps1
```

手工播放验证（需图形界面）：

```powershell
# 用工具链里的 ffplay 播放上一步产物
& "$env:AVTOOLCHAIN\ffmpeg\ffmpeg-master-latest-win64-gpl\bin\ffplay.exe" build/_artifacts/L1-02-cli/src.mp4
```

## 预期输出

- `L1-02.cli_practice`：打印每条执行命令与流信息，最终输出 `cli_practice PASS`，产物位于 `build/_artifacts/L1-02-cli/`；
- `L1-02.cheatsheet`：打印分组命令清单后输出 `cheatsheet OK`。

## 踩坑清单

- **参数位置**：`-vf`/`-ss` 放在 `-i` 之前与之后语义不同（输入侧剪切 vs 输出侧）；`-map` 必须写在输出文件之前。
- **`-c copy` 的容器兼容**：把 AAC 流直接 copy 进某些容器会失败，需换成 `.m4a`/`.aac`。
- **`ffplay -vfscale=...` 写法错误**：正确为 `-vf scale=...`（`-vf` 与值之间要有空格）。
- **中文路径**：Windows 下 ffmpeg 对非 ASCII 路径偶发失败，建议产物路径只用 ASCII。
- **ffplay 无窗口**：缺少 SDL 或运行在无图形环境时会报错，属正常，用 `ffmpeg`/`ffprobe` 做自动化验证即可。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
