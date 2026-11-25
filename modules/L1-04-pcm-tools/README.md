# L1-04 PCM 音频采样数据处理工具集

素材依据：`article/021 视音频数据处理：PCM音频采样数据处理`

## 目标

用一个单文件命令行工具 `pcm_tools` 覆盖 PCM16LE 的常见处理，理解 **采样位数 / 声道交错 / 大小端**，并完成"裸 PCM ↔ WAVE 封装"闭环。

## 核心概念（工具实现依据）

- **16LE**：每样值 2 Byte，小端存储（低位在低地址）；
- **交错存储**：双声道按 `L,R,L,R...` 排列，故一帧 = 4 Byte；
- **取值域**：16bit 有符号 `-32768~32767`；转 8bit 需 `>>8` 再 `+128` 映射到 `0~255`。

## 子命令

```
split_lr    <in.pcm> <out_l.pcm> <out_r.pcm>            分离左右声道
half_left   <in.pcm> <out.pcm>                          左声道音量减半
doublespeed <in.pcm> <out.pcm>                          抽奇数帧 -> 速度翻倍
to_pcm8     <in.pcm> <out.pcm>                          PCM16LE -> PCM8
cut_mono    <in.pcm> <start> <dur> <out.pcm> <out.txt>  单声道截取 + 样值清单
to_wave     <in.pcm> <channels> <sample_rate> <out.wav> 封装为 WAVE
```

## 依赖

- 便携工具链（gcc + ffmpeg），见仓库根 README；
- 测试素材由 `scripts/pcm_practice.ps1` 用 ffmpeg `sine` 自产（44.1kHz / 0.2s），无需外部文件。

## 构建与运行

```powershell
pwsh -NoProfile -File tools/build.ps1

# 单独跑本模块测试
pwsh -NoProfile -File modules/L1-04-pcm-tools/scripts/pcm_practice.ps1 build/modules/L1-04-pcm-tools/pcm_tools.exe
```

## 预期输出

`scripts/pcm_practice.ps1` 打印 6 个实验段并断言：

- **分离**：左右声道与原交错数据逐字节对应；
- **减半**：左声道 `= 原值 / 2`（向零取整），右声道不变；
- **翻倍**：产物为源帧数的 `floor` 一半，首帧来自源第 1 帧；
- **PCM8**：每样值 `= floor(s16/256) + 128`；
- **截取**：按 `cnt > start && cnt <= start+dur` 取 `dur` 个样值，首尾索引正确；
- **WAVE**：文件大小 `44 + 数据长度`，ffprobe 复核采样率/声道，并**往返解码**与原 PCM 完全一致。

最终打印 `pcm_practice PASS`，产物在 `build/_artifacts/L1-04-pcm-tools/`。

## 踩坑清单

- **`while(!feof(fp))` 多读一次**：素材写法在末尾会重复处理最后一帧，导致输出多出一个样值；应改为"先读返回个数、再判定"（本工具已修正）。
- **`dwAvgBytesPerSec` 少乘声道数**：素材为 `采样率 * sizeof(short)`，正确应为 `采样率 * 声道数 * 2`，否则部分播放器按错误码率解读（本工具已修正）。
- **字节序**：把 16LE 数据当 big-endian 读会得到噪声；跨平台要显式按小端拼装。
- **强转指针**：`(short*)unsigned_char_buf` 依赖对齐，跨平台可能崩溃；应整块读入 `short` 数组或用 `memcpy`（本工具用 `short` 数组读取）。
- **有符号/无符号**：16bit→8bit 若不 `+128` 偏移，负数会被当作大正数，听到爆音。
- **截取边界**：`cnt > start`（非 `>=`）意味着实际从 `start+1` 开始，容易差一位。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| 编译器 | gcc 16.2.0 (w64devkit 2.11.0) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
