# bootstrap.ps1 —— 一键准备便携工具链（w64devkit + cmake + ffmpeg）
#
# 用途：对应规划文档 §5.7「可复现保障」，让读者/CI 无需手工配置即可获得可用工具链。
# 行为：默认安装到「仓库同级 .avtoolchain」目录（与 tools/avtool.ps1 的查找顺序一致），
#       每个组件已存在即跳过；全部完成后自动校验 gcc/cmake/ffmpeg 版本。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\bootstrap.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\bootstrap.ps1 -Force
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\bootstrap.ps1 -Mirror ''
#
# 参数：
#   -Mirror   GitHub 加速前缀，默认 https://gh-proxy.com/；传空串 '' 表示直连 github.com。
#   -Force    即使组件已存在也重新下载解压。

param(
    [string]$Mirror = $(
        if ($env:AVGH_MIRROR) { $env:AVGH_MIRROR } else { 'https://gh-proxy.com/' }
    ),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# 原生命令（curl/ffmpeg 等）会把日志写到 stderr，PS 5.1 在 Stop 模式下会误判为致命错误；
# 因此单独封装，临时切到 Continue 并用 $LASTEXITCODE 判定。
function Invoke-Native {
    param([string]$Exe, [string[]]$CliArgs, [switch]$Quiet)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($Quiet) {
        & $Exe @CliArgs 2>$null | Out-Null
    } else {
        & $Exe @CliArgs
    }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    return $code
}

function Resolve-ToolchainRoot {
    if ($env:AVTOOLCHAIN) { return $env:AVTOOLCHAIN }
    # av-lab 的仓库根位于 .avtoolchain 同级
    $repoRoot = Split-Path -Parent $PSScriptRoot
    return (Join-Path (Split-Path -Parent $repoRoot) '.avtoolchain')
}

# 版本与下载地址集中在此，升级时只改这里。
# 当前实测版本：w64devkit 2.11.0 (gcc/g++ 16.2.0)、cmake 4.5.1、ffmpeg master (N-*)
$components = @(
    [pscustomobject]@{
        Name  = 'w64devkit'
        Url   = 'https://github.com/skeeto/w64devkit/releases/download/v2.11.0/w64devkit-2.11.0.zip'
        Zip   = 'w64devkit-2.11.0.zip'
        Dest  = 'w64devkit'
        Probe = 'w64devkit\bin\gcc.exe'
    }
    [pscustomobject]@{
        Name  = 'cmake'
        Url   = 'https://github.com/Kitware/CMake/releases/download/v4.5.1/cmake-4.5.1-windows-x86_64.zip'
        Zip   = 'cmake-4.5.1-windows-x86_64.zip'
        Dest  = 'cmake'
        Probe = 'cmake-4.5.1-windows-x86_64\bin\cmake.exe'
    }
    [pscustomobject]@{
        Name  = 'ffmpeg'
        Url   = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
        Zip   = 'ffmpeg-master-latest-win64-gpl.zip'
        Dest  = 'ffmpeg'
        Probe = 'ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe'
    }
)

$tcRoot = Resolve-ToolchainRoot
$pkgDir = Join-Path $tcRoot 'pkgs'
New-Item -ItemType Directory -Force -Path $tcRoot, $pkgDir | Out-Null

Write-Host "== 工具链根目录 ==" -ForegroundColor Cyan
Write-Host "  $tcRoot"
if ($Mirror) { Write-Host "== 加速前缀 ==`n  $Mirror" -ForegroundColor Cyan } else { Write-Host "== 直连 github.com ==" -ForegroundColor Cyan }

foreach ($c in $components) {
    $destDir = Join-Path $tcRoot $c.Dest
    $probeExe = Join-Path $destDir $c.Probe

    if ((Test-Path $probeExe) -and -not $Force) {
        Write-Host "[$($c.Name)] 已存在，跳过" -ForegroundColor DarkGray
        continue
    }

    $zipPath = Join-Path $pkgDir $c.Zip
    $url = $Mirror + $c.Url
    Write-Host "[$($c.Name)] 下载 $($c.Zip)" -ForegroundColor Yellow

    $code = Invoke-Native 'curl.exe' @(
        '-L', '--fail', '-sS', '--connect-timeout', '20', '-o', $zipPath, $url
    ) -Quiet
    if ($code -ne 0 -or -not (Test-Path $zipPath)) {
        throw "[$($c.Name)] 下载失败（exit=$code）：$url`n可改用 -Mirror 指定其它加速前缀，或 -Mirror '' 直连。"
    }

    Write-Host "[$($c.Name)] 解压 -> $destDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $destDir -Force

    if (-not (Test-Path $probeExe)) {
        throw "[$($c.Name)] 解压后未找到预期文件：$probeExe（请检查压缩包结构或 Probe 配置）"
    }
    Write-Host "[$($c.Name)] 完成" -ForegroundColor Green
}

Write-Host "== 校验 ==" -ForegroundColor Cyan
. (Join-Path $PSScriptRoot 'avtool.ps1')

$checks = @(
    @{ Name = 'gcc'; Exe = $AvTool.Gcc; Arg = '--version' }
    @{ Name = 'g++'; Exe = $AvTool.Gpp; Arg = '--version' }
    @{ Name = 'cmake'; Exe = $AvTool.Cmake; Arg = '--version' }
    @{ Name = 'ffmpeg'; Exe = $AvTool.Ffmpeg; Arg = '-version' }
    @{ Name = 'ffprobe'; Exe = $AvTool.Ffprobe; Arg = '-version' }
)

$missing = @()
foreach ($ck in $checks) {
    if (-not $ck.Exe) { $missing += $ck.Name; Write-Host ("  {0,-8}: 缺失" -f $ck.Name) -ForegroundColor Red; continue }
    $line = (& $ck.Exe $ck.Arg 2>&1 | Select-Object -First 1)
    Write-Host ("  {0,-8}: {1}" -f $ck.Name, ($line -as [string]).Trim())
}

if ($missing.Count -gt 0) {
    Write-Host "bootstrap 未完成，缺失：$($missing -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "工具链就绪 ✔  下一步：powershell -NoProfile -File tools\build.ps1" -ForegroundColor Green
exit 0
