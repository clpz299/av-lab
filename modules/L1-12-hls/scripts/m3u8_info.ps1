# m3u8_info.ps1 —— m3u8（HLS 播放列表）解析小工具
#
# 解析 HLS 播放列表，输出目标时长、媒体序列号、播放列表类型、是否含 ENDLIST、
# 切片数量、总时长与切片清单。用于验证 HLS 切片结果、观察直播滑动窗口。
#
# 用法：
#   powershell -NoProfile -File scripts\m3u8_info.ps1 -M3u8 out.m3u8
#   powershell -NoProfile -File scripts\m3u8_info.ps1 -M3u8 out.m3u8 -Json

param(
    [Parameter(Mandatory)][string]$M3u8,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $M3u8)) { throw "找不到 m3u8 文件: $M3u8" }

$inv = [System.Globalization.CultureInfo]::InvariantCulture
$targetDuration = $null
$mediaSequence  = 0
$playlistType   = ''
$version        = 0
$hasEndList     = $false
$segments       = @()
$pendingDur     = $null

foreach ($raw in (Get-Content -LiteralPath $M3u8)) {
    $t = $raw.Trim()
    if ($t -eq '') { continue }
    if ($t -like '#EXT-X-TARGETDURATION:*') {
        $targetDuration = [int]($t -replace '.*:', '')
    } elseif ($t -like '#EXT-X-MEDIA-SEQUENCE:*') {
        $mediaSequence = [int]($t -replace '.*:', '')
    } elseif ($t -like '#EXT-X-PLAYLIST-TYPE:*') {
        $playlistType = ($t -replace '.*:', '')
    } elseif ($t -like '#EXT-X-VERSION:*') {
        $version = [int]($t -replace '.*:', '')
    } elseif ($t -eq '#EXT-X-ENDLIST') {
        $hasEndList = $true
    } elseif ($t -like '#EXTINF:*') {
        $durStr = ($t -replace '^#EXTINF:', '') -replace ',.*$', ''
        $pendingDur = [double]::Parse($durStr, $inv)
    } elseif ($t.StartsWith('#')) {
        continue    # 其它标签（#EXTM3U 等）忽略
    } else {
        $segments += [pscustomobject]@{ Duration = $pendingDur; Uri = $t }
        $pendingDur = $null
    }
}

$total = 0.0
foreach ($s in $segments) { if ($null -ne $s.Duration) { $total += $s.Duration } }

$info = [pscustomobject]@{
    TargetDuration = $targetDuration
    MediaSequence  = $mediaSequence
    PlaylistType   = $playlistType
    Version        = $version
    HasEndList     = $hasEndList
    SegmentCount   = $segments.Count
    TotalDuration  = [math]::Round($total, 3)
    Segments       = $segments
}

if ($Json) {
    $info | ConvertTo-Json -Depth 5
} else {
    Write-Host "m3u8: $M3u8"
    Write-Host ("  版本            : {0}" -f $info.Version)
    Write-Host ("  目标时长        : {0}s" -f $info.TargetDuration)
    Write-Host ("  媒体序列号      : {0}" -f $info.MediaSequence)
    Write-Host ("  播放列表类型    : {0}" -f $(if ($info.PlaylistType) { $info.PlaylistType } else { '(无，直播/未标注)' }))
    Write-Host ("  含 ENDLIST      : {0}" -f $info.HasEndList)
    Write-Host ("  切片数量        : {0}" -f $info.SegmentCount)
    Write-Host ("  总时长          : {0}s" -f $info.TotalDuration)
    foreach ($s in $info.Segments) {
        Write-Host ("    - {0,-14} {1}s" -f $s.Uri, $s.Duration)
    }
}
