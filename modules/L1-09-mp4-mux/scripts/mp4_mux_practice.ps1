# mp4_mux_practice.ps1 —— L1-09 MP4 文件生成与封装入门
#
# 链路：带音视频的 MP4 -> 解封装拆出 H.264 裸流 + AAC 裸流 -> 再用 -c copy 封装回 MP4。
# 附带：查看 MP4 顶层 box 结构、faststart 对比、帧率/ADTS 两个封装坑。
# 用法：powershell -NoProfile -File scripts\mp4_mux_practice.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-09-mp4-mux'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function Ff([string[]]$a) {
    $r = Invoke-AvNative $AvTool.Ffmpeg $a
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "ffmpeg 失败 (exit=$($r.Code)): $($a -join ' ')" }
    return $r
}
function FfTry([string[]]$a) { return (Invoke-AvNative $AvTool.Ffmpeg $a) }
function VField([string]$file, [string]$entries) {
    return (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','v:0','-show_entries',$entries,'-of','default=nw=1', $file)).Output
}
function Get-Key([string]$txt, [string]$key) {
    if ($txt -match "(?m)^$key=(\S+)") { return $Matches[1] }
    throw "未能从 ffprobe 输出解析 $key ：$txt"
}
function Head([string]$file, [int]$n) {
    $b = [System.IO.File]::ReadAllBytes($file)
    return ($b[0..($n-1)] | ForEach-Object { $_.ToString('x2') }) -join ' '
}
function Boxes([string]$file) {
    # 解析顶层 box：4 字节 big-endian size + 4 字节 type；size==1 表示 64 位长度（本实验素材用不到）
    $b = [System.IO.File]::ReadAllBytes($file)
    $pos = 0; $res = @()
    while ($pos + 8 -le $b.Length) {
        $size = ([int]$b[$pos] -shl 24) -bor ([int]$b[$pos+1] -shl 16) -bor ([int]$b[$pos+2] -shl 8) -bor [int]$b[$pos+3]
        $type = [System.Text.Encoding]::ASCII.GetString($b[($pos+4)..($pos+7)])
        $res += [pscustomobject]@{ Type = $type; Size = $size }
        if ($size -le 0) { break }
        $pos += $size
    }
    return $res
}

# ---------- 0) 素材：带音视频的 MP4（320x240 / 30fps / 2s + 440Hz 正弦）----------
Write-Host "== 0) 生成带音视频的 MP4 素材 ==" -ForegroundColor Cyan
$src = Join-Path $outDir 'src.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=320x240:rate=30:duration=2',
     '-f','lavfi','-i','sine=frequency=440:sample_rate=44100:duration=2',
     '-c:v','libx264','-pix_fmt','yuv420p','-g','30','-c:a','aac','-b:a','96k','-shortest', $src) | Out-Null
$srcFmt = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','format=format_name,duration','-of','default=nw=1', $src)).Output
Write-Host "    $($srcFmt -replace "`r?`n", ' / ')"
Assert-True ((Get-Key $srcFmt 'format_name') -like '*mp4*') "素材应为 MP4 封装"
Assert-True ([double](Get-Key $srcFmt 'duration') -gt 1.9) "素材时长应约 2s"

# ---------- 1) 解封装（demux）：拆出 H.264 裸流 + AAC 裸流 ----------
Write-Host "== 1) 解封装：拆出 H.264 / AAC 裸流 ==" -ForegroundColor Cyan
$v264 = Join-Path $outDir 'v.h264'
$aac  = Join-Path $outDir 'a.aac'
# MP4 里视频是 AVCC（长度前缀），导出裸流必须转成 Annex-B：-bsf:v h264_mp4toannexb
Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
     '-c','copy','-bsf:v','h264_mp4toannexb','-f','h264', $v264) | Out-Null
Ff @('-hide_banner','-loglevel','error','-y','-i',$src,
     '-c','copy','-vn','-f','adts', $aac) | Out-Null
$vHead = Head $v264 4
$aHead = Head $aac 2
Write-Host "    v.h264 首 4 字节 = $vHead（Annex-B 起始码 00 00 00 01）"
Write-Host "    a.aac  首 2 字节 = $aHead（ADTS 同步字 ff f1）"
Assert-True ($vHead -eq '00 00 00 01') "H.264 裸流应以 4 字节起始码 00000001 开头"
$ah = $aHead -split ' '
Assert-True ($ah[0] -eq 'ff' -and (([Convert]::ToInt32($ah[1],16) -band 0xF0) -eq 0xF0)) "AAC 裸流应为 ADTS（ff f0/ff f1）"
Assert-True ((Get-Item $v264).Length -gt 0 -and (Get-Item $aac).Length -gt 0) "拆分结果不应为空"

# ---------- 2) 封装（mux）：裸流 -> MP4 ----------
Write-Host "== 2) 封装：H.264 + AAC 裸流封回 MP4 ==" -ForegroundColor Cyan
$ok = Join-Path $outDir 'remux.mp4'
# 裸流无时间戳，用 -r 指定帧率；AAC 显式加 aac_adtstoasc 保证 ADTS 转 ASC
Ff @('-hide_banner','-loglevel','error','-y',
     '-r','30','-i',$v264,
     '-i',$aac,
     '-c','copy','-bsf:a','aac_adtstoasc', $ok) | Out-Null
