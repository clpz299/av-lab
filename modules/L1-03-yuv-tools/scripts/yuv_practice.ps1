# yuv_practice.ps1 —— L1-03 RGB/YUV 像素数据处理端到端实验
#
# 链路：ffmpeg 自产测试素材 -> yuv_tools 各子命令处理 -> 断言产物大小与关键像素值
# 用法：powershell -NoProfile -File scripts\yuv_practice.ps1 <yuv_tools.exe 路径>
#       （CTest 会通过 $<TARGET_FILE:yuv_tools> 自动传入；手工运行可省略，脚本会去 build/ 下找）

param([string]$YuvTools)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-03-yuv-tools'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $YuvTools) {
    $cand = Get-ChildItem -Path (Join-Path $repoRoot 'build') -Recurse -Filter 'yuv_tools.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cand) { throw "未找到 yuv_tools.exe，请先构建或显式传入路径" }
    $YuvTools = $cand.FullName
}
if (-not (Test-Path $YuvTools)) { throw "yuv_tools 不存在: $YuvTools" }

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function SizeOf([string]$p) { (Get-Item $p).Length }
function Run-Tool([string[]]$ToolArgs) {
    Write-Host ("  $ yuv_tools " + ($ToolArgs -join ' ')) -ForegroundColor DarkGray
    $r = Invoke-AvNative $YuvTools $ToolArgs
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "yuv_tools 执行失败 (exit=$($r.Code)): $($ToolArgs -join ' ')" }
    if ($r.Output) { Write-Host "    $($r.Output -replace "`r?`n", "`n    ")" }
    return $r.Output
}

# ---------- 0) ffmpeg 自产素材 ----------
Write-Host "== 0) 生成测试素材 ==" -ForegroundColor Cyan
$W = 256; $H = 256
$src420 = Join-Path $outDir 'src_256x256_420p.yuv'
$src420b = Join-Path $outDir 'src_b_256x256_420p.yuv'
$src444 = Join-Path $outDir 'src_256x256_444p.yuv'
$srcRgb = Join-Path $outDir 'src_256x256.rgb'

$r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=256x256:rate=1','-frames:v','1','-pix_fmt','yuv420p','-f','rawvideo', $src420)
if ($r.Code -ne 0) { throw "生成 420p 素材失败: $($r.Output)" }
$r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','smptebars=size=256x256','-frames:v','1','-pix_fmt','yuv420p','-f','rawvideo', $src420b)
if ($r.Code -ne 0) { throw "生成对照素材失败: $($r.Output)" }
$r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=256x256:rate=1','-frames:v','1','-pix_fmt','yuv444p','-f','rawvideo', $src444)
if ($r.Code -ne 0) { throw "生成 444p 素材失败: $($r.Output)" }
$r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=256x256:rate=1','-frames:v','1','-pix_fmt','rgb24','-f','rawvideo', $srcRgb)
if ($r.Code -ne 0) { throw "生成 RGB24 素材失败: $($r.Output)" }

$Y420 = $W * $H;               # 65536
$UV420 = $W * $H / 4;          # 16384
$FRAME420 = $W * $H * 3 / 2;   # 98304
$FRAME444 = $W * $H * 3;       # 196608
Assert-True ((SizeOf $src420) -eq $FRAME420) "src 420p 大小应为 $FRAME420"
Assert-True ((SizeOf $src444) -eq $FRAME444) "src 444p 大小应为 $FRAME444"
Assert-True ((SizeOf $srcRgb) -eq $FRAME444) "src rgb24 大小应为 $FRAME444"

# ---------- 1) split420 / split444 ----------
Write-Host "== 1) 分量分离 ==" -ForegroundColor Cyan
Run-Tool @('split420', $src420, "$W", "$H", '1', $outDir) | Out-Null
Assert-True ((SizeOf (Join-Path $outDir 'output_420_y.y')) -eq $Y420) "split420 Y 大小应为 $Y420"
Assert-True ((SizeOf (Join-Path $outDir 'output_420_u.y')) -eq $UV420) "split420 U 大小应为 $UV420"
Assert-True ((SizeOf (Join-Path $outDir 'output_420_v.y')) -eq $UV420) "split420 V 大小应为 $UV420"

Run-Tool @('split444', $src444, "$W", "$H", '1', $outDir) | Out-Null
Assert-True ((SizeOf (Join-Path $outDir 'output_444_y.y')) -eq $Y420) "split444 Y 大小应为 $Y420"
Assert-True ((SizeOf (Join-Path $outDir 'output_444_u.y')) -eq $Y420) "split444 U 大小应为 $Y420"
Assert-True ((SizeOf (Join-Path $outDir 'output_444_v.y')) -eq $Y420) "split444 V 大小应为 $Y420"

# ---------- 2) gray420：U/V 应全部为 128 ----------
Write-Host "== 2) 灰度化 (U/V=128) ==" -ForegroundColor Cyan
$gray = Join-Path $outDir 'gray_420p.yuv'
Run-Tool @('gray420', $src420, "$W", "$H", '1', $gray) | Out-Null
Assert-True ((SizeOf $gray) -eq $FRAME420) "gray 大小应为 $FRAME420"
$gb = [System.IO.File]::ReadAllBytes($gray)
$bad = 0
for ($i = $Y420; $i -lt $FRAME420; $i++) { if ($gb[$i] -ne 128) { $bad++ } }
Assert-True ($bad -eq 0) "gray 的 U/V 区应全为 128（不匹配 $bad 字节）"

# ---------- 3) half420：Y 应等于原值/2 ----------
Write-Host "== 3) 亮度减半 ==" -ForegroundColor Cyan
$half = Join-Path $outDir 'half_420p.yuv'
Run-Tool @('half420', $src420, "$W", "$H", '1', $half) | Out-Null
$ob = [System.IO.File]::ReadAllBytes($src420)
$hb = [System.IO.File]::ReadAllBytes($half)
Assert-True ((SizeOf $half) -eq $FRAME420) "half 大小应为 $FRAME420"
$bad = 0
for ($i = 0; $i -lt $Y420; $i++) { if ($hb[$i] -ne [math]::Floor($ob[$i] / 2)) { $bad++ } }
Assert-True ($bad -eq 0) "half 的 Y 应等于原值整除 2（不匹配 $bad 字节）"
# U/V 不应被改动
$bad = 0
for ($i = $Y420; $i -lt $FRAME420; $i++) { if ($hb[$i] -ne $ob[$i]) { $bad++ } }
Assert-True ($bad -eq 0) "half 不应改动 U/V（不匹配 $bad 字节）"

# ---------- 4) border420 ----------
Write-Host "== 4) 加边框 ==" -ForegroundColor Cyan
$bd = Join-Path $outDir 'border_420p.yuv'
Run-Tool @('border420', $src420, "$W", "$H", '16', '1', $bd) | Out-Null
$bb = [System.IO.File]::ReadAllBytes($bd)
Assert-True ((SizeOf $bd) -eq $FRAME420) "border 大小应为 $FRAME420"
Assert-True ($bb[0] -eq 255) "左上角应为 255"
Assert-True ($bb[($H-1)*$W + ($W-1)] -eq 255) "右下角应为 255"
# 内部像素保持不变
$idx = 100 * $W + 100
Assert-True ($bb[$idx] -eq $ob[$idx]) "内部像素 (100,100) 不应被改动"

# ---------- 5) graybar420 ----------
Write-Host "== 5) 灰阶测试图 ==" -ForegroundColor Cyan
$gw = 640; $gh = 360; $barnum = 10; $barw = $gw / $barnum
$graybar = Join-Path $outDir 'graybar_640x360_420p.yuv'
$out = Run-Tool @('graybar420', "$gw", "$gh", '0', '255', "$barnum", $graybar)
Assert-True ((SizeOf $graybar) -eq ($gw * $gh * 3 / 2)) "graybar 大小应为 $($gw*$gh*3/2)"
$cb = [System.IO.File]::ReadAllBytes($graybar)
Assert-True ($cb[0] -eq 0) "灰阶第 0 条应为 0"
Assert-True ($cb[5 * $barw] -eq 141) "灰阶第 5 条应为 141（实际 $($cb[5*$barw])）"
$bad = 0
for ($i = $gw * $gh; $i -lt $cb.Length; $i++) { if ($cb[$i] -ne 128) { $bad++ } }
Assert-True ($bad -eq 0) "graybar 的 U/V 应全为 128（不匹配 $bad 字节）"

# ---------- 6) psnr420 ----------
Write-Host "== 6) PSNR ==" -ForegroundColor Cyan
$o1 = Run-Tool @('psnr420', $src420, $src420, "$W", "$H", '1')
Assert-True ($o1 -match 'inf') "自比对应输出 inf（实际: $o1）"
$o2 = Run-Tool @('psnr420', $src420, $src420b, "$W", "$H", '1')
$val = [double]($o2 -replace "`r", '' -replace "`n", '')
Assert-True ($val -gt 0 -and $val -le 100) "不同图像 PSNR 应为 (0,100]（实际: $val）"

# ---------- 7) splitrgb24 ----------
Write-Host "== 7) RGB24 分离 ==" -ForegroundColor Cyan
Run-Tool @('splitrgb24', $srcRgb, "$W", "$H", '1', $outDir) | Out-Null
foreach ($c in 'r','g','b') {
    Assert-True ((SizeOf (Join-Path $outDir "output_$c.y")) -eq $Y420) "splitrgb24 $c 大小应为 $Y420"
}

# ---------- 8) rgb24tobmp ----------
Write-Host "== 8) RGB24 -> BMP ==" -ForegroundColor Cyan
$bmp = Join-Path $outDir 'out.bmp'
Run-Tool @('rgb24tobmp', $srcRgb, "$W", "$H", $bmp) | Out-Null
$hdr = [System.IO.File]::ReadAllBytes($bmp)[0..1] | ForEach-Object { [char]$_ }
Assert-True (($hdr -join '') -eq 'BM') "BMP 魔数应为 BM"
$probe = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','stream=width,height','-of','csv=p=0', $bmp)
Assert-True ($probe.Code -eq 0) "ffprobe 无法解析 BMP: $($probe.Output)"
Assert-True ($probe.Output -match "$W" -and $probe.Output -match "$H") "BMP 分辨率应为 $W x $H（实际: $($probe.Output)）"

# ---------- 9) rgb24toyuv ----------
Write-Host "== 9) RGB24 -> YUV420P ==" -ForegroundColor Cyan
$yuvOut = Join-Path $outDir 'from_rgb_420p.yuv'
Run-Tool @('rgb24toyuv', $srcRgb, "$W", "$H", '1', $yuvOut) | Out-Null
Assert-True ((SizeOf $yuvOut) -eq $FRAME420) "rgb24toyuv 大小应为 $FRAME420"

# ---------- 10) colorbar24 ----------
Write-Host "== 10) 彩条生成 ==" -ForegroundColor Cyan
$cw = 640; $ch = 360; $cbarw = $cw / 8
$cbar = Join-Path $outDir 'colorbar_640x360.rgb'
Run-Tool @('colorbar24', "$cw", "$ch", $cbar) | Out-Null
Assert-True ((SizeOf $cbar) -eq ($cw * $ch * 3)) "colorbar 大小应为 $($cw*$ch*3)"
$rc = [System.IO.File]::ReadAllBytes($cbar)
# 第 0 条=白，第 5 条=红，第 7 条=黑
Assert-True ($rc[0] -eq 255 -and $rc[1] -eq 255 -and $rc[2] -eq 255) "彩条第 0 条应为白"
$off5 = (5 * $cbarw) * 3
Assert-True ($rc[$off5] -eq 255 -and $rc[$off5+1] -eq 0 -and $rc[$off5+2] -eq 0) "彩条第 5 条应为红"
$off7 = (7 * $cbarw) * 3
Assert-True ($rc[$off7] -eq 0 -and $rc[$off7+1] -eq 0 -and $rc[$off7+2] -eq 0) "彩条第 7 条应为黑"

Write-Host "yuv_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
