# L1-01 音视频开发环境搭建

## 目标

1. 用本工程工具链编译并运行一个 C 程序，证明编译器可用；
2. 自检 `gcc / cmake / ffmpeg` 三件套版本；
3. 完成**第一个可复现的音视频实验**：用 ffmpeg 生成一段带音轨的测试视频，转成 GIF，并用 ffprobe 校验产物；
4. **扩展（源码编译题）**：提供从零编译 FFmpeg 的构建脚本（含 x264 依赖）。

## 扩展：从零编译 FFmpeg（源码编译题）

交付物是**编译脚本 + 环境自检脚本**：

| 文件 | 作用 |
|---|---|
| [build_ffmpeg.sh](file:///d:/workspace/private/audio_video_streaming-main/av-lab/modules/L1-01-env/srcbuild/build_ffmpeg.sh) | Linux / WSL / MSYS2 下的完整构建脚本（先建 x264，再 configure+make FFmpeg） |
| [build_ffmpeg.bat](file:///d:/workspace/private/audio_video_streaming-main/av-lab/modules/L1-01-env/srcbuild/build_ffmpeg.bat) | Windows 入口：定位 MSYS2 的 bash 并转交 `build_ffmpeg.sh` |
| [srcbuild_check.ps1](file:///d:/workspace/private/audio_video_streaming-main/av-lab/modules/L1-01-env/scripts/srcbuild_check.ps1) | 脚本契约校验 + `bash -n` 语法检查 + 本机编译前提探测 |

> ⚠️ FFmpeg 的 `configure` 本身是 shell 脚本，**原生 Windows（cmd/PowerShell）无法直接编译**，必须先装 MSYS2 或改用 WSL。
> 因此本模块的自动化测试只覆盖「**脚本契约 + 语法 + 环境探测**」层（`L1-01.srcbuild_check`），真正的编译见下方手工步骤。

### 手工编译步骤（需 MSYS2 / WSL）

```bash
# 1) Windows 上先装 MSYS2，在 "MSYS2 MINGW64" 终端执行：
pacman -S --needed base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-nasm git

# 2) 运行构建脚本（会先编译 x264，再编译 FFmpeg 到 ~/ffmpeg-build）
bash srcbuild/build_ffmpeg.sh --prefix "$HOME/ffmpeg-build" --jobs 8

# 3) 验证
"$HOME/ffmpeg-build/bin/ffmpeg" -version | head -n 3
"$HOME/ffmpeg-build/bin/ffmpeg" -hide_banner -encoders | grep x264
```

Windows 用户也可直接双击/运行 `srcbuild\build_ffmpeg.bat`（内部自动找 `C:\msys64\usr\bin\bash.exe`）。

关键裁剪/依赖选项（脚本内已固化）：`--enable-gpl --enable-libx264 --enable-static --disable-shared --disable-doc --disable-autodetect`；
AAC 无需外部库（FFmpeg 自带原生 `aac` 编码器），H.264 必须外链 x264。

## 依赖

- 便携工具链位于仓库同级 `.avtoolchain/`（见根目录 README）；
- 无需联网（工具链已就绪时）；
- 源码编译扩展另需：MSYS2（或 WSL）+ `nasm` + `git` + 网络（下载 x264/FFmpeg 源码）。


## 构建与运行

```powershell
# 在 av-lab/ 下执行
pwsh -NoProfile -File tools/build.ps1
```

或单独运行实验脚本：

```powershell
pwsh -NoProfile -File modules/L1-01-env/scripts/first_conversion.ps1
```

## 预期输出

- `hello_env` 打印编译期工具链信息，测试 `L1-01.hello_env` 通过；
- `L1-01.env_check`：打印 gcc/cmake/ffmpeg 版本后 PASS；
- `L1-01.convert`：在 `build/_artifacts/L1-01-env/` 生成 `test.mp4` 与 `test.gif`，并打印 ffprobe 时长/编码信息，最后 PASS；
- `L1-01.srcbuild_check`：校验 `build_ffmpeg.sh/bat` 契约 + `bash -n` 语法检查 + 探测本机编译前提，PASS，并输出 `srcbuild_report.json`。

## 实测环境

| 项 | 值 |
|---|---|
| OS | Windows 10 19044 (x64) |
| gcc/g++ | 16.2.0 (w64devkit 2.11.0) |
| cmake | 4.5.1 |
| ffmpeg | N-129130 (BtbN win64-gpl) |
| 源码编译扩展 | 本机无 MSYS2/nasm，`srcbuild_check` 仅做契约+语法+环境探测（如实报告"缺 MSYS2/nasm"），真正编译需另装 MSYS2/WSL |

