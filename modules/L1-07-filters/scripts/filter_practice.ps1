# filter_practice.ps1 —— L1-07 FFmpeg 滤镜入门端到端实验
#
# 链路：ffmpeg 自产 MP4 -> drawtext 文字水印 / overlay 图片水印 / crop / pad / 多宫格 / 踩坑
# 用法：powershell -NoProfile -File scripts\filter_practice.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-07-filters'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function Ff([string[]]$a, [switch]$AllowFail) {
    $r = Invoke-AvNative $AvTool.Ffmpeg $a
    if (-not $AllowFail -and $r.Code -ne 0) { Write-Host $r.Output; throw "ffmpeg 失败 (exit=$($r.Code)): $($a -join ' ')" }
    return $r
}
function Get-Dims([string]$f) {
    $r = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','csv=p=0', $f)
    if ($r.Code -ne 0) { throw "ffprobe 失败: $($r.Output)" }
    return $r.Output.Trim()
}
function Get-DimsFrames([string]$f) {
    $r = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','v:0','-show_entries','stream=width,height,nb_frames','-of','csv=p=0', $f)
    if ($r.Code -ne 0) { throw "ffprobe 失败: $($r.Output)" }
    return $r.Output.Trim()
}
function Grab-Png([string]$f, [string]$png) {
    Ff @('-hide_banner','-loglevel','error','-y','-i', $f, '-frames:v','1', $png) | Out-Null
    return [System.IO.File]::ReadAllBytes($png)
}
# 找到可用字体（Windows 必带）；ffmpeg drawtext 需要显式 fontfile
function Resolve-Font {
    foreach ($c in 'simhei.ttf','msyh.ttc','segoeui.ttf','arial.ttf','consola.ttf') {
        $p = Join-Path $env:WINDIR "Fonts\$c"
        if (Test-Path $p) { return $p }
    }
    throw "未找到可用字体文件，drawtext 无法测试"
}
# 滤镜图里 Windows 盘符的冒号必须转义为 \:，且整体用单引号包住
function Escape-FontPath([string]$p) {
    return ($p -replace ':','\:')
}

# ---------- 0) 素材 ----------
Write-Host "== 0) 生成素材 ==" -ForegroundColor Cyan
$src = Join-Path $outDir 'src.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=1',
     '-c:v','libx264','-pix_fmt','yuv420p','-an', $src) | Out-Null
$logo = Join-Path $outDir 'logo.png'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','color=c=red@0.6:s=64x32:d=1','-frames:v','1', $logo) | Out-Null
$font = Resolve-Font
$fontEsc = Escape-FontPath $font
Write-Host "    字体: $font"
$srcFrame = Grab-Png $src (Join-Path $outDir 'src_f0.png')

# ---------- 1) 文字水印 drawtext ----------
Write-Host "== 1) 文字水印（drawtext）==" -ForegroundColor Cyan
$txt = Join-Path $outDir 'watermark_text.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i', $src,
     '-vf', "drawtext=fontfile='$fontEsc':fontcolor=white:fontsize=20:text='av-lab':x=10:y=10:box=1:boxcolor=black@0.4",
     '-c:v','libx264','-pix_fmt','yuv420p', $txt) | Out-Null
Assert-True ((Get-Dims $txt) -eq '320,240') "文字水印输出尺寸应保持 320x240"
$txtFrame = Grab-Png $txt (Join-Path $outDir 'txt_f0.png')
Assert-True (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$srcFrame, [byte[]]$txtFrame)) "文字水印应改变画面像素"

# ---------- 2) 图片水印 overlay ----------
Write-Host "== 2) 图片水印（overlay 右下角）==" -ForegroundColor Cyan
$ov = Join-Path $outDir 'watermark_logo.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i', $src, '-i', $logo,
     '-filter_complex','[0:v][1:v]overlay=W-w-10:H-h-10','-c:v','libx264','-pix_fmt','yuv420p', $ov) | Out-Null
Assert-True ((Get-Dims $ov) -eq '320,240') "图片水印输出尺寸应保持 320x240"
$ovFrame = Grab-Png $ov (Join-Path $outDir 'ov_f0.png')
Assert-True (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$srcFrame, [byte[]]$ovFrame)) "图片水印应改变画面像素"

# ---------- 3) crop 裁剪 / pad 补边 ----------
Write-Host "== 3) crop 裁剪 / pad 补边 ==" -ForegroundColor Cyan
$crop = Join-Path $outDir 'crop.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i', $src, '-vf','crop=160:120:80:60',
     '-c:v','libx264','-pix_fmt','yuv420p', $crop) | Out-Null
