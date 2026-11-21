# quality_practice.ps1 —— L1-15 客观质量指标计算：PSNR / SSIM / SNR
#
# 链路：同一源(原始 YUV) -> 多码率转码 -> 解码回 YUV420P -> quality_tools 算指标
#       -> CSV + ASCII 曲线；并用 ffmpeg 的 psnr 滤镜做交叉验证。
# 踩坑：分辨率不一致、像素格式不统一（都无法直接比较）。
# 用法：powershell -NoProfile -File scripts\quality_practice.ps1 <quality_tools.exe 路径>
#       （CTest 会通过 $<TARGET_FILE:quality_tools> 自动传入；手工运行可省略）

param([string]$QualityTools)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-15-quality'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $QualityTools) {
    $cand = Get-ChildItem -Path (Join-Path $repoRoot 'build') -Recurse -Filter 'quality_tools.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cand) { throw "未找到 quality_tools.exe，请先构建或显式传入路径" }
    $QualityTools = $cand.FullName
}
if (-not (Test-Path $QualityTools)) { throw "quality_tools 不存在: $QualityTools" }

function Assert-True([bool]$cond, [string]$msg) { if (-not $cond) { throw "断言失败: $msg" } }
function Ff([string[]]$a) {
    $r = Invoke-AvNative $AvTool.Ffmpeg $a
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "ffmpeg 失败 (exit=$($r.Code)): $($a -join ' ')" }
    return $r
}
function Run-Quality([string]$ref, [string]$test, [int]$w, [int]$h) {
    $r = Invoke-AvNative $QualityTools @($ref, $test, "$w", "$h")
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "quality_tools 失败 (exit=$($r.Code)): $ref vs $test" }
    return $r.Output
}
function Result-Of([string]$output) {
    $line = ($output -split "`r?`n") | Where-Object { $_ -like 'RESULT *' } | Select-Object -Last 1
    if (-not $line) { throw "未找到 RESULT 行：$output" }
    return ($line.Substring('RESULT '.Length) | ConvertFrom-Json)
}
# ffmpeg psnr 滤镜：取末行 'PSNR y:.. u:.. v:.. average:.. min:.. max:..' 的 y 值
function FfPsnrY([string]$mp4, [string]$refYuv, [int]$w, [int]$h, [int]$fps) {
    $r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner',
        '-i', $mp4,
        '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-s', "${w}x${h}", '-r', "$fps", '-i', $refYuv,
        '-lavfi', '[0:v][1:v]psnr', '-f', 'null', '-')
    $line = ($r.Output -split "`r?`n") | Where-Object { $_ -match 'PSNR y:' } | Select-Object -Last 1
    if (-not $line) { return $null }
    $m = [regex]::Match($line, 'y:([0-9.]+)')
    if (-not $m.Success) { return $null }
    return [double]$m.Groups[1].Value
}
function Bar([double]$v, [double]$minV, [double]$maxV, [int]$width = 40) {
    if ($maxV -le $minV) { return ('#' * $width) }
    $n = [int][math]::Round(($v - $minV) / ($maxV - $minV) * $width)
    if ($n -lt 0) { $n = 0 }
    if ($n -gt $width) { $n = $width }
    return ('#' * $n)
}
function R4([double]$v) { return [math]::Round($v, 4) }

$W = 640; $H = 360; $FPS = 25; $DUR = 1
$frameBytes = $W * $H * 3 / 2

# ---------- 0) 参考基准：原始 YUV（无损） ----------
Write-Host "== 0) 生成参考基准（原始 YUV，无损）==" -ForegroundColor Cyan
$refYuv = Join-Path $outDir 'ref_640x360.yuv'
Ff @('-hide_banner','-loglevel','error','-y','-f','lavfi',
     '-i', "testsrc2=size=${W}x${H}:rate=${FPS}:duration=$DUR",
     '-pix_fmt','yuv420p','-f','rawvideo', $refYuv) | Out-Null
$refFrames = [int]((Get-Item $refYuv).Length / $frameBytes)
Assert-True ($refFrames -eq ($FPS * $DUR)) "参考 YUV 帧数应为 $($FPS * $DUR)，实际 $refFrames"
Write-Host "  参考：$refYuv ($refFrames 帧, ${W}x${H} YUV420P)" -ForegroundColor Gray

# ---------- 1) 多码率转码 + 指标计算 ----------
Write-Host "== 1) 多码率转码 -> 指标计算（PSNR / SSIM / SNR）==" -ForegroundColor Cyan
$bitrates = @(2000, 1000, 500, 250)   # kbps
$psnrTol  = 0.5                        # 与 ffmpeg 交叉验证的允许误差(dB)
$results  = @()

