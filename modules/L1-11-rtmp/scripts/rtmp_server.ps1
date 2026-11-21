# rtmp_server.ps1 —— 一键启动本地 RTMP 服务（收流并落地为 FLV）
#
# 说明：本工程为了「零外部依赖、可自动测试」，用 ffmpeg 的 rtmp listen 模式充当本地 RTMP 服务端：
#   ffmpeg -listen 1 -f flv -i rtmp://127.0.0.1:1935/live/test -c copy -f flv live_rec.flv
# 它以 RTMP 服务端身份等待一个推流端接入，收到码流后原样落地。生产环境请用 Nginx-rtmp / SRS，
# 参见同目录 nginx-rtmp.conf。
#
# 用法：
#   powershell -NoProfile -File scripts\rtmp_server.ps1                 # 监听 1935 / live / test
#   powershell -NoProfile -File scripts\rtmp_server.ps1 -Port 1936 -Stream s2 -Loop
#
# 参数：
#   -Port    监听端口（RTMP 默认 1935）
#   -App     应用名（rtmp 地址中的 app 段，默认 live）
#   -Stream  流名（rtmp 地址中的 stream 段，默认 test）
#   -OutFile 落地文件路径（默认 build/_artifacts/L1-11-rtmp/live_rec.flv）
#   -Loop    持续监听（推流端断开后自动重新监听，模拟常驻服务）

param(
    [int]$Port = 1935,
    [string]$App = 'live',
    [string]$Stream = 'test',
    [string]$OutFile,
    [switch]$Loop
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

if (-not $OutFile) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $OutFile = Join-Path $repoRoot 'build\_artifacts\L1-11-rtmp\live_rec.flv'
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null

$url = "rtmp://127.0.0.1:$Port/$App/$Stream"
Write-Host "[rtmp-server] listen $url -> $OutFile" -ForegroundColor Cyan

do {
    # -listen 1 让 ffmpeg 作为 RTMP 服务端等待推流端接入；收到后 -c copy 落地
    $r = Invoke-AvNative $AvTool.Ffmpeg @(
        '-hide_banner','-loglevel','warning','-y',
        '-listen','1','-f','flv','-i',$url,'-c','copy','-f','flv',$OutFile)
    if ($r.Output) { Write-Host $r.Output }
    Write-Host "[rtmp-server] 推流端已断开 (exit=$($r.Code))" -ForegroundColor Yellow
} while ($Loop)
