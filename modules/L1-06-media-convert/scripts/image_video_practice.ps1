# image_video_practice.ps1 —— L1-06 图片与视频互转、视频转 GIF 端到端实验
#
# 链路：ffmpeg 自产 MP4 -> 拆成 PNG 序列 -> 序列合成 MP4 -> 转循环 GIF
# 用法：powershell -NoProfile -File scripts\image_video_practice.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-06-media-convert'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$seqDir = Join-Path $outDir 'seq'
$gapDir = Join-Path $outDir 'seqgap'
Remove-Item $seqDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $gapDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $seqDir | Out-Null

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function Ff([string[]]$a) {
    $r = Invoke-AvNative $AvTool.Ffmpeg $a
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "ffmpeg 失败 (exit=$($r.Code)): $($a -join ' ')" }
    return $r
}
function Probe([string]$f) {
    $r = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','v:0','-show_entries','stream=pix_fmt,nb_frames','-of','default=nw=1', $f)
    if ($r.Code -ne 0) { throw "ffprobe 失败: $($r.Output)" }
    return $r.Output
}
function Get-Field([string]$txt, [string]$key) {
    if ($txt -match "$key=(\S+)") { return $Matches[1] }
    throw "未能从 ffprobe 输出解析 $key ：$txt"
}

# ---------- 0) ffmpeg 自产 MP4 素材 ----------
Write-Host "== 0) 生成 MP4 素材 ==" -ForegroundColor Cyan
$src = Join-Path $outDir 'src.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=2',
     '-c:v','libx264','-pix_fmt','yuv420p','-an', $src) | Out-Null
Assert-True (Test-Path $src) "MP4 未生成"

# ---------- 1) 视频 -> 图片序列 ----------
Write-Host "== 1) 视频拆成 PNG 序列 ==" -ForegroundColor Cyan
Ff @('-hide_banner','-loglevel','error','-y','-i', $src,
     '-f','image2', (Join-Path $seqDir '%04d.png')) | Out-Null
$pngs = Get-ChildItem (Join-Path $seqDir '*.png') | Sort-Object Name
Write-Host "    生成 $($pngs.Count) 张 PNG，首帧 $($pngs[0].Name) 末帧 $($pngs[-1].Name)"
Assert-True ($pngs.Count -eq 50) "图片序列应为 50 帧（实际 $($pngs.Count)）"
Assert-True ($pngs[0].Name -eq '0001.png') "首帧应从 0001 开始（实际 $($pngs[0].Name)）"
Assert-True ($pngs[-1].Name -eq '0050.png') "末帧应为 0050（实际 $($pngs[-1].Name)）"

# ---------- 2) 图片序列 -> 视频（显式 yuv420p）----------
Write-Host "== 2) 序列合成 MP4（-pix_fmt yuv420p）==" -ForegroundColor Cyan
$rebuilt = Join-Path $outDir 'rebuilt_420.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-framerate','25',
     '-i', (Join-Path $seqDir '%04d.png'),
     '-c:v','libx264','-pix_fmt','yuv420p', $rebuilt) | Out-Null
$info = Probe $rebuilt
Write-Host "    $($info -replace "`r?`n", " / ")"
Assert-True ((Get-Field $info 'nb_frames') -eq '50') "合成视频应还原 50 帧"
Assert-True ((Get-Field $info 'pix_fmt') -eq 'yuv420p') "显式指定后像素格式应为 yuv420p"

# ---------- 3) 踩坑：不指定 -pix_fmt 得到 yuv444p ----------
Write-Host "== 3) 踩坑：省略 -pix_fmt 得到 yuv444p ==" -ForegroundColor Cyan
$default = Join-Path $outDir 'rebuilt_default.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-framerate','25',
     '-i', (Join-Path $seqDir '%04d.png'), '-c:v','libx264', $default) | Out-Null
$fmtDefault = Get-Field (Probe $default) 'pix_fmt'
Write-Host "    默认 pix_fmt = $fmtDefault"
Assert-True ($fmtDefault -ne 'yuv420p') "PNG(rgb) 直接编码默认应为 yuv444p（实际 $fmtDefault）"

# ---------- 4) 踩坑：图片序号不连续导致截断 ----------
Write-Host "== 4) 踩坑：缺帧导致序列截断 ==" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $gapDir | Out-Null
Copy-Item (Join-Path $seqDir '*.png') $gapDir -Force
Remove-Item (Join-Path $gapDir '0025.png') -Force
$gapMp4 = Join-Path $outDir 'gap.mp4'
# 缺帧时 ffmpeg 会在第一个空洞处停止，退出码非 0，故此处不强制成功
$null = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-framerate','25',
        '-i', (Join-Path $gapDir '%04d.png'), '-c:v','libx264','-pix_fmt','yuv420p', $gapMp4)
$gapFrames = Get-Field (Probe $gapMp4) 'nb_frames'
Write-Host "    缺 0025.png 后合成帧数 = $gapFrames"
Assert-True ($gapFrames -eq '24') "缺帧后应在第一个空洞处停止（应为 24，实际 $gapFrames）"

# ---------- 5) 视频 -> 循环 GIF（默认 vs 调色板两遍法）----------
Write-Host "== 5) MP4 转循环 GIF（调色板优化）==" -ForegroundColor Cyan
$gifNaive = Join-Path $outDir 'out_naive.gif'
$gifOpt   = Join-Path $outDir 'out_opt.gif'
Ff @('-hide_banner','-loglevel','error','-y','-i', $src,
     '-vf','fps=15,scale=320:-1:flags=lanczos', $gifNaive) | Out-Null
Ff @('-hide_banner','-loglevel','error','-y','-i', $src,
     '-vf','fps=15,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse',
     '-loop','0', $gifOpt) | Out-Null

$nb = [System.IO.File]::ReadAllBytes($gifNaive)
$ob = [System.IO.File]::ReadAllBytes($gifOpt)
$magicN = [System.Text.Encoding]::ASCII.GetString($nb[0..5])
$magicO = [System.Text.Encoding]::ASCII.GetString($ob[0..5])
$loopFlag = [System.Text.Encoding]::ASCII.GetString($ob).Contains('NETSCAPE2.0')
$gifFrames = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-count_frames','-select_streams','v:0','-show_entries','stream=nb_read_frames','-of','default=nw=1', $gifOpt)
$gf = Get-Field $gifFrames.Output 'nb_read_frames'
Write-Host "    默认 GIF $($nb.Length) B / 调色板 GIF $($ob.Length) B，帧数 $gf"
Assert-True ($magicN -eq 'GIF89a') "默认 GIF 应为 GIF89a（实际 $magicN）"
Assert-True ($magicO -eq 'GIF89a') "调色板 GIF 应为 GIF89a（实际 $magicO）"
Assert-True $loopFlag "调色板 GIF 应含 NETSCAPE2.0（启用循环）"
Assert-True ($gf -eq '30') "GIF 帧数应为 30（2s x 15fps，实际 $gf）"

Write-Host "image_video_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
