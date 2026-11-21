#!/usr/bin/env bash
# build_ffmpeg.sh —— L1-01 扩展：从零编译 FFmpeg（含外部依赖 x264）
#
# 适用环境：Linux / WSL / MSYS2(MINGW64) / macOS（需 GNU make 或兼容环境）
# 为什么需要 POSIX shell：FFmpeg 的 configure 本身是一段 shell 脚本，
#   原生 Windows cmd/PowerShell 无法直接跑，Windows 上必须先有 MSYS2 或 WSL。
#
# 用法：
#   bash build_ffmpeg.sh [选项]
#     --prefix DIR      安装前缀（默认 $HOME/ffmpeg-build）
#     --jobs N          并行编译任务数（默认 nproc）
#     --ffmpeg-ver VER  版本号（默认 7.1；传 master 走 git 最新）
#     --no-nasm         强制关闭 x86 汇编优化
#   环境变量：PREFIX / JOBS / FFMPEG_VER / WORK 亦可控制
#
# 依赖：gcc g++ make pkg-config git curl tar xz
#       nasm —— 可选，缺失只影响 x86 汇编优化（自动降级 --disable-x86asm）
#
# 产物：$PREFIX/bin/ffmpeg[.exe]、$PREFIX/include、$PREFIX/lib/libav*.a
set -euo pipefail

PREFIX="${PREFIX:-$HOME/ffmpeg-build}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
FFMPEG_VER="${FFMPEG_VER:-7.1}"
WORK="${WORK:-$PWD/_src}"
WITH_NASM="${WITH_NASM:-1}"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)     PREFIX="$2"; shift 2 ;;
    --jobs)       JOBS="$2"; shift 2 ;;
    --ffmpeg-ver) FFMPEG_VER="$2"; shift 2 ;;
    --no-nasm)    WITH_NASM=0; shift ;;
    -h|--help)    sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---------- 0) 前置检查 ----------
for t in gcc make pkg-config git; do
  command -v "$t" >/dev/null 2>&1 || { echo "缺少必需工具: $t" >&2; exit 3; }
done
log "gcc: $(gcc --version | head -n1)"

# nasm 缺失 -> 自动关闭汇编优化（对应踩坑：'nasm/yasm 缺失导致汇编优化未启用'）
NASM_FLAG=""
if [ "$WITH_NASM" = "1" ] && command -v nasm >/dev/null 2>&1; then
  log "nasm: $(nasm -v | head -n1)"
else
  log "nasm 不可用 -> 关闭 x86 汇编优化 (--disable-x86asm)"
  NASM_FLAG="--disable-x86asm"
fi

mkdir -p "$WORK" "$PREFIX"
cd "$WORK"

# ---------- 1) 编译 x264（外部依赖，FFmpeg 不自带 H.264 编码器） ----------
# 说明：AAC 无需外部库——FFmpeg 自带原生 aac 编码器；
#       H.264 则必须外链 x264（否则 configure 报 'libx264 not found'）。
if [ -f "$PREFIX/lib/libx264.a" ] || [ -f "$PREFIX/lib/libx264.so" ] || [ -f "$PREFIX/lib/libx264.dll.a" ]; then
  log "x264 已就绪，跳过"
else
  log "获取 x264 源码..."
  if [ -d x264/.git ]; then
    git -C x264 pull --ff-only || true
  else
    git clone --depth 1 https://code.videolan.org/videolan/x264.git x264
  fi
  log "编译 x264（静态库，关闭 CLI）..."
  (
    cd x264
    ./configure --prefix="$PREFIX" --enable-static --disable-cli --enable-pic $NASM_FLAG
    make -j"$JOBS"
    make install
  )
fi

# ---------- 2) 获取 FFmpeg 源码 ----------
if [ -d ffmpeg/.git ]; then
  log "复用已有 FFmpeg 源码目录"
else
  if [ "$FFMPEG_VER" = "master" ]; then
    log "克隆 FFmpeg master..."
    git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git ffmpeg
  else
    log "下载 FFmpeg $FFMPEG_VER 发行包..."
    curl -fL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz" -o ffmpeg.tar.xz
    tar xf ffmpeg.tar.xz
    mv "ffmpeg-${FFMPEG_VER}" ffmpeg
  fi
fi

# ---------- 3) configure：裁剪选项 + 链接 libx264 ----------
log "配置 FFmpeg（裁剪 + libx264，jobs=$JOBS）..."
cd ffmpeg
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ./configure \
  --prefix="$PREFIX" \
  --enable-gpl \
  --enable-libx264 \
  --enable-static --disable-shared \
  --enable-pic \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$PREFIX/include" \
  --extra-ldflags="-L$PREFIX/lib" \
  --disable-doc \
  --disable-debug \
  --disable-ffplay \
  --disable-autodetect \
  $NASM_FLAG

# ---------- 4) 编译 + 安装 ----------
log "编译 FFmpeg..."
make -j"$JOBS"
make install

# ---------- 5) 验证 ----------
log "验证产物..."
"$PREFIX/bin/ffmpeg" -version | head -n 3
if "$PREFIX/bin/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -qi libx264; then
  log "确认: libx264 编码器已内置"
else
  log "警告: 未在 encoders 列表中找到 libx264"
fi
log "完成。产物前缀: $PREFIX"
