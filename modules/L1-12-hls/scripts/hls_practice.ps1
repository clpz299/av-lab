# hls_practice.ps1 —— L1-12 HLS 切片与 m3u8 播放实验
#
# 链路：MP4 -> HLS 切片(m3u8 + ts) -> 解析 m3u8 -> 经 m3u8 拉流回放；
# 并踩透三个坑：hls_time 受 GOP 影响、非关键帧切片(花屏)、直播滑动窗口。
# 用法：powershell -NoProfile -File scripts\hls_practice.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-12-hls'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$m3u8Tool = Join-Path $PSScriptRoot 'm3u8_info.ps1'

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function Ff([string[]]$a) {
    $r = Invoke-AvNative $AvTool.Ffmpeg $a
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "ffmpeg 失败 (exit=$($r.Code)): $($a -join ' ')" }
    return $r
}
function M3u8Info([string]$f) {
    return ((& $m3u8Tool -M3u8 $f -Json) | Out-String | ConvertFrom-Json)
}
function KeyFrames([string]$f) {
    $r = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams','v:0','-skip_frame','nokey',
                                          '-show_entries','frame=key_frame','-of','csv=p=0', $f)
    return (($r.Output -split "`r?`n") | Where-Object { $_.Trim() -eq '1' }).Count
}
function SegPath([string]$prefix, [int]$i) { return (Join-Path $outDir ("{0}_{1:d3}.ts" -f $prefix, $i)) }

# ---------- 0) 素材：8s，关键帧间隔 1s ----------
Write-Host "== 0) 素材：8s / GOP=1s / H.264+AAC ==" -ForegroundColor Cyan
$src = Join-Path $outDir 'src.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=8',
     '-f','lavfi','-i','sine=frequency=440:sample_rate=44100:duration=8',
     '-c:v','libx264','-pix_fmt','yuv420p','-g','25','-keyint_min','25','-sc_threshold','0',
     '-c:a','aac','-b:a','96k','-shortest', $src) | Out-Null

# ---------- 1) 切片（VOD） ----------
Write-Host "== 1) HLS 切片：-c copy -hls_time 2 -hls_list_size 0 -hls_playlist_type vod ==" -ForegroundColor Cyan
$vodd = Join-Path $outDir 'vod.m3u8'
Ff @('-hide_banner','-loglevel','error','-y','-i',$src,'-c','copy','-f','hls',
     '-hls_time','2','-hls_list_size','0','-hls_playlist_type','vod',
     '-hls_segment_filename',(Join-Path $outDir 'vod_%03d.ts'), $vodd) | Out-Null
$v = M3u8Info $vodd
Write-Host "    切片数=$($v.SegmentCount) 目标时长=$($v.TargetDuration)s 类型=$($v.PlaylistType) ENDLIST=$($v.HasEndList) 总时长=$($v.TotalDuration)s"
Assert-True ($v.SegmentCount -eq 4) "8s / hls_time=2 / GOP=1s 应切成 4 段（实际 $($v.SegmentCount)）"
Assert-True ($v.TargetDuration -eq 2) "EXT-X-TARGETDURATION 应为 2"
Assert-True ($v.PlaylistType -eq 'VOD') "应标注 EXT-X-PLAYLIST-TYPE:VOD"
Assert-True ($v.HasEndList) "VOD 应含 EXT-X-ENDLIST"
Assert-True ([math]::Abs($v.TotalDuration - 8) -lt 0.2) "各段时长之和应约为 8s（实际 $($v.TotalDuration)）"
# 每段都从关键帧开始（段内至少 1 个关键帧），可独立解码
for ($i = 0; $i -lt $v.SegmentCount; $i++) {
    $kf = KeyFrames (SegPath 'vod' $i)
    Assert-True ($kf -ge 1) "关键帧对齐切片下，每段应含关键帧（vod_$i 关键帧数=$kf）"
}

# ---------- 2) TS 段结构 ----------
Write-Host "== 2) TS 段结构：0x47 同步字节 / 188 字节定长包 ==" -ForegroundColor Cyan
$seg0 = SegPath 'vod' 0
$b = [System.IO.File]::ReadAllBytes($seg0)
$sync = 0
for ($i = 0; $i -lt [Math]::Min($b.Length, 188 * 8); $i += 188) { if ($b[$i] -eq 0x47) { $sync++ } }
Write-Host ("    vod_000.ts 首字节=0x{0:X2} 长度={1} 能否被188整除={2} 前8包同步命中={3}" -f $b[0], $b.Length, ($b.Length % 188 -eq 0), $sync)
Assert-True ($b[0] -eq 0x47) "TS 段首字节应为同步字节 0x47"
Assert-True ($b.Length % 188 -eq 0) "TS 段长度应为 188 的整数倍"
Assert-True ($sync -eq 8) "TS 每 188 字节应以 0x47 开头"

