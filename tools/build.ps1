# build.ps1 —— 一键配置、构建并运行全量测试
# 用法： pwsh -NoProfile -File tools\build.ps1 [-Target <name>]

param(
    [string]$Target = ""
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'avtool.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $repoRoot 'build'

Write-Host "== 工具链 ==" -ForegroundColor Cyan
Write-Host "gcc   : $($AvTool.Gcc)"
Write-Host "cmake : $($AvTool.Cmake)"
Write-Host "ffmpeg: $($AvTool.Ffmpeg)"

Write-Host "== 配置 ==" -ForegroundColor Cyan
& $AvTool.Cmake -S $repoRoot -B $buildDir -G "Unix Makefiles" `
    -DCMAKE_C_COMPILER="$($AvTool.Gcc)" `
    -DCMAKE_CXX_COMPILER="$($AvTool.Gpp)" `
    -DCMAKE_MAKE_PROGRAM="$($AvTool.Make)"
if ($LASTEXITCODE -ne 0) { throw "cmake 配置失败" }

Write-Host "== 构建 ==" -ForegroundColor Cyan
& $AvTool.Cmake --build $buildDir
if ($LASTEXITCODE -ne 0) { throw "构建失败" }

Write-Host "== 测试 ==" -ForegroundColor Cyan
& $AvTool.Ctest --test-dir $buildDir --output-on-failure
if ($LASTEXITCODE -ne 0) { throw "测试失败" }

Write-Host "全部通过 ✔" -ForegroundColor Green
