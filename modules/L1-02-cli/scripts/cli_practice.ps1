# cli_practice.ps1 —— L1-02 ffmpeg / ffprobe 命令行实战实验
#
# 实验链路（探测信息 -> 提取音视频 -> 播放验证）：
#   1) 用 lavfi 生成一段带音轨的测试源 src.mp4
#   2) ffprobe 探测流信息（streams + format）
#   3) ffmpeg 分离提取纯视频 / 纯音频（-c copy 不重编码）
#   4) ffmpeg 加一条简单视频过滤器（scale）生成缩略版
#   5) ffprobe 复核产物，确认分离正确
# 说明：ffplay 需要图形界面，本脚本不自动播放；请手工运行 README 中的 ffplay 命令验证。

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-02-cli'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$src       = Join-Path $outDir 'src.mp4'
$videoOnly = Join-Path $outDir 'video_only.mp4'
$audioOnly = Join-Path $outDir 'audio_only.m4a'
$scaled    = Join-Path $outDir 'scaled.mp4'
Remove-Item $src, $videoOnly, $audioOnly, $scaled -ErrorAction SilentlyContinue

function Invoke-Cmd {
    param([string]$Exe, [string[]]$CliArgs)
    Write-Host ("  $ " + (Split-Path -Leaf $Exe) + " " + ($CliArgs -join ' ')) -ForegroundColor DarkGray
    Invoke-AvNative $Exe $CliArgs
}

# 1) 生成测试源（320x240@15 + 440Hz 正弦音轨，5s）
Write-Host "== 1) 生成测试源 src.mp4 ==" -ForegroundColor Cyan
$r = Invoke-Cmd $AvTool.Ffmpeg @(
    '-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=15',
    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
    '-t', '5', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', $src)
if ($r.Code -ne 0) { Write-Host $r.Output; throw "生成测试源失败 (exit=$($r.Code))" }

# 2) ffprobe 探测流信息（教学重点：-show_entries / -of 输出格式）
Write-Host "== 2) ffprobe 探测流信息 ==" -ForegroundColor Cyan
$r = Invoke-Cmd $AvTool.Ffprobe @(
    '-v', 'error', '-show_entries', 'stream=index,codec_type,codec_name,width,height,sample_rate,channels',
    '-of', 'csv=p=0', $src)
if ($r.Code -ne 0) { Write-Host $r.Output; throw "ffprobe 探测失败 (exit=$($r.Code))" }
Write-Host "  # 字段顺序由 ffprobe 固定（index,codec_name,codec_type,...），且不适用的字段会被省略"
($r.Output -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" }

# 3) 分离提取：-map 选流 + -c copy 免重编码
Write-Host "== 3) 分离提取纯视频 / 纯音频 (-c copy) ==" -ForegroundColor Cyan
$r = Invoke-Cmd $AvTool.Ffmpeg @(
    '-hide_banner', '-loglevel', 'error', '-y', '-i', $src, '-map', '0:v:0', '-c', 'copy', '-an', $videoOnly)
if ($r.Code -ne 0) { Write-Host $r.Output; throw "提取纯视频失败 (exit=$($r.Code))" }

$r = Invoke-Cmd $AvTool.Ffmpeg @(
    '-hide_banner', '-loglevel', 'error', '-y', '-i', $src, '-map', '0:a:0', '-c', 'copy', '-vn', $audioOnly)
if ($r.Code -ne 0) { Write-Host $r.Output; throw "提取纯音频失败 (exit=$($r.Code))" }

# 4) 简单过滤器：缩放到 160x120 并去掉音轨
Write-Host "== 4) 过滤器 scale=160:120 (-vf) ==" -ForegroundColor Cyan
$r = Invoke-Cmd $AvTool.Ffmpeg @(
    '-hide_banner', '-loglevel', 'error', '-y', '-i', $src,
    '-vf', 'scale=160:120', '-an', $scaled)
if ($r.Code -ne 0) { Write-Host $r.Output; throw "缩放失败 (exit=$($r.Code))" }

# 5) 复核产物：大小 + 流类型
Write-Host "== 5) 复核产物 ==" -ForegroundColor Cyan
foreach ($f in @($videoOnly, $audioOnly, $scaled)) {
    if (-not (Test-Path $f)) { throw "产物缺失: $f" }
    $size = (Get-Item $f).Length
    if ($size -lt 1KB) { throw "产物过小，疑似失败: $f ($size 字节)" }
}

$vTypes = (Invoke-AvNative $AvTool.Ffprobe @(
    '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', $videoOnly)).Output
$aTypes = (Invoke-AvNative $AvTool.Ffprobe @(
    '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', $audioOnly)).Output

$vTypes = ($vTypes -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ','
$aTypes = ($aTypes -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ','

Write-Host ("  video_only.mp4 流: {0}" -f $vTypes)
Write-Host ("  audio_only.m4a 流: {0}" -f $aTypes)

if ($vTypes -notmatch 'video' -or $vTypes -match 'audio') { throw "分离结果错误：video_only 应仅含视频流（实际: $vTypes）" }
if ($aTypes -notmatch 'audio' -or $aTypes -match 'video') { throw "分离结果错误：audio_only 应仅含音频流（实际: $aTypes）" }

$scaledW = (Invoke-AvNative $AvTool.Ffprobe @(
    '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', $scaled)).Output
Write-Host ("  scaled.mp4 分辨率: {0}" -f ($scaledW -replace "`r?`n", ' '))
if ($scaledW -notmatch '160' -or $scaledW -notmatch '120') { throw "缩放结果错误：期望 160x120（实际: $scaledW）" }

Write-Host "cli_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
