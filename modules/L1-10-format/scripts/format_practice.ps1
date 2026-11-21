# format_practice.ps1 —— L1-10 常见音视频格式识别与转换
#
# 链路：同一份 H.264+AAC 源 -> 转封装成 mp4/flv/mkv/avi/ts/mov 六种容器 -> 生成转换矩阵表；
# 并演示三个坑：编码 vs 封装混淆、转封装失败（容器不支持该编码）、MKV 多音轨选择。
# 用法：powershell -NoProfile -File scripts\format_practice.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-10-format'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$script:matrix = @()

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function Ff([string[]]$a) {
    $r = Invoke-AvNative $AvTool.Ffmpeg $a
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "ffmpeg 失败 (exit=$($r.Code)): $($a -join ' ')" }
    return $r
}
function FfTry([string[]]$a) { return (Invoke-AvNative $AvTool.Ffmpeg $a) }
function FormatName([string]$file) {
    # nw=1:nk=1 -> 去掉 [FORMAT] 包装与 "format_name=" 键名，直接得到值
    return (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','format=format_name','-of','default=nw=1:nk=1', $file)).Output.Trim()
}
function Codecs([string]$file, [string]$sel) {
    # 取某类流（v/a）的 codec_name 列表
    $r = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams',$sel,'-show_entries','stream=codec_name','-of','csv=p=0', $file)).Output
    return (($r -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
}
function Streams([string]$file) {
    # 返回形如 "video:h264 audio:aac" 的编码清单（分开探测，避免依赖 ffprobe CSV 字段顺序）
    $list = @()
    foreach ($c in (Codecs $file 'v')) { $list += "video:$c" }
    foreach ($c in (Codecs $file 'a')) { $list += "audio:$c" }
    return ($list -join ' ')
}
function Describe([string]$tag, [string]$file) {
    $fmt = FormatName $file
    $st  = Streams $file
    Write-Host ("    {0,-22} 封装={1,-28} 编码=[{2}]" -f $tag, $fmt, $st)
    return [pscustomobject]@{ Tag = $tag; Container = $fmt; Codecs = $st }
}

# ---------- 0) 素材：H.264 + AAC 的 MP4 ----------
Write-Host "== 0) 生成素材（H.264 + AAC / MP4）==" -ForegroundColor Cyan
$src = Join-Path $outDir 'src.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=2',
     '-f','lavfi','-i','sine=frequency=440:sample_rate=44100:duration=2',
     '-c:v','libx264','-pix_fmt','yuv420p','-g','25','-c:a','aac','-b:a','96k','-shortest', $src) | Out-Null
$srcD = Describe 'src.mp4' $src
Assert-True ($srcD.Container -like '*mp4*') "源应是 MP4 封装"
Assert-True ($srcD.Codecs -match 'video:h264' -and $srcD.Codecs -match 'audio:aac') "源应是 H.264 视频 + AAC 音频"

# ---------- 1) 格式识别：封装 ≠ 编码（同一个 .mp4 也能装别的编码）----------
Write-Host "== 1) 格式识别：封装（容器）与编码是两件事 ==" -ForegroundColor Cyan
$m4 = Join-Path $outDir 'mpeg4.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
     '-c:v','mpeg4','-q:v','5','-c:a','copy', $m4) | Out-Null
$m4D = Describe 'mpeg4.mp4（重编码）' $m4
Write-Host "    -> 同样是 MP4 容器，编码却可以是 h264 或 mpeg4：'MP4 编码'是错误说法"
Assert-True ($m4D.Container -like '*mp4*') "mpeg4.mp4 仍是 MP4 封装"
Assert-True ($m4D.Codecs -match 'video:mpeg4') "重编码后视频编码应为 mpeg4（与 h264 不同）"

# ---------- 2) 转换矩阵：转封装（-c copy）到六种容器 ----------
Write-Host "== 2) 转换矩阵：-c copy 无损转封装 ==" -ForegroundColor Cyan
$expect = @{ 'mp4'='mp4'; 'flv'='^flv'; 'mkv'='matroska'; 'avi'='^avi'; 'ts'='mpegts'; 'mov'='mp4' }
foreach ($ext in 'mp4','flv','mkv','avi','ts','mov') {
    $f = Join-Path $outDir "remux.$ext"
    $r = Ff @('-hide_banner','-loglevel','error','-y','-i',$src,'-c','copy', $f)
    $d = Describe "remux.$ext" $f
    Assert-True ($d.Container -match $expect[$ext]) "remux.$ext 封装应为 $($expect[$ext])（实际 $($d.Container)）"
    Assert-True ($d.Codecs -match 'video:h264' -and $d.Codecs -match 'audio:aac') "remux.$ext 转封装应保留 h264+aac"
    $script:matrix += [pscustomobject]@{
        Target = $ext; Container = $d.Container; Codecs = $d.Codecs
        SizeBytes = (Get-Item $f).Length; SourceFile = "remux.$ext"
    }
}

# ---------- 3) 踩坑：转封装失败（容器不支持该编码）----------
Write-Host "== 3) 踩坑：容器不支持该编码时 -c copy 失败 ==" -ForegroundColor Cyan
$vp8 = Join-Path $outDir 'v.webm'
Ff @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=160x120:rate=25:duration=2',
     '-c:v','libvpx','-an', $vp8) | Out-Null
