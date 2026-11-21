# first_conversion.ps1 —— L1-01 首个转换实验
# 流程： ffmpeg 生成测试 MP4(含音轨) -> 转 GIF -> ffprobe 校验产物
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-01-env'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$mp4 = Join-Path $outDir 'test.mp4'
$gif = Join-Path $outDir 'test.gif'
Remove-Item $mp4, $gif -ErrorAction SilentlyContinue

Write-Host "== 1) 生成测试 MP4 (testsrc2 + 正弦音轨, 3s) ==" -ForegroundColor Cyan
$r1 = Invoke-AvNative $AvTool.Ffmpeg @(
    '-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=15',
    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
    '-t', '3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', $mp4)
if ($r1.Code -ne 0) { Write-Host $r1.Output; throw "生成 MP4 失败 (exit=$($r1.Code))" }

Write-Host "== 2) MP4 -> GIF (调色板法) ==" -ForegroundColor Cyan
$r2 = Invoke-AvNative $AvTool.Ffmpeg @(
    '-hide_banner', '-loglevel', 'error', '-y', '-i', $mp4,
    '-vf', 'fps=10,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',
    $gif)
if ($r2.Code -ne 0) { Write-Host $r2.Output; throw "转 GIF 失败 (exit=$($r2.Code))" }

Write-Host "== 3) ffprobe 校验产物 ==" -ForegroundColor Cyan
foreach ($f in @($mp4, $gif)) {
    if (-not (Test-Path $f)) { throw "产物缺失: $f" }
    $size = (Get-Item $f).Length
    if ($size -lt 10KB) { throw "产物过小，疑似失败: $f ($size 字节)" }
    Write-Host ("  {0}  ({1:N1} KB)" -f (Split-Path -Leaf $f), ($size / 1KB))
    $probe = Invoke-AvNative $AvTool.Ffprobe @(
        '-v', 'error', '-show_entries', 'format=format_name,duration,size', '-of', 'default=nw=1', $f)
    ($probe.Output -split "`n") | ForEach-Object { Write-Host "    $_" }
}

Write-Host "first_conversion PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
