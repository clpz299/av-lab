# L1-06 图片与视频互转、视频转 GIF

素材依据：`video/001`、`video/040`（序列帧合成 / GIF 生成），并参考 `article/026`（如何生成 mp4 文件）。

## 目标

打通 **视频 → 图片序列 → 视频** 的双向转换，并把 MP4 转成**循环 GIF**；过程中踩透三个高频坑：像素格式、帧序号连续性、GIF 调色板。

## 核心概念（脚本实现依据）

- **image2 复用器**：`-f image2` 用 `%04d` 模板读写序列帧，序号**从 1 开始**、且**必须连续**；
- **`-framerate` vs `-r`**：读序列帧时用 `-framerate` 设定输入帧率（`-r` 在输入前语义不同，易踩坑）；
- **像素格式**：H.264 主流播放器只认 `yuv420p`；RGB(PNG) 直接编码默认得到 `yuv444p`，会导致部分播放器**黑屏**；
- **GIF 调色板**：GIF 最多 256 色，用 `palettegen`+`paletteuse` 两遍法生成**全局调色板**，画质/观感优于逐帧量化；`-loop 0` 表示无限循环。

## 实验步骤

```
0) ffmpeg 自产 MP4 素材（testsrc2 320x240 / 25fps / 2s = 50 帧）
1) 视频 -> PNG 序列：-f image2 seq/%04d.png            -> 断言 50 张、0001..0050
2) 序列 -> MP4：-framerate 25 -i %04d.png -pix_fmt yuv420p -> 断言 50 帧 + yuv420p
3) 踩坑：省略 -pix_fmt                                  -> 断言得到 yuv444p
4) 踩坑：删掉 0025.png 再合成                            -> 断言在空洞处截断为 24 帧
5) MP4 -> 循环 GIF：默认 vs palettegen/paletteuse       -> 断言 GIF89a / NETSCAPE2.0 / 30 帧
```

## 依赖

- 便携工具链（ffmpeg/ffprobe），见仓库根 README；
- 无 C 工具，测试素材由脚本用 ffmpeg `testsrc2` 自产，无需外部文件。

## 构建与运行

```powershell
powershell -NoProfile -File tools/build.ps1

# 单独跑本模块测试
powershell -NoProfile -File modules/L1-06-media-convert/scripts/image_video_practice.ps1
```

## 预期输出

脚本打印 6 个实验段并断言，最终 `image_video_practice PASS`，产物在 `build/_artifacts/L1-06-media-convert/`。

实测（320x240 测试片）：

| 步骤 | 结果 |
|---|---|
| 拆序列 | 50 张 PNG（0001.png ~ 0050.png） |
| 合成（显式 420p） | `nb_frames=50`, `pix_fmt=yuv420p` |
| 合成（默认） | `pix_fmt=yuv444p`（黑屏坑） |
| 缺 0025.png | `nb_frames=24`（空洞截断） |
| GIF | 均 `GIF89a`；优化版含 `NETSCAPE2.0`，30 帧 |

## 高频命令速查

```powershell
# 视频拆序列帧
ffmpeg -i in.mp4 -f image2 seq/%04d.png

# 序列帧合成视频（务必指定 yuv420p）
ffmpeg -framerate 25 -i seq/%04d.png -c:v libx264 -pix_fmt yuv420p out.mp4

# 视频转循环 GIF（两遍调色板法）
ffmpeg -i in.mp4 -vf "fps=15,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" -loop 0 out.gif

# 图片序列（jpg）合成
ffmpeg -framerate 30 -i img_%03d.jpg -c:v libx264 -pix_fmt yuv420p out.mp4
```

## 踩坑清单

- **图片命名不连续**：`%04d` 读取时遇到第一个缺号即停止，后面全部丢弃（本实验删掉 0025.png 后只剩 24 帧）；批量导出前后务必核对序号；
- **未指定 `-pix_fmt yuv420p`**：PNG(RGB) 直接编码默认是 `yuv444p`，部分播放器/浏览器黑屏或无声；合成视频应显式指定；
- **`-r` 与 `-framerate` 混用**：读序列帧应在输入前用 `-framerate`，输出帧率用 `-r`，位置写反会导致丢帧或变速；
- **GIF 调色板**：默认逐帧量化在渐变色/照片上色彩断层明显，两遍调色板法（`palettegen`+`paletteuse`）观感更好；注意 `split` 分流语法；
- **GIF 体积**：GIF 不是万能压缩格式，复杂纹理上体积可能不降反升，可配合 `fps`、`scale`、`max_colors` 控制；
- **奇偶尺寸**：`yuv420p` 要求宽高为偶数，`scale=320:-1` 对奇数源需改用 `scale=320:-2`。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| ffmpeg | N-129130 (BtbN win64-gpl) |
