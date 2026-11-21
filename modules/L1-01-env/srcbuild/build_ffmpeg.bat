@echo off
REM build_ffmpeg.bat —— L1-01 扩展：Windows 入口，调用 MSYS2(MINGW64) 执行 build_ffmpeg.sh
REM
REM 为什么不能直接用 cmd 编译：FFmpeg 的 configure 是 shell 脚本，原生 Windows 无 POSIX shell，
REM   必须先装 MSYS2（或改用 WSL）。本脚本负责找到 MSYS2 的 bash 并转交。
REM
REM 用法：build_ffmpeg.bat [--prefix DIR] [--jobs N] [--ffmpeg-ver VER] [--no-nasm]
REM 前置：安装 MSYS2 后在 MINGW64 终端执行
REM   pacman -S --needed base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-nasm git

setlocal
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR_FWD=%SCRIPT_DIR:\=/%"
set "SH=%SCRIPT_DIR_FWD%build_ffmpeg.sh"

REM 1) 定位 MSYS2 的 bash.exe
set "BASH="
if defined MSYS2_ROOT if exist "%MSYS2_ROOT%\usr\bin\bash.exe" set "BASH=%MSYS2_ROOT%\usr\bin\bash.exe"
if not defined BASH if exist "C:\msys64\usr\bin\bash.exe" set "BASH=C:\msys64\usr\bin\bash.exe"

if not defined BASH (
  echo [错误] 未找到 MSYS2（bash.exe）。
  echo        FFmpeg 的 configure 需要 POSIX shell，请先安装 MSYS2: https://www.msys2.org/
  echo        安装后在 "MSYS2 MINGW64" 终端执行：
  echo          pacman -S --needed base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-nasm git
  echo        然后重新运行本脚本（或设置 MSYS2_ROOT 指向 MSYS2 安装目录）。
  exit /b 1
)

echo [信息] 使用 bash: %BASH%
set "MSYSTEM=MINGW64"
"%BASH%" --login -c "cd '%SCRIPT_DIR_FWD%' && bash '%SH%' %*"
if errorlevel 1 (
  echo [失败] FFmpeg 编译未成功，请查看上方日志。
  exit /b 1
)
echo [成功] FFmpeg 编译完成。
endlocal
