# stream_practice.ps1 —— L1-05 视频码流分析工具入门端到端实验
#
# 链路：ffmpeg 自产 MP4 -> 导出 Annex-B 裸流(-bsf:v h264_mp4toannexb) -> h264_nalu 列 NALU -> 识别 I 帧
# 用法：powershell -NoProfile -File scripts\stream_practice.ps1 <h264_nalu.exe 路径>

param([string]$H264Nalu)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-05-stream-tools'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $H264Nalu) {
    $cand = Get-ChildItem -Path (Join-Path $repoRoot 'build') -Recurse -Filter 'h264_nalu.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cand) { throw "未找到 h264_nalu.exe，请先构建或显式传入路径" }
    $H264Nalu = $cand.FullName
}
if (-not (Test-Path $H264Nalu)) { throw "h264_nalu 不存在: $H264Nalu" }

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function Run-Tool([string[]]$ToolArgs) {
    Write-Host ("  $ h264_nalu " + ($ToolArgs -join ' ')) -ForegroundColor DarkGray
    $r = Invoke-AvNative $H264Nalu $ToolArgs
    if ($r.Output) { Write-Host "    $($r.Output -replace "`r?`n", "`n    ")" }
    return $r
}

# ---------- 0) ffmpeg 自产 MP4 素材 ----------
Write-Host "== 0) 生成 H.264 MP4 素材 ==" -ForegroundColor Cyan
$mp4 = Join-Path $outDir 'src.mp4'
# testsrc2 彩条测试图：320x240 / 25fps / 2s = 50 帧；-g 25 每 25 帧一个关键帧(帧 0、25)
$r = Invoke-AvNative $AvTool.Ffmpeg @(
    '-hide_banner','-loglevel','error','-y',
    '-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=2',
    '-c:v','libx264','-pix_fmt','yuv420p',
    '-g','25','-keyint_min','25','-sc_threshold','0','-an',
    $mp4)
if ($r.Code -ne 0) { throw "生成 MP4 失败: $($r.Output)" }
Assert-True (Test-Path $mp4) "MP4 未生成"
Write-Host ("    MP4 大小: " + (Get-Item $mp4).Length + " B")

# ---------- 1) 导出 Annex-B 裸流 ----------
Write-Host "== 1) 导出 Annex-B 裸流（-bsf:v h264_mp4toannexb）==" -ForegroundColor Cyan
$annexb = Join-Path $outDir 'src_annexb.h264'
$r = Invoke-AvNative $AvTool.Ffmpeg @(
    '-hide_banner','-loglevel','error','-y',
    '-i', $mp4,
    '-c:v','copy','-bsf:v','h264_mp4toannexb','-f','h264',
    $annexb)
if ($r.Code -ne 0) { throw "导出裸流失败: $($r.Output)" }
$ab = [System.IO.File]::ReadAllBytes($annexb)
Assert-True ($ab.Length -gt 0) "裸流为空"
$head4 = ($ab[0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
Write-Host "    首 4 字节: $head4"
Assert-True ($ab[0] -eq 0 -and $ab[1] -eq 0 -and $ab[2] -eq 0 -and $ab[3] -eq 1) "Annex-B 裸流应以 00 00 00 01 起始"

# ---------- 2) MP4 用 AVCC 存储（踩坑佐证）----------
Write-Host "== 2) 佐证：MP4 内部为 AVCC（长度前缀），非 Annex-B ==" -ForegroundColor Cyan
$probe = Invoke-AvNative $AvTool.Ffprobe @(
    '-v','error','-select_streams','v:0',
    '-show_entries','stream=codec_name,is_avc',
    '-of','default=nw=1', $mp4)
Assert-True ($probe.Code -eq 0) "ffprobe 解析 MP4 失败: $($probe.Output)"
Write-Host "    $($probe.Output -replace "`r?`n", " / ")"
Assert-True ($probe.Output -match 'codec_name=.*h264') "MP4 视频流应为 h264"
Assert-True ($probe.Output -match 'is_avc=(1|true)') "MP4 内 H.264 应为 AVCC 存储（is_avc=1/true）"

# ---------- 3) 用 h264_nalu 列 NALU 并识别 I 帧 ----------
Write-Host "== 3) 解析裸流：列出 NALU 并识别 I 帧 ==" -ForegroundColor Cyan
$res = Run-Tool @($annexb)
Assert-True ($res.Code -eq 0) "h264_nalu 解析失败 (exit=$($res.Code))"
$txt = $res.Output
Assert-True ($txt -match 'SPS')  "应包含 SPS NALU"
Assert-True ($txt -match 'PPS')  "应包含 PPS NALU"
Assert-True ($txt -match 'IDR')  "应包含 IDR（I 帧）NALU"

if ($txt -match 'Total NALUs:\s*(\d+)') { $total = [int]$Matches[1] } else { throw "未能解析 NALU 总数" }
if ($txt -match 'I/IDR frames:\s*(\d+)') { $idrCnt = [int]$Matches[1] } else { throw "未能解析 I 帧数量" }
Write-Host "    NALU 总数=$total, I 帧数=$idrCnt"
Assert-True ($total -gt 5) "NALU 总数应大于 5（实际 $total）"
Assert-True ($idrCnt -ge 2) "I 帧数应 >= 2（-g 25 + 50 帧，实际 $idrCnt）"

# ---------- 4) 对比：不显式加 -bsf 导出（容器自动补 bsf）----------
Write-Host "== 4) 对比：不显式加 -bsf 导出（容器自动补）==" -ForegroundColor Cyan
$auto = Join-Path $outDir 'src_auto.h264'
$r = Invoke-AvNative $AvTool.Ffmpeg @(
    '-hide_banner','-loglevel','error','-y',
    '-i', $mp4, '-c:v','copy','-f','h264', $auto)
Assert-True ($r.Code -eq 0) "不带 bsf 导出失败: $($r.Output)"
$autoNalu = Run-Tool @($auto)
Assert-True ($autoNalu.Code -eq 0) "h264_nalu 解析（自动 bsf）失败"
if ($autoNalu.Output -match 'I/IDR frames:\s*(\d+)') { $autoIdr = [int]$Matches[1] } else { throw "未能解析自动导出 I 帧数" }
Assert-True ($autoIdr -eq $idrCnt) "两种导出方式 I 帧数应一致（$autoIdr vs $idrCnt）"

# ---------- 5) 踩坑：把非 Annex-B（AVCC 长度前缀）数据喂给分析器 ----------
Write-Host "== 5) 踩坑：分析器对非 Annex-B 输入报错 ==" -ForegroundColor Cyan
$avcc = Join-Path $outDir 'fake_avcc.bin'
$bytes = New-Object System.Collections.Generic.List[byte]
foreach ($n in 5, 7, 9) {
    # 4 字节大端长度前缀（AVCC 风格），后接 n 字节伪 payload；全文件无 00 00 01
    $bytes.Add(0); $bytes.Add(0); $bytes.Add(0); $bytes.Add([byte]$n)
    1..$n | ForEach-Object { $bytes.Add([byte](0x40 + $_)) }
}
[System.IO.File]::WriteAllBytes($avcc, $bytes.ToArray())
$r = Run-Tool @($avcc)
Assert-True ($r.Code -eq 2) "非 Annex-B 输入应返回退出码 2，实际 $($r.Code)"
Assert-True ($r.Output -match 'Annex-B') "错误信息应提示 Annex-B 起始码缺失"

Write-Host "stream_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
