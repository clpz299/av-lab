# rtmp_practice.ps1 —— L1-11 直播/点播概念与推拉流初体验
#
# 链路：
#   0) 素材：ffmpeg 合成 H.264+AAC 的 3s MP4
#   1) 推流 -> 本地 RTMP 服务（ffmpeg -listen 1）收流落地，验证 RTMP 推流链路
#   2) 拉流本质：客户端连服务端拉码流；用 TCP ?listen=1 演示「边推边拉」（并发推/拉）
#   3) RTMP 地址结构：rtmp://host:port/app/streamName（端口默认 1935）
#   4) 踩坑：连不存在的 RTMP 服务 -> 失败信息
#   5) 服务端分发：RTMP 中继链 hub -> edge（对应 CDN 边缘分发）
# 用法：powershell -NoProfile -File scripts\rtmp_practice.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-11-rtmp'
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
function Field([string]$file, [string]$entries) {
    return (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries',$entries,'-of','default=nw=1:nk=1', $file)).Output.Trim()
}
function Codecs([string]$file, [string]$sel) {
    $r = (Invoke-AvNative $AvTool.Ffprobe @('-v','error','-select_streams',$sel,'-show_entries','stream=codec_name','-of','csv=p=0', $file)).Output
    return (($r -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
}
function Start-BgFf([string[]]$a, [string]$tag) {
    $o = Join-Path $outDir "$tag.out"; $e = Join-Path $outDir "$tag.err"
    return Start-Process -PassThru -FilePath $AvTool.Ffmpeg `
        -RedirectStandardOutput $o -RedirectStandardError $e -ArgumentList $a
}
function Stop-Bg($p, [int]$waitMs = 6000) {
    if ($null -eq $p) { return }
    $p.WaitForExit($waitMs) | Out-Null
    if (-not $p.HasExited) { $p.Kill() }
}
function Wait-Listen([int]$Port, [int]$TimeoutMs = 45000) {
    # 被动等待端口进入 LISTEN（不主动连接，避免消耗 ffmpeg -listen 的单次连接）
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}
function Parse-Rtmp([string]$url) {
    # rtmp://host[:port]/app/streamName ；端口缺省为 1935
    $m = [regex]::Match($url, '^rtmp://(?<host>[^:/]+)(?::(?<port>\d+))?/(?<app>[^/]+)/(?<stream>.+)$')
    if (-not $m.Success) { throw "非法 RTMP 地址: $url" }
    $port = if ($m.Groups['port'].Success) { [int]$m.Groups['port'].Value } else { 1935 }
    return [pscustomobject]@{
        Host = $m.Groups['host'].Value; Port = $port
        App  = $m.Groups['app'].Value;  Stream = $m.Groups['stream'].Value
    }
}

$serverScript = Join-Path $PSScriptRoot 'rtmp_server.ps1'

# ---------- 0) 素材 ----------
Write-Host "== 0) 素材：H.264 + AAC / 3s ==" -ForegroundColor Cyan
$src = Join-Path $outDir 'src.mp4'
Ff @('-hide_banner','-loglevel','error','-y',
     '-f','lavfi','-i','testsrc2=size=320x240:rate=25:duration=3',
     '-f','lavfi','-i','sine=frequency=440:sample_rate=44100:duration=3',
     '-c:v','libx264','-pix_fmt','yuv420p','-g','25','-c:a','aac','-b:a','96k','-shortest', $src) | Out-Null

# ---------- 1) 推流 -> 本地 RTMP 服务收流 ----------
Write-Host "== 1) 推流 -> 本地 RTMP 服务(ffmpeg -listen 1)收流 ==" -ForegroundColor Cyan
$rec = Join-Path $outDir 'live_rec.flv'
$srv = Start-Process -PassThru -FilePath 'powershell' -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',$serverScript,
    '-Port','1935','-App','live','-Stream','test','-OutFile',$rec)
Start-Sleep -Milliseconds 500
Assert-True (Wait-Listen 1935) "本地 RTMP 服务应在 45s 内监听 1935"
Write-Host "    推流：-re -i src.mp4 -c copy -f flv rtmp://127.0.0.1:1935/live/test"
Ff @('-hide_banner','-loglevel','error','-y','-re','-i',$src,'-c','copy','-f','flv','rtmp://127.0.0.1:1935/live/test') | Out-Null
Stop-Bg $srv
Assert-True (Test-Path $rec) "服务端应落地 live_rec.flv"
$v = Codecs $rec 'v'; $a = Codecs $rec 'a'
Write-Host "    服务端落地 live_rec.flv：$((Get-Item $rec).Length) B，视频=$v 音频=$a，时长=$((Field $rec 'format=duration'))"
Assert-True ($v -contains 'h264') "RTMP 收流应含 H.264 视频"
Assert-True ($a -contains 'aac')  "RTMP 收流应含 AAC 音频"
Assert-True ([double](Field $rec 'format=duration') -gt 2.5) "收流时长应接近源 3s"

# ---------- 2) 拉流本质：并发「边推边拉」（TCP ?listen=1） ----------
Write-Host "== 2) 拉流本质：客户端连接服务端拉码流（TCP ?listen=1 并发推/拉）==" -ForegroundColor Cyan
$pubts = Join-Path $outDir 'pub_listen.ts'
$pub = Start-BgFf @('-hide_banner','-loglevel','error','-y','-re','-i',$src,
                    '-c','copy','-f','mpegts','tcp://127.0.0.1:8899?listen=1') 'push'
Start-Sleep -Milliseconds 500
Assert-True (Wait-Listen 8899) "推流端应在 45s 内监听 8899"
Write-Host "    推流端监听 tcp://127.0.0.1:8899，拉流端连接拉取..."
$pullOut = Join-Path $outDir 'pull.ts'
Ff @('-hide_banner','-loglevel','error','-y','-i','tcp://127.0.0.1:8899','-c','copy','-f','mpegts',$pullOut) | Out-Null
Stop-Bg $pub 4000
Assert-True (Test-Path $pullOut) "拉流端应拿到 pull.ts"
$pv = Codecs $pullOut 'v'; $pa = Codecs $pullOut 'a'
Write-Host "    拉流得到 pull.ts：$((Get-Item $pullOut).Length) B，视频=$pv 音频=$pa"
Assert-True ($pv -contains 'h264' -and $pa -contains 'aac') "拉流内容应与源一致（h264+aac）"

# ---------- 3) RTMP 地址结构 ----------
Write-Host "== 3) RTMP 地址结构 rtmp://host:port/app/streamName ==" -ForegroundColor Cyan
$u1 = Parse-Rtmp 'rtmp://127.0.0.1/live/test'
$u2 = Parse-Rtmp 'rtmp://push.example.com:1936/live/room01'
Write-Host "    rtmp://127.0.0.1/live/test           -> host=$($u1.Host) port=$($u1.Port) app=$($u1.App) stream=$($u1.Stream)"
Write-Host "    rtmp://push.example.com:1936/live/room01 -> host=$($u2.Host) port=$($u2.Port) app=$($u2.App) stream=$($u2.Stream)"
Assert-True ($u1.Port -eq 1935) "未写端口时应缺省为 1935"
Assert-True ($u2.Port -eq 1936) "显式端口应被解析"
Assert-True ($u2.App -eq 'live' -and $u2.Stream -eq 'room01') "app/stream 应正确解析"

# ---------- 4) 踩坑：连不存在的 RTMP 服务 ----------
Write-Host "== 4) 踩坑：推流地址写错/端口未监听 ==" -ForegroundColor Cyan
$r = FfTry @('-hide_banner','-loglevel','error','-y','-re','-i',$src,'-c','copy','-f','flv','rtmp://127.0.0.1:1999/live/nope')
Write-Host "    exit=$($r.Code)"
Write-Host "    $((($r.Output -split "`r?`n") | Where-Object { $_ -match 'Cannot open connection|Error opening output' } | Select-Object -First 1))"
Assert-True ($r.Code -ne 0) "连接不存在的 RTMP 服务应失败"
Assert-True ($r.Output -match 'Cannot open connection|Error opening output') "失败信息应为无法建立连接/打开输出"

# ---------- 5) 服务端分发：RTMP 中继链 hub -> edge ----------
Write-Host "== 5) 服务端分发：RTMP 中继链 hub(1936) -> edge(1937) ==" -ForegroundColor Cyan
$chainRec = Join-Path $outDir 'chain_rec.flv'
$edge = Start-BgFf @('-hide_banner','-loglevel','error','-y','-listen','1','-f','flv',
                     '-i','rtmp://127.0.0.1:1937/live/edge','-c','copy','-f','flv',$chainRec) 'edge'
Start-Sleep -Milliseconds 500
Assert-True (Wait-Listen 1937) "边缘节点应在 20s 内监听 1937"
$hub = Start-BgFf @('-hide_banner','-loglevel','error','-y','-listen','1','-f','flv',
                    '-i','rtmp://127.0.0.1:1936/live/hub','-c','copy','-f','flv',
                    'rtmp://127.0.0.1:1937/live/edge') 'hub'
Start-Sleep -Milliseconds 500
Assert-True (Wait-Listen 1936) "中继节点应在 20s 内监听 1936"
Ff @('-hide_banner','-loglevel','error','-y','-re','-i',$src,'-c','copy','-f','flv','rtmp://127.0.0.1:1936/live/hub') | Out-Null
Stop-Bg $hub; Stop-Bg $edge
Assert-True (Test-Path $chainRec) "边缘节点应落地 chain_rec.flv"
$cv = Codecs $chainRec 'v'
Write-Host "    边缘落地 chain_rec.flv：$((Get-Item $chainRec).Length) B，视频=$cv 音频=$(Codecs $chainRec 'a')"
Assert-True ($cv -contains 'h264') "经中继后边缘仍应收到 H.264"

Write-Host "rtmp_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
