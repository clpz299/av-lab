# concepts_practice.ps1 —— L1-08 音视频核心概念实验：帧率 / 码率 / 分辨率 / GOP
#
# 思路：用同一段合成素材做「单变量对照」压测，固定其它参数，逐项只改一个维度，
#       记录体积 / 帧率 / 关键帧数，最后汇总成结果表（CSV）。
# 用法：powershell -NoProfile -File scripts\concepts_practice.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-08-concepts'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$script:rows = @()

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function Ff([string[]]$a) {
    $r = Invoke-AvNative $AvTool.Ffmpeg $a
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "ffmpeg 失败 (exit=$($r.Code)): $($a -join ' ')" }
    return $r
}
function Field([string]$file, [string]$entries) {
    $r = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','v:0','-show_entries',$entries,'-of','default=nw=1', $file)
    if ($r.Code -ne 0) { throw "ffprobe 失败: $($r.Output)" }
    return $r.Output
}
function Get-Key([string]$txt, [string]$key) {
    if ($txt -match "(?m)^$key=(\S+)") { return $Matches[1] }
    throw "未能从 ffprobe 输出解析 $key ：$txt"
}
function Size([string]$f) { return (Get-Item $f).Length }
function KeyCount([string]$f) {
    # 只保留关键帧，统计行数
    $r = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','v:0','-skip_frame','nokey',
                                          '-show_entries','frame=key_frame','-of','csv=p=0', $f)
    return (($r.Output -split "`r?`n") | Where-Object { $_.Trim() -eq '1' }).Count
}
function Add-Row([string]$dim, [string]$val, [string]$file, [string]$extra) {
    $info  = Field $file 'stream=width,height,avg_frame_rate,nb_frames,bit_rate'
    $row = [pscustomobject]@{
        Dimension = $dim
        Value     = $val
        SizeBytes = Size $file
        Width     = Get-Key $info 'width'
        Height    = Get-Key $info 'height'
        FPS       = Get-Key $info 'avg_frame_rate'
        Frames    = Get-Key $info 'nb_frames'
        BitRate   = Get-Key $info 'bit_rate'
        Extra     = $extra
    }
    $script:rows += $row
    Write-Host ("    {0,-10} {1,-9} size={2,8}  {3}x{4}  fps={5,-6} frames={6,-4} bitrate={7}" -f `
        $dim, $val, $row.SizeBytes, $row.Width, $row.Height, $row.FPS, $row.Frames, $row.BitRate)
    return $row
}

# ---------- 0) 基准素材：640x480 / 30fps / 3s / GOP=30 ----------
Write-Host "== 0) 生成基准素材 ==" -ForegroundColor Cyan
$src = Join-Path $outDir 'src.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=640x480:rate=30:duration=3',
     '-c:v','libx264','-pix_fmt','yuv420p','-g','30','-an', $src) | Out-Null
$srcInfo = Field $src 'stream=width,height,avg_frame_rate,nb_frames'
Write-Host "    $($srcInfo -replace "`r?`n", ' / ')"
Assert-True ((Get-Key $srcInfo 'nb_frames') -eq '90') "基准素材应为 90 帧（3s x 30fps）"
Add-Row 'base' 'src' $src '' | Out-Null

# ---------- 1) 帧率：同一素材改输出帧率 ----------
Write-Host "== 1) 帧率（-r）==" -ForegroundColor Cyan
$fpsFiles = @()
foreach ($r in 10,15,30) {
    $f = Join-Path $outDir "fr_$r.mp4"
    Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
         '-c:v','libx264','-pix_fmt','yuv420p','-g','30','-r',"$r",'-an',$f) | Out-Null
    Add-Row 'framerate' "-r $r" $f '' | Out-Null
    $fpsFiles += $f
}
Assert-True ((Get-Key (Field $fpsFiles[0] 'stream=avg_frame_rate') 'avg_frame_rate') -eq '10/1') "-r 10 输出帧率应为 10/1"
Assert-True ((Get-Key (Field $fpsFiles[2] 'stream=avg_frame_rate') 'avg_frame_rate') -eq '30/1') "-r 30 输出帧率应为 30/1"
Assert-True ((Size $fpsFiles[0]) -lt (Size $fpsFiles[1]) -and (Size $fpsFiles[1]) -lt (Size $fpsFiles[2])) `
    "帧率越高，帧数越多，体积应递增（$((Size $fpsFiles[0])) / $((Size $fpsFiles[1])) / $((Size $fpsFiles[2]))）"

# ---------- 1b) 踩坑：源帧率与输出帧率不匹配 ----------
Write-Host "== 1b) 踩坑：帧率不匹配（重复帧 / -r 位置）==" -ForegroundColor Cyan
$src10 = Join-Path $outDir 'src10fps.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=320x240:rate=10:duration=2',
     '-c:v','libx264','-pix_fmt','yuv420p','-an', $src10) | Out-Null
Assert-True ((Get-Key (Field $src10 'stream=nb_frames') 'nb_frames') -eq '20') "10fps x 2s 素材应为 20 帧"

$up30 = Join-Path $outDir 'up_r30.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i',$src10,'-c:v','libx264','-pix_fmt','yuv420p','-r','30','-an',$up30) | Out-Null
$up30Frames = Get-Key (Field $up30 'stream=nb_frames') 'nb_frames'
Write-Host "    10fps 源 -r 30 -> $up30Frames 帧（升帧靠复制帧，画质不会变好）"
Assert-True ($up30Frames -eq '60') "10fps 源升到 30fps 应为 60 帧（3 倍重复帧）"

