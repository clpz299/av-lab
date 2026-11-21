# pcm_practice.ps1 —— L1-04 PCM 音频采样数据处理端到端实验
#
# 链路：ffmpeg 自产 PCM16LE 素材 -> pcm_tools 各子命令 -> 断言产物大小与样值
# 用法：powershell -NoProfile -File scripts\pcm_practice.ps1 <pcm_tools.exe 路径>

param([string]$PcmTools)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-04-pcm-tools'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $PcmTools) {
    $cand = Get-ChildItem -Path (Join-Path $repoRoot 'build') -Recurse -Filter 'pcm_tools.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cand) { throw "未找到 pcm_tools.exe，请先构建或显式传入路径" }
    $PcmTools = $cand.FullName
}
if (-not (Test-Path $PcmTools)) { throw "pcm_tools 不存在: $PcmTools" }

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}
function SizeOf([string]$p) { (Get-Item $p).Length }
function Run-Tool([string[]]$ToolArgs) {
    Write-Host ("  $ pcm_tools " + ($ToolArgs -join ' ')) -ForegroundColor DarkGray
    $r = Invoke-AvNative $PcmTools $ToolArgs
    if ($r.Code -ne 0) { Write-Host $r.Output; throw "pcm_tools 执行失败 (exit=$($r.Code)): $($ToolArgs -join ' ')" }
    if ($r.Output) { Write-Host "    $($r.Output -replace "`r?`n", "`n    ")" }
    return $r.Output
}
# 按 C 的整除规则（向零取整）计算 short/2
function TruncDiv2([int]$x) { if ($x -ge 0) { [int][math]::Floor($x / 2) } else { -[int][math]::Floor((-$x) / 2) } }
# 有符号右移 8 位 = floor(x/256)
function Shr8([int]$x) { [int][math]::Floor($x / 256) }

# ---------- 0) ffmpeg 自产素材 ----------
Write-Host "== 0) 生成 PCM16LE 素材 ==" -ForegroundColor Cyan
$sr = 44100; $dur = 0.2   # 秒
$stereo = Join-Path $outDir 'stereo_44100_s16le.pcm'
$mono   = Join-Path $outDir 'mono_44100_s16le.pcm'
$r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i',"sine=frequency=440:sample_rate=$sr`:duration=$dur",'-ac','2','-f','s16le', $stereo)
if ($r.Code -ne 0) { throw "生成双声道素材失败: $($r.Output)" }
$r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i',"sine=frequency=330:sample_rate=$sr`:duration=$dur",'-ac','1','-f','s16le', $mono)
if ($r.Code -ne 0) { throw "生成单声道素材失败: $($r.Output)" }

$N = [int]($sr * $dur)                 # 帧数 8820
$sb = [System.IO.File]::ReadAllBytes($stereo)
Assert-True ($sb.Length -eq $N * 4) "双声道素材大小应为 $($N*4)（实际 $($sb.Length)）"

# ---------- 1) split_lr ----------
Write-Host "== 1) 分离左右声道 ==" -ForegroundColor Cyan
$l = Join-Path $outDir 'out_l.pcm'; $rr = Join-Path $outDir 'out_r.pcm'
Run-Tool @('split_lr', $stereo, $l, $rr) | Out-Null
Assert-True ((SizeOf $l) -eq $N * 2) "左声道大小应为 $($N*2)"
Assert-True ((SizeOf $rr) -eq $N * 2) "右声道大小应为 $($N*2)"
$lb = [System.IO.File]::ReadAllBytes($l)
$rb = [System.IO.File]::ReadAllBytes($rr)
$bad = 0
for ($i = 0; $i -lt $N; $i++) {
    if ($lb[2*$i] -ne $sb[4*$i] -or $lb[2*$i+1] -ne $sb[4*$i+1]) { $bad++ }
    if ($rb[2*$i] -ne $sb[4*$i+2] -or $rb[2*$i+1] -ne $sb[4*$i+3]) { $bad++ }
}
Assert-True ($bad -eq 0) "左右声道应与原交错数据一一对应（不匹配 $bad 字节）"

# ---------- 2) half_left ----------
Write-Host "== 2) 左声道音量减半 ==" -ForegroundColor Cyan
$half = Join-Path $outDir 'out_halfleft.pcm'
Run-Tool @('half_left', $stereo, $half) | Out-Null
Assert-True ((SizeOf $half) -eq $N * 4) "half_left 大小应保持不变 $($N*4)"
$hb = [System.IO.File]::ReadAllBytes($half)
$bad = 0
for ($i = 0; $i -lt $N; $i++) {
    $oL = [BitConverter]::ToInt16($sb, 4*$i)
    $oR = [BitConverter]::ToInt16($sb, 4*$i+2)
    $nL = [BitConverter]::ToInt16($hb, 4*$i)
    $nR = [BitConverter]::ToInt16($hb, 4*$i+2)
    if ($nL -ne (TruncDiv2 $oL)) { $bad++ }
    if ($nR -ne $oR) { $bad++ }
}
Assert-True ($bad -eq 0) "左声道应整除 2、右声道不变（不匹配 $bad 样值）"

# ---------- 3) doublespeed ----------
Write-Host "== 3) 速度翻倍（抽奇数帧）==" -ForegroundColor Cyan
$dbl = Join-Path $outDir 'out_doublespeed.pcm'
Run-Tool @('doublespeed', $stereo, $dbl) | Out-Null
$kept = [math]::Floor($N / 2)
Assert-True ((SizeOf $dbl) -eq $kept * 4) "doublespeed 大小应为 $($kept*4)"
$db = [System.IO.File]::ReadAllBytes($dbl)
# 第 0 个保留帧应等于源的第 1 帧（cnt=1）
Assert-True ([BitConverter]::ToInt16($db,0) -eq [BitConverter]::ToInt16($sb,4)) "首帧应来自源第 1 帧(L)"
Assert-True ([BitConverter]::ToInt16($db,2) -eq [BitConverter]::ToInt16($sb,6)) "首帧应来自源第 1 帧(R)"

# ---------- 4) to_pcm8 ----------
Write-Host "== 4) PCM16LE -> PCM8 ==" -ForegroundColor Cyan
$p8 = Join-Path $outDir 'out_8.pcm'
Run-Tool @('to_pcm8', $stereo, $p8) | Out-Null
Assert-True ((SizeOf $p8) -eq $N * 2) "PCM8 大小应为 $($N*2)"
$p8b = [System.IO.File]::ReadAllBytes($p8)
$bad = 0
for ($i = 0; $i -lt $N; $i++) {
    $eL = (Shr8 ([BitConverter]::ToInt16($sb, 4*$i)))   + 128
    $eR = (Shr8 ([BitConverter]::ToInt16($sb, 4*$i+2))) + 128
    if ($p8b[2*$i] -ne $eL -or $p8b[2*$i+1] -ne $eR) { $bad++ }
}
Assert-True ($bad -eq 0) "PCM8 值应为 floor(s16/256)+128（不匹配 $bad 样值）"

# ---------- 5) cut_mono ----------
Write-Host "== 5) 单声道截取 ==" -ForegroundColor Cyan
$mb = [System.IO.File]::ReadAllBytes($mono)
$mN = $mb.Length / 2
$start = 100; $durN = 200
$cutPcm = Join-Path $outDir 'out_cut.pcm'; $cutTxt = Join-Path $outDir 'out_cut.txt'
Run-Tool @('cut_mono', $mono, "$start", "$durN", $cutPcm, $cutTxt) | Out-Null
Assert-True ((SizeOf $cutPcm) -eq ($durN * 2)) "截取长度应为 $($durN*2)"
$cutb = [System.IO.File]::ReadAllBytes($cutPcm)
# 条件 cnt>start && cnt<=start+dur -> 源索引 101..300
Assert-True ([BitConverter]::ToInt16($cutb,0) -eq [BitConverter]::ToInt16($mb, 2*($start+1))) "首个样值应对应源索引 $($start+1)"
Assert-True ([BitConverter]::ToInt16($cutb, 2*($durN-1)) -eq [BitConverter]::ToInt16($mb, 2*($start+$durN))) "末个样值应对应源索引 $($start+$durN)"
Assert-True ((SizeOf $cutTxt) -gt 0) "样值清单不应为空"

# ---------- 6) to_wave ----------
Write-Host "== 6) 封装为 WAVE ==" -ForegroundColor Cyan
$wav = Join-Path $outDir 'out_stereo.wav'
Run-Tool @('to_wave', $stereo, '2', "$sr", $wav) | Out-Null
Assert-True ((SizeOf $wav) -eq (44 + $N * 4)) "WAV 大小应为 44 + $($N*4)"
$probe = Invoke-AvNative $AvTool.Ffprobe @('-v','error','-show_entries','stream=channels,sample_rate','-of','csv=p=0', $wav)
Assert-True ($probe.Code -eq 0) "ffprobe 无法解析 WAV: $($probe.Output)"
Assert-True ($probe.Output -match '44100') "WAV 采样率应为 44100（实际: $($probe.Output)）"
Assert-True ($probe.Output -match '2') "WAV 应为 2 声道（实际: $($probe.Output)）"
# 往返验证：ffmpeg 解码 WAV -> raw s16le，应与原始 PCM 完全一致
$rt = Join-Path $outDir 'roundtrip.raw'
$r = Invoke-AvNative $AvTool.Ffmpeg @('-hide_banner','-loglevel','error','-y','-i', $wav, '-f','s16le','-ac','2', $rt)
if ($r.Code -ne 0) { throw "WAV 解码失败: $($r.Output)" }
$rtb = [System.IO.File]::ReadAllBytes($rt)
Assert-True ($rtb.Length -eq $sb.Length) "往返 PCM 长度应一致（$($rtb.Length) vs $($sb.Length)）"
Assert-True ([System.Linq.Enumerable]::SequenceEqual([byte[]]$rtb, [byte[]]$sb)) "往返 PCM 内容应与原始一致"

Write-Host "pcm_practice PASS" -ForegroundColor Green
Write-Host "产物目录: $outDir"
exit 0