# ---------- 3) 经 m3u8 拉流回放 ----------
Write-Host "== 3) 播放器视角：ffmpeg -i vod.m3u8 拉流解码 ==" -ForegroundColor Cyan
$replay = Join-Path $outDir 'replay.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-i',$vodd,'-c','copy',$replay) | Out-Null
$dur = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1', $replay)).Output.Trim()
$ns  = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','format=nb_streams','-of','default=nw=1:nk=1', $replay)).Output.Trim()
Write-Host "    replay.mp4 流数=$ns 时长=$dur"
Assert-True ($ns -eq '2') "经 m3u8 拉流回放应得到音视频 2 条流"
Assert-True ([double]$dur -gt 7.5) "回放时长应接近源 8s（实际 $dur）"

# ---------- 4) 踩坑：GOP 过大 -> hls_time 不生效 ----------
Write-Host "== 4) 踩坑：GOP=10s 时 hls_time=2 失效 ==" -ForegroundColor Cyan
$srcBig = Join-Path $outDir 'src_g250.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=8',
     '-f','lavfi','-i','sine=frequency=440:sample_rate=44100:duration=8',
     '-c:v','libx264','-pix_fmt','yuv420p','-g','250','-keyint_min','250','-sc_threshold','0',
     '-c:a','aac','-b:a','96k','-shortest', $srcBig) | Out-Null
$bigM3u8 = Join-Path $outDir 'big.m3u8'
Ff @('-hide_banner','-loglevel','error','-y','-i',$srcBig,'-c','copy','-f','hls',
     '-hls_time','2','-hls_list_size','0','-hls_playlist_type','vod',
     '-hls_segment_filename',(Join-Path $outDir 'big_%03d.ts'), $bigM3u8) | Out-Null
$vb = M3u8Info $bigM3u8
Write-Host "    切片数=$($vb.SegmentCount) 目标时长=$($vb.TargetDuration)s 总时长=$($vb.TotalDuration)s"
Assert-True ($vb.SegmentCount -eq 1) "关键帧间隔 10s > hls_time 2s，只能切成 1 段（实际 $($vb.SegmentCount)）"
Assert-True ($vb.TargetDuration -eq 8) "切片拉长后 TARGETDURATION 随之增大到 8"

# ---------- 5) 踩坑：非关键帧切片 -> 花屏 ----------
Write-Host "== 5) 踩坑：-hls_flags split_by_time 强行按时间切 ==" -ForegroundColor Cyan
$spM3u8 = Join-Path $outDir 'split.m3u8'
Ff @('-hide_banner','-loglevel','error','-y','-i',$srcBig,'-c','copy','-f','hls',
     '-hls_time','2','-hls_list_size','0','-hls_playlist_type','vod','-hls_flags','split_by_time',
     '-hls_segment_filename',(Join-Path $outDir 'split_%03d.ts'), $spM3u8) | Out-Null
$vs = M3u8Info $spM3u8
$kfList = @()
for ($i = 0; $i -lt $vs.SegmentCount; $i++) { $kfList += (KeyFrames (SegPath 'split' $i)) }
Write-Host "    切片数=$($vs.SegmentCount) 各段关键帧数=[$($kfList -join ', ')]"
Assert-True ($vs.SegmentCount -eq 4) "split_by_time 允许按时间强行切成 4 段（忽略关键帧边界）"
Assert-True (($kfList | Where-Object { $_ -eq 0 }).Count -ge 1) "强行按时间切会产生不含关键帧的段（播放/换段花屏）"

# ---------- 6) 直播滑动窗口 ----------
Write-Host "== 6) 直播滑动窗口：-hls_list_size 3 ==" -ForegroundColor Cyan
$liveM3u8 = Join-Path $outDir 'live.m3u8'
Ff @('-hide_banner','-loglevel','error','-y','-i',$src,'-c','copy','-f','hls',
     '-hls_time','2','-hls_list_size','3',
     '-hls_segment_filename',(Join-Path $outDir 'live_%03d.ts'), $liveM3u8) | Out-Null
$vl = M3u8Info $liveM3u8
Write-Host "    切片数=$($vl.SegmentCount) 序列号=$($vl.MediaSequence) 类型=$(if($vl.PlaylistType){$vl.PlaylistType}else{'(无)'})"
Assert-True ($vl.SegmentCount -eq 3) "滑动窗口应只保留最近 3 个切片"
Assert-True ($vl.MediaSequence -eq 1) "滑动后媒体序列号前移到 1"
Assert-True (-not $vl.PlaylistType) "直播/滑动窗口模式不标注 PLAYLIST-TYPE"

# ---------- 7) m3u8 解析工具输出 ----------
Write-Host "== 7) m3u8 解析小工具 ==" -ForegroundColor Cyan
& $m3u8Tool -M3u8 $vodd

Write-Host "hls_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