# -r 放在 -i 之前：改变的是「输入帧率的解释」，输出声明 30fps 但帧数仍是 20 -> 时长错乱
$mis = Join-Path $outDir 'misplaced_r.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-r','30','-i',$src10,'-c:v','libx264','-pix_fmt','yuv420p','-an',$mis) | Out-Null
$misFrames = Get-Key (Field $mis 'stream=nb_frames') 'nb_frames'
$misRate   = Get-Key (Field $mis 'stream=avg_frame_rate') 'avg_frame_rate'
Write-Host "    -r 30 放在 -i 之前 -> avg_frame_rate=$misRate 但只有 $misFrames 帧（时间基错乱）"
Assert-True ($misFrames -eq '20') "-r 置于输入前不应复制帧，帧数仍为 20"
Assert-True ($misRate -eq '30/1') "-r 置于输入前会用 30fps 重新解释输入时间基"
Add-Row 'framerate' 'mismatch' $mis 'up30=60frames' | Out-Null

# ---------- 2) 码率：同一素材改目标码率 ----------
Write-Host "== 2) 码率（-b:v）==" -ForegroundColor Cyan
$brFiles = @()
foreach ($b in '200k','800k','2000k') {
    $f = Join-Path $outDir "br_$b.mp4"
    Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
         '-c:v','libx264','-pix_fmt','yuv420p','-b:v',$b,'-an',$f) | Out-Null
    Add-Row 'bitrate' "-b:v $b" $f '' | Out-Null
    $brFiles += $f
}
Assert-True ((Size $brFiles[0]) -lt (Size $brFiles[1]) -and (Size $brFiles[1]) -lt (Size $brFiles[2])) `
    "目标码率越高，体积应递增（$((Size $brFiles[0])) / $((Size $brFiles[1])) / $((Size $brFiles[2]))）"

# ---------- 3) 量化参数：CRF（恒定质量）与码率的区别 ----------
Write-Host "== 3) 量化参数（CRF）==" -ForegroundColor Cyan
$crfFiles = @()
foreach ($c in 18,28,40) {
    $f = Join-Path $outDir "crf_$c.mp4"
    Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
         '-c:v','libx264','-pix_fmt','yuv420p','-crf',"$c",'-an',$f) | Out-Null
    Add-Row 'crf' "-crf $c" $f '' | Out-Null
    $crfFiles += $f
}
Assert-True ((Size $crfFiles[0]) -gt (Size $crfFiles[1]) -and (Size $crfFiles[1]) -gt (Size $crfFiles[2])) `
    "CRF 越大压缩越狠、体积应递减（$((Size $crfFiles[0])) / $((Size $crfFiles[1])) / $((Size $crfFiles[2]))）"