foreach ($br in $bitrates) {
    $mp4 = Join-Path $outDir ("br_{0}k.mp4" -f $br)
    $yuv = Join-Path $outDir ("br_{0}k.yuv" -f $br)
    Ff @('-hide_banner','-loglevel','error','-y',
         '-f','rawvideo','-pix_fmt','yuv420p','-s',"${W}x${H}",'-r',"$FPS",'-i',$refYuv,
         '-c:v','libx264','-b:v',"${br}k",'-pix_fmt','yuv420p','-g','25','-an', $mp4) | Out-Null
    Ff @('-hide_banner','-loglevel','error','-y','-i',$mp4,'-pix_fmt','yuv420p','-f','rawvideo', $yuv) | Out-Null
    # 首帧 PNG，供主观对照
    Ff @('-hide_banner','-loglevel','error','-y','-i',$mp4,'-frames:v','1', (Join-Path $outDir ("frame_{0}k.png" -f $br))) | Out-Null

    $res = Result-Of (Run-Quality $refYuv $yuv $W $H)
    Assert-True ($res.frames -eq $refFrames) "${br}k 参与比较的帧数应为 $refFrames"

    # 交叉验证：我们的 PSNR(Y) 应与 ffmpeg psnr 滤镜接近
    $ffPsnr = FfPsnrY $mp4 $refYuv $W $H $FPS
    Assert-True ($null -ne $ffPsnr) "${br}k 应能从 ffmpeg psnr 输出中解析出 y 值"
    $diff = [math]::Abs([double]$res.psnr_y - $ffPsnr)
    Assert-True ($diff -lt $psnrTol) "`n   ${br}k PSNR(Y) 自算 $($res.psnr_y) 与 ffmpeg $ffPsnr 误差 $([math]::Round($diff,4)) 应 < $psnrTol dB"
    Write-Host ("  {0,5}k : PSNR_Y={1,8} SSIM={2,8} SNR={3,8} | ffmpeg PSNR_Y={4,8} (Δ={5})" -f `
        $br, $res.psnr_y, $res.ssim, $res.snr, $ffPsnr, [math]::Round($diff,4)) -ForegroundColor Gray

    $results += [pscustomobject]@{
        Kbps = $br; Mp4 = $mp4
        PsnrY = [double]$res.psnr_y; PsnrU = [double]$res.psnr_u; PsnrV = [double]$res.psnr_v
        PsnrAvg = [double]$res.psnr_avg; Ssim = [double]$res.ssim; Snr = [double]$res.snr
        FfPsnrY = $ffPsnr
    }
}

# 单调性：码率越低，PSNR / SSIM / SNR 应不高于高码率
for ($i = 0; $i -lt $results.Count - 1; $i++) {
    Assert-True ($results[$i].PsnrY -ge $results[$i + 1].PsnrY - 0.01) "码率高者 PSNR 不应低于码率低者（$($results[$i].Kbps)k vs $($results[$i+1].Kbps)k）"
    Assert-True ($results[$i].Ssim  -ge $results[$i + 1].Ssim  - 1e-6) "码率高者 SSIM 不应低于码率低者（$($results[$i].Kbps)k vs $($results[$i+1].Kbps)k）"
}

# ---------- 2) CSV + ASCII 曲线 ----------
Write-Host "== 2) 输出 CSV 与 ASCII 曲线 ==" -ForegroundColor Cyan
$csvPath = Join-Path $outDir 'metrics.csv'
$lines = @('bitrate_kbps,frames,psnr_y,psnr_u,psnr_v,psnr_avg,ssim_y,snr_y')
foreach ($r in $results) {
    $lines += ("{0},{1},{2},{3},{4},{5},{6},{7}" -f $r.Kbps, $refFrames,
               (R4 $r.PsnrY), (R4 $r.PsnrU), (R4 $r.PsnrV), (R4 $r.PsnrAvg), (R4 $r.Ssim), (R4 $r.Snr))
}
$lines += ''
$lines += '# +ffmpeg psnr 交叉验证（PSNR Y）'
$lines += 'bitrate_kbps,self_psnr_y,ffmpeg_psnr_y,abs_diff_db'
foreach ($r in $results) {
    $lines += ("{0},{1},{2},{3}" -f $r.Kbps, (R4 $r.PsnrY), (R4 $r.FfPsnrY), (R4 ([math]::Abs($r.PsnrY - $r.FfPsnrY))))
}
$lines | Set-Content -Encoding UTF8 $csvPath

$curvePath = Join-Path $outDir 'curve.txt'
$curve = @('L1-15 多码率客观质量曲线（同一源）', '')
$minP = ($results | Measure-Object -Property PsnrY -Minimum).Minimum
$maxP = ($results | Measure-Object -Property PsnrY -Maximum).Maximum
$minS = ($results | Measure-Object -Property Ssim  -Minimum).Minimum
$maxS = ($results | Measure-Object -Property Ssim  -Maximum).Maximum
$curve += "PSNR(Y) dB  (${minP} ~ ${maxP})"
foreach ($r in $results) { $curve += ("  {0,6}k | {1} {2}" -f $r.Kbps, (Bar $r.PsnrY $minP $maxP), (R4 $r.PsnrY)) }
$curve += ''
$curve += "SSIM       (${minS} ~ ${maxS})"
foreach ($r in $results) { $curve += ("  {0,6}k | {1} {2}" -f $r.Kbps, (Bar $r.Ssim $minS $maxS), (R4 $r.Ssim)) }
$curve | Set-Content -Encoding UTF8 $curvePath
$curve | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

# ---------- 3) 边界：同一文件 ----------
Write-Host "== 3) 边界：两个完全相同的文件 ==" -ForegroundColor Cyan
$same = Result-Of (Run-Quality $refYuv $refYuv $W $H)
Assert-True ($same.identical -eq $true) "同文件比较应判定 identical=true"
Assert-True ([math]::Abs([double]$same.ssim - 1.0) -lt 1e-6) "同文件 SSIM 应≈1.0，实际 $($same.ssim)"
Assert-True ($null -eq $same.psnr_y) "同文件 PSNR 应为无穷大（JSON 中为 null）"
Write-Host "  同文件：SSIM=$($same.ssim) PSNR=inf(=null) 判定 identical=true" -ForegroundColor Gray

# ---------- 4) 踩坑：分辨率 / 像素格式不一致 ----------
Write-Host "== 4) 踩坑：分辨率不一致、像素格式不统一 ==" -ForegroundColor Cyan
$bigMp4 = $results[0].Mp4
$smallMp4 = Join-Path $outDir 'small_320x180.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','yuv420p','-s',"${W}x${H}",'-r',"$FPS",'-i',$refYuv,
     '-vf','scale=320:180','-pix_fmt','yuv420p','-c:v','libx264','-an', $smallMp4) | Out-Null
$rSize = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-i',$bigMp4,'-i',$smallMp4,'-lavfi','[0:v][1:v]psnr','-f','null','-')
Assert-True ($rSize.Code -ne 0) "分辨率不一致时 psnr 滤镜应报错退出（实际 exit=$($rSize.Code)）"
$msgSize = ($rSize.Output -split "`r?`n") | Where-Object { $_ -match 'same size|Width and height|must be' } | Select-Object -First 1
Write-Host "  分辨率不一致 -> ffmpeg: $msgSize" -ForegroundColor Yellow

# 4b) 像素格式不统一：quality_tools 只按 YUV420P 解释字节，
#     444P 的单帧字节数是 420P 的 2 倍，按 420P 解析会把帧数读成 2 倍 -> 帧数不一致告警
$fmt444Yuv = Join-Path $outDir 'fmt_444p.yuv'
Ff @('-hide_banner','-loglevel','error','-y','-f','lavfi',
     '-i', "testsrc2=size=${W}x${H}:rate=${FPS}:duration=$DUR",'-pix_fmt','yuv444p','-f','rawvideo', $fmt444Yuv) | Out-Null
$rFmt = Invoke-AvNative $QualityTools @($refYuv, $fmt444Yuv, "$W", "$H")
$warn = ($rFmt.Output -split "`r?`n") | Where-Object { $_ -match '帧数不一致' } | Select-Object -First 1
Assert-True ($null -ne $warn) "像素格式不统一时应告警帧数不一致（按 420P 解析 444P 会读到 2 倍帧数）"
Write-Host "  像素格式不统一 -> quality_tools: $warn" -ForegroundColor Yellow

# 4c) 反向印证：ffmpeg psnr 遇 420P/444P 混用会静默自动转换（不报错），更隐蔽
$ref420Mp4 = Join-Path $outDir 'ref_420p.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','yuv420p','-s',"${W}x${H}",'-r',"$FPS",'-i',$refYuv,
     '-c:v','libx264','-an', $ref420Mp4) | Out-Null
$fmt444Mp4 = Join-Path $outDir 'fmt_444p.mp4'
Ff @('-hide_banner','-loglevel','error','-y','-f','lavfi',
     '-i', "testsrc2=size=${W}x${H}:rate=${FPS}:duration=$DUR",'-pix_fmt','yuv444p','-c:v','libx264','-an', $fmt444Mp4) | Out-Null
$rAuto = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-i',$ref420Mp4,'-i',$fmt444Mp4,'-lavfi','[0:v][1:v]psnr','-f','null','-')
Write-Host "  对照：ffmpeg psnr 遇 420P vs 444P 混用 exit=$($rAuto.Code)（会自动插入格式转换，不报错，属隐蔽陷阱）" -ForegroundColor Yellow

# ---------- 汇总 ----------
Write-Host ""
Write-Host "全部校验通过 ✔" -ForegroundColor Green
Write-Host "产物目录：$outDir" -ForegroundColor Gray
Write-Host "  metrics.csv / curve.txt / frame_*.png（各码率首帧，供主观对照）" -ForegroundColor Gray