Write-Host "    crop 输出: $(Get-Dims $crop)"
Assert-True ((Get-Dims $crop) -eq '160,120') "crop 应得到 160x120"
$pad = Join-Path $outDir 'pad.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i', $src, '-vf','pad=400:300:(ow-iw)/2:(oh-ih)/2:green',
     '-c:v','libx264','-pix_fmt','yuv420p', $pad) | Out-Null
Write-Host "    pad  输出: $(Get-Dims $pad)"
Assert-True ((Get-Dims $pad) -eq '400,300') "pad 应得到 400x300"

# ---------- 4) 滤镜链顺序影响结果 ----------
Write-Host "== 4) 滤镜链顺序影响结果 ==" -ForegroundColor Cyan
$a = Join-Path $outDir 'order_a.mp4'; $b = Join-Path $outDir 'order_b.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i', $src, '-vf','scale=160:120,pad=320:240:0:0:green',
     '-c:v','libx264','-pix_fmt','yuv420p', $a) | Out-Null
Ff @('-hide_banner','-loglevel','error','-y','-i', $src, '-vf','pad=320:240:0:0:green,scale=160:120',
     '-c:v','libx264','-pix_fmt','yuv420p', $b) | Out-Null
Write-Host "    scale,pad -> $(Get-Dims $a) ; pad,scale -> $(Get-Dims $b)"
Assert-True ((Get-Dims $a) -eq '320,240') "scale=160:120,pad=320:240 应输出 320x240"
Assert-True ((Get-Dims $b) -eq '160,120') "pad=320:240,scale=160:120 应输出 160x120"

# ---------- 5) 踩坑：scale 的 -1 导致奇数高度 ----------
Write-Host "== 5) 踩坑：scale=300:-1 奇数高度编码失败 ==" -ForegroundColor Cyan
$odd1 = Ff @('-hide_banner','-loglevel','error','-y','-i', $src, '-vf','scale=300:-1',
             '-c:v','libx264','-pix_fmt','yuv420p', (Join-Path $outDir 'odd1.mp4')) -AllowFail
Assert-True ($odd1.Code -ne 0) "scale=300:-1 应因高度不可被 2 整除而失败"
Write-Host "    失败信息: $(($odd1.Output -split "`r?`n" | Select-String 'divisible|Error' | Select-Object -First 1))"
$odd2 = Join-Path $outDir 'odd2.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i', $src, '-vf','scale=300:-2',
     '-c:v','libx264','-pix_fmt','yuv420p', $odd2) | Out-Null
$d2 = Get-Dims $odd2; $h2 = [int]($d2.Split(',')[1])
Write-Host "    scale=300:-2 -> $d2"
Assert-True ($d2.Split(',')[0] -eq '300') "scale=300:-2 宽度应为 300"
Assert-True ($h2 % 2 -eq 0) "scale=300:-2 高度应为偶数（实际 $h2）"

# ---------- 6) 踩坑：字体文件不存在 ----------
Write-Host "== 6) 踩坑：fontfile 指向不存在的字体 ==" -ForegroundColor Cyan
$bad = Ff @('-hide_banner','-loglevel','error','-y','-i', $src,
            '-vf', "drawtext=fontfile='C\:/Windows/Fonts/__nope__.ttf':text=x",
            '-frames:v','1', (Join-Path $outDir 'badfont.png')) -AllowFail
Assert-True ($bad.Code -ne 0) "fontfile 不存在时应初始化滤镜失败"

# ---------- 7) 2x2 多宫格 ----------
Write-Host "== 7) 2x2 多宫格（hstack + vstack）==" -ForegroundColor Cyan
$grid = Join-Path $outDir 'grid2x2.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-i', $src, '-i', $src, '-i', $src, '-i', $src,
     '-filter_complex','[0:v]scale=160:120[a];[1:v]scale=160:120[b];[2:v]scale=160:120[c];[3:v]scale=160:120[d];[a][b]hstack[top];[c][d]hstack[bot];[top][bot]vstack[out]',
     '-map','[out]','-c:v','libx264','-pix_fmt','yuv420p', $grid) | Out-Null
$gInfo = Get-DimsFrames $grid
Write-Host "    多宫格输出: $gInfo"
Assert-True ($gInfo -match '^320,240,25$') "2x2 多宫格应为 320x240 且 25 帧（实际 $gInfo）"

Write-Host "filter_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