$vp8bad = Join-Path $outDir 'vp8_copy.mp4'
$rb = FfTry @('-hide_banner','-loglevel','error','-y','-i',$vp8,'-c','copy', $vp8bad)
Write-Host "    VP8 -c copy -> mp4 : exit=$($rb.Code)"
Write-Host "    $((($rb.Output -split "`r?`n") | Where-Object { $_ -match 'not currently supported|Could not find tag' } | Select-Object -First 1))"
Assert-True ($rb.Code -ne 0) "VP8 直接转封装进 MP4 应失败"
Assert-True ($rb.Output -match 'not currently supported|Could not find tag') "失败原因应为容器不支持该编码"
# 修复：重编码为目标容器支持的编码
$vp8fix = Join-Path $outDir 'vp8_fixed.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i',$vp8,'-c:v','libx264','-pix_fmt','yuv420p', $vp8fix) | Out-Null
$fxD = Describe 'vp8_fixed.mp4（重编码修复）' $vp8fix
Assert-True ($fxD.Codecs -match 'video:h264') "重编码为 H.264 后可正常封装进 MP4"

# ---------- 4) 踩坑：MKV 多音轨，按索引选择 ----------
Write-Host "== 4) 踩坑：MKV 多音轨选择 ==" -ForegroundColor Cyan
$multi = Join-Path $outDir 'multi.mkv'
Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
     '-f','lavfi','-i','sine=frequency=880:sample_rate=44100:duration=2',
     '-map','0:v','-map','0:a','-map','1:a',
     '-c:v','copy','-c:a','aac','-shortest', $multi) | Out-Null
$aCount = ((Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','a','-show_entries','stream=index','-of','csv=p=0', $multi)).Output -split "`r?`n" | Where-Object { $_.Trim() -ne '' }).Count
Write-Host "    multi.mkv 音轨数 = $aCount，编码清单 = $((Streams $multi))"
Assert-True ($aCount -eq 2) "MKV 应含 2 条音轨"
# 不指定 map 时默认取第一条；-map 0:a:1 显式选第二条（880Hz）
$sel = Join-Path $outDir 'sel_a1.wav'
Ff @('-hide_banner','-loglevel','error','-y','-i',$multi,'-map','0:a:1','-c','copy', $sel) | Out-Null
$selCount = ((Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','a','-show_entries','stream=index','-of','csv=p=0', $sel)).Output -split "`r?`n" | Where-Object { $_.Trim() -ne '' }).Count
Write-Host "    -map 0:a:1 导出音轨数 = $selCount，大小 = $((Get-Item $sel).Length) B"
Assert-True ($selCount -eq 1) "按 0:a:1 应只导出第 2 条音轨"

# ---------- 5) 汇总：转换矩阵表 ----------
Write-Host "== 5) 转换矩阵表 ==" -ForegroundColor Cyan
$csv = Join-Path $outDir 'format_matrix.csv'
$script:matrix | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "    已写出 $csv（$($script:matrix.Count) 行）"
Write-Host ""
Write-Host "    目标容器  封装(format_name)              编码(codec)                体积(B)"
foreach ($m in $script:matrix) {
    Write-Host ("    {0,-9} {1,-28} {2,-24} {3}" -f $m.Target, $m.Container, $m.Codecs, $m.SizeBytes)
}

Write-Host "format_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
