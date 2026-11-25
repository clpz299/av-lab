# L1-07 FFmpeg 滤镜入门：水印 / 裁剪 / 画中画 / 多宫格

素材依据：`article/027`（ffmpeg 滤镜的基本使用）、`article/017`（基于 FFmpeg 的 AVfilter 的例子）。

## 目标

理解 **滤镜链（filterchain）模型**，掌握 5 个高频滤镜（`scale` / `crop` / `pad` / `drawtext` / `overlay`），完成「文字水印 + 图片水印 + 2×2 多宫格」，并踩透三个高频坑。

## 核心概念（脚本实现依据）

- **简单滤镜 vs 复杂滤镜**：单入单出用 `-vf`（`-filter:v`）；多入多出用 `-filter_complex`（`-lavfi`），用 `[标签]` 连接各路流；
- **滤镜链**：`A,B,C` 依次串联，**顺序改变结果**（先缩再补边 ≠ 先补边再缩）；
- **`-1` vs `-2`**：`scale=W:-1` 按比例算高但可能得到**奇数**，遇 `libx264` 报 `height not divisible by 2`；应改用 `-2`（就近取偶数）；
- **`drawtext` 依赖字体**：必须给 `fontfile=`，且 Windows 盘符的冒号需转义为 `\:`、整个值用单引号包裹；
- **`overlay` 坐标系**：`overlay=x:y` 叠在**主视频**上；`W/H` 是主视频宽高，`w/h` 是叠加层宽高；`W-w-10` 即右下角留 10px。

## 实验步骤

```
0) 素材：testsrc2 320x240/25fps/1s + 红色 PNG 水印图
1) 文字水印：drawtext=fontfile='C\:/.../simhei.ttf':...   -> 断言尺寸不变 + 像素改变
2) 图片水印：overlay=W-w-10:H-h-10                         -> 断言尺寸不变 + 像素改变
3) crop=160:120:80:60 -> 160x120 ; pad=400:300 -> 400x300
4) 顺序：scale,pad -> 320x240 ; pad,scale -> 160x120（结果不同）
5) 踩坑：scale=300:-1 失败 ; scale=300:-2 -> 300x226（偶数）
6) 踩坑：fontfile 指向不存在字体 -> 滤镜初始化失败
7) 多宫格：4 路 scale -> hstack/vstack -> 320x240 / 25 帧
```

## 依赖

- 便携工具链（ffmpeg/ffprobe），见仓库根 README；
- 无 C 工具，测试素材由脚本自产；`drawtext` 需要系统字体（脚本自动探测 `simhei.ttf/msyh.ttc/segoeui.ttf/arial.ttf/consola.ttf`）。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-07-filters/scripts/filter_practice.ps1
```

## 预期输出

脚本打印 8 个实验段并断言，最终 `filter_practice PASS`，产物在 `build/_artifacts/L1-07-filters/`。

实测结果：

| 步骤 | 结果 |
|---|---|
| 文字水印 | 320x240，与源帧像素不同 |
| 图片水印 | 320x240，与源帧像素不同 |
| crop / pad | 160x120 / 400x300 |
| scale,pad / pad,scale | 320x240 / 160x120（顺序敏感） |
| scale=300:-1 | 失败：`height not divisible by 2 (300x225)` |
| scale=300:-2 | 300x226（偶数） |
| 缺字体 | 滤镜初始化失败（exit ≠ 0） |
| 2×2 多宫格 | 320x240 / 25 帧 |

## 高频命令速查

```powershell
# 文字水印（Windows 注意 \: 转义 + 单引号）
ffmpeg -i in.mp4 -vf "drawtext=fontfile='C\:/Windows/Fonts/simhei.ttf':fontcolor=white:fontsize=20:text='av-lab':x=10:y=10:box=1:boxcolor=black@0.4" out.mp4

# 图片水印（右下角留 10px）
ffmpeg -i in.mp4 -i logo.png -filter_complex "[0:v][1:v]overlay=W-w-10:H-h-10" out.mp4

# 裁剪 / 补边
ffmpeg -i in.mp4 -vf "crop=160:120:80:60" out.mp4
ffmpeg -i in.mp4 -vf "pad=400:300:(ow-iw)/2:(oh-ih)/2:green" out.mp4

# 等比缩放且保证偶数（切勿用 -1）
ffmpeg -i in.mp4 -vf "scale=300:-2" out.mp4

# 2x2 多宫格
ffmpeg -i a.mp4 -i b.mp4 -i c.mp4 -i d.mp4 -filter_complex "[0:v]scale=160:120[a];[1:v]scale=160:120[b];[2:v]scale=160:120[c];[3:v]scale=160:120[d];[a][b]hstack[top];[c][d]hstack[bot];[top][bot]vstack[out]" -map "[out]" out.mp4
```

## 踩坑清单

- **`drawtext` 在 Windows 的字体路径**：盘符冒号与滤镜参数分隔符冲突，直接写 `fontfile=C:/...` 会报 `No option name near '/Windows/...'`；正确写法 `fontfile='C\:/Windows/Fonts/xxx.ttf'`；
- **`drawtext` 缺字体库/字体文件**：容器若未带 fontconfig 会打印 `Fontconfig error: Cannot load default config file`；`fontfile` 指向不存在的文件则 `Error initializing filters`；
- **`scale` 的 `-1`**：按比例算出的高可能为奇数，`libx264` 拒绝编码；一律用 `-2`；
- **`overlay` 参数顺序**：`[主][叠加]overlay`，`W/H` 指主视频，`w/h` 指叠加层，写反位置就会跑到画面外；
- **滤镜链顺序**：`scale,pad` 与 `pad,scale` 输出完全不同，先想清楚再串；
- **中文字幕乱码**：滤镜字符串编码/字体不支持中文都会花屏或吞字，尽量用支持中文的字体（如 simhei/msyh）并确认脚本为 UTF-8；
- **`nullsrc` 无时间轴**：与真实视频 overlay 时要加 `shortest=1`，否则输出长度异常（见 article/027 案例）。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
| 字体 | C:\Windows\Fonts\simhei.ttf |