$okFmt = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','format=format_name,nb_streams,duration','-of','default=nw=1', $ok)).Output
Write-Host "    $($okFmt -replace "`r?`n", ' / ')"
$okStreams = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','stream=codec_type,codec_name','-of','default=nw=1', $ok)).Output
Write-Host "    streams: $($okStreams -replace "`r?`n", ' / ')"
Assert-True ((Get-Key $okFmt 'format_name') -like '*mp4*') "封装结果应为 MP4"
Assert-True ((Get-Key $okFmt 'nb_streams') -eq '2') "封装结果应含视频+音频两条流"
Assert-True ($okStreams -match 'codec_name=h264' -and $okStreams -match 'codec_name=aac') "应为 H.264 视频 + AAC 音频"

# ---------- 3) MP4 顶层 box 结构 ----------
Write-Host "== 3) MP4 顶层 box 结构 ==" -ForegroundColor Cyan
$boxes = Boxes $ok
foreach ($b in $boxes) { Write-Host ("    {0,-4} size={1}" -f $b.Type, $b.Size) }
$types = $boxes | ForEach-Object { $_.Type }
Assert-True ($types -contains 'ftyp') "MP4 应含 ftyp box（文件类型）"
Assert-True ($types -contains 'moov') "MP4 应含 moov box（元数据）"
Assert-True ($types -contains 'mdat') "MP4 应含 mdat box（媒体数据）"
Assert-True (([array]::IndexOf($types,'moov')) -gt ([array]::IndexOf($types,'mdat'))) "默认 moov 在 mdat 之后（非 faststart）"

# ---------- 4) faststart：把 moov 前移，利于边下边播 ----------
Write-Host "== 4) faststart：moov 前移 ==" -ForegroundColor Cyan
$fast = Join-Path $outDir 'remux_faststart.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-r','30','-i',$v264,'-i',$aac,
     '-c','copy','-bsf:a','aac_adtstoasc','-movflags','+faststart', $fast) | Out-Null
$fTypes = (Boxes $fast) | ForEach-Object { $_.Type }
Write-Host "    默认 box 顺序: $($types -join ' -> ')"
Write-Host "    faststart 顺序: $($fTypes -join ' -> ')"
Assert-True (([array]::IndexOf($fTypes,'moov')) -lt ([array]::IndexOf($fTypes,'mdat'))) "+faststart 应让 moov 排在 mdat 之前"

# ---------- 5) 踩坑：裸流无时间戳，帧率设错导致时长异常 ----------
Write-Host "== 5) 踩坑：帧率设错 -> 时长异常 ==" -ForegroundColor Cyan
$r60 = Join-Path $outDir 'remux_r60.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-r','60','-i',$v264,'-i',$aac,
     '-c','copy','-bsf:a','aac_adtstoasc', $r60) | Out-Null
$d30 = [double](Get-Key (VField $ok  'stream=duration') 'duration')
$d60 = [double](Get-Key (VField $r60 'stream=duration') 'duration')
Write-Host "    -r 30 -> 视频时长 $d30 s ；-r 60 -> 视频时长 $d60 s"
Assert-True ($d30 -gt 1.9 -and $d30 -lt 2.1) "-r 30 时长应约 2s（实际 $d30）"
Assert-True ($d60 -lt 1.1) "-r 60 会让 2s 素材只播约 1s（实际 $d60）"
Assert-True ($d30 -gt $d60) "帧率填大一倍，时长应缩短"

# ---------- 6) 踩坑：ADTS -> ASC（aac_adtstoasc）----------
Write-Host "== 6) 踩坑：ADTS 裸流 vs MP4 内的 ASC ==" -ForegroundColor Cyan
# 新版 ffmpeg 在读取 ADTS 裸流时会自动提取 AudioSpecificConfig，不显式加 bsf 也能成功；
# 但 MP4 内的 AAC 一定不带 ADTS 头，而是用 esds(ASC) 描述。
$noBsf = Join-Path $outDir 'remux_nobsf.mp4'
$rb = FfTry @('-hide_banner','-loglevel','error','-y','-r','30','-i',$v264,'-i',$aac,'-c','copy', $noBsf)
$okAac  = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','a:0','-show_entries','stream=codec_name,extradata_size','-of','default=nw=1', $ok)).Output
$noAac  = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','a:0','-show_entries','stream=codec_name,extradata_size','-of','default=nw=1', $noBsf)).Output
Write-Host "    .aac 裸流首字节 ff f1 为每帧 7 字节 ADTS 头"
Write-Host "    显式 bsf  MP4 音频: $($okAac -replace "`r?`n", ' / ')"
Write-Host "    省略 bsf  MP4 音频: $($noAac -replace "`r?`n", ' / ')（exit=$($rb.Code)）"
Assert-True ((Get-Key $okAac 'codec_name') -eq 'aac') "MP4 音频应为 AAC"
Assert-True ([int](Get-Key $okAac 'extradata_size') -lt 7) "MP4 内 AAC 用 ASC 描述（extradata 远小于 7 字节 ADTS 头）"
Assert-True ([int](Get-Key $noAac 'extradata_size') -lt 7) "省略 bsf 时新版 ffmpeg 会自动转换 ADTS->ASC"

Write-Host "mp4_mux_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