# ---------- 4) 分辨率：同素材缩放到不同尺寸 ----------
Write-Host "== 4) 分辨率（scale）==" -ForegroundColor Cyan
$resFiles = @()
foreach ($s in '320x240','640x480','1280x960') {
    $f = Join-Path $outDir "res_$s.mp4"
    Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
         '-vf',"scale=$s",'-c:v','libx264','-pix_fmt','yuv420p','-an',$f) | Out-Null
    $row = Add-Row 'resolution' $s $f ''
    $wh  = $s -split 'x'
    Assert-True ($row.Width -eq $wh[0] -and $row.Height -eq $wh[1]) "缩放后尺寸应为 $s（实际 $($row.Width)x$($row.Height)）"
    $resFiles += $f
}
Assert-True ((Size $resFiles[0]) -lt (Size $resFiles[1]) -and (Size $resFiles[1]) -lt (Size $resFiles[2])) `
    "分辨率越高、像素越多、体积应递增（$((Size $resFiles[0])) / $((Size $resFiles[1])) / $((Size $resFiles[2]))）"

# ---------- 5) GOP：关键帧间隔影响关键帧数量与体积 ----------
Write-Host "== 5) GOP（-g）==" -ForegroundColor Cyan
$gopFiles = @(); $gopKeys = @()
foreach ($g in 10,30,120) {
    $f = Join-Path $outDir "gop_$g.mp4"
    Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
         '-c:v','libx264','-pix_fmt','yuv420p','-g',"$g",'-an',$f) | Out-Null
    $k = KeyCount $f
    Add-Row 'gop' "-g $g" $f "keyframes=$k" | Out-Null
    $gopFiles += $f; $gopKeys += $k
}
Write-Host "    关键帧数：-g 10 -> $($gopKeys[0])，-g 30 -> $($gopKeys[1])，-g 120 -> $($gopKeys[2])"
Assert-True ($gopKeys[0] -gt $gopKeys[1] -and $gopKeys[1] -gt $gopKeys[2]) `
    "GOP 越小关键帧越密（$($gopKeys[0]) / $($gopKeys[1]) / $($gopKeys[2])）"
Assert-True ($gopKeys[2] -eq 1) "3s/90 帧配 -g 120 应只有 1 个关键帧（仅开头 IDR）"
Assert-True ((Size $gopFiles[0]) -gt (Size $gopFiles[1]) -and (Size $gopFiles[1]) -gt (Size $gopFiles[2])) `
    "GOP 越大 I 帧越少、体积应递减（$((Size $gopFiles[0])) / $((Size $gopFiles[1])) / $((Size $gopFiles[2]))）"

# ---------- 6) 汇总结果表 ----------
Write-Host "== 6) 汇总结果表 ==" -ForegroundColor Cyan
$csv = Join-Path $outDir 'stress_table.csv'
$script:rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "    已写出 $csv（$($script:rows.Count) 行）"
Write-Host ""
Write-Host "    维度       取值        体积(B)  分辨率      帧率     帧数  码率(bps)"
foreach ($r in $script:rows) {
    Write-Host ("    {0,-10} {1,-10} {2,8}  {3,5}x{4,-4}  {5,-8} {6,-5} {7}" -f `
        $r.Dimension, $r.Value, $r.SizeBytes, $r.Width, $r.Height, $r.FPS, $r.Frames, $r.BitRate)
}

Write-Host "concepts_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
