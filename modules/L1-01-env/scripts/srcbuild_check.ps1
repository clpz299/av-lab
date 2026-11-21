# srcbuild_check.ps1 —— L1-01 扩展：从零编译 FFmpeg 的「脚本契约 + 本机环境」自检
#
# 本脚本不做真正的编译（那需要 MSYS2/WSL，耗时且依赖网络），而是：
#   1) 校验 build_ffmpeg.sh / build_ffmpeg.bat 两个交付脚本存在且内容契约正确；
#   2) 对 build_ffmpeg.sh 做 bash 语法检查（bash -n，若能找到 bash）；
#   3) 探测本机是否具备编译前提（gcc/make/git/curl/nasm/bash/MSYS2/WSL），如实报告。
# 真正的编译步骤见 README「实验步骤 B」，需人工在有 MSYS2 的机器上执行。
#
# 用法：powershell -NoProfile -File scripts\srcbuild_check.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$moduleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$srcbuildDir = Join-Path $moduleRoot 'srcbuild'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir = Join-Path $repoRoot 'build\_artifacts\L1-01-env'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$script:checks = @()
function Check([string]$name, [bool]$ok, [string]$detail) {
    $script:checks += [pscustomobject]@{ name = $name; ok = $ok; detail = $detail }
    $tag = if ($ok) { '[ OK ]' } else { '[FAIL]' }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("{0} {1} —— {2}" -f $tag, $name, $detail) -ForegroundColor $color
}
function HasToken([string]$text, [string]$pattern) {
    return [bool]([regex]::IsMatch($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
}

Write-Host "== A) 交付脚本契约校验 ==" -ForegroundColor Cyan
$shPath = Join-Path $srcbuildDir 'build_ffmpeg.sh'
$batPath = Join-Path $srcbuildDir 'build_ffmpeg.bat'

$shExists = Test-Path $shPath
Check 'build_ffmpeg.sh 存在' $shExists $shPath
$batExists = Test-Path $batPath
Check 'build_ffmpeg.bat 存在' $batExists $batPath

if (-not $shExists) { throw "缺少 build_ffmpeg.sh" }
if (-not $batExists) { throw "缺少 build_ffmpeg.bat" }

$sh = Get-Content -Raw $shPath
$bat = Get-Content -Raw $batPath

Check 'sh 行数充足(>40)' (($sh -split "`n").Count -gt 40) ("{0} 行" -f ($sh -split "`n").Count)
Check 'sh 含 --enable-gpl' (HasToken $sh '--enable-gpl') 'GPL 许可（libx264 要求）'
Check 'sh 含 --enable-libx264' (HasToken $sh '--enable-libx264') '链接 H.264 外部编码器'
Check 'sh 含 x264 源码获取' (HasToken $sh 'x264\.git|git clone[^\n]*x264') '先建依赖再建 FFmpeg'
Check 'sh 含 --disable-x86asm 降级' (HasToken $sh '--disable-x86asm') 'nasm 缺失时的降级路径'
Check 'sh 含 nasm 探测' (HasToken $sh 'command -v nasm') '运行前探测汇编器'
Check 'sh 含 --disable-doc 裁剪' (HasToken $sh '--disable-doc') '编译选项裁剪'
Check 'sh 含 make install' (HasToken $sh 'make install') '安装产物'
Check 'sh 使用 set -euo pipefail' (HasToken $sh 'set -euo pipefail') '出错即停，避免带病继续'
Check 'sh 含 -jobs 并行参数' (HasToken $sh 'make -j') '并行编译'

Check 'bat 定位 bash.exe' (HasToken $bat 'bash\.exe') '必须经 POSIX shell'
Check 'bat 引用 MSYS2' (HasToken $bat 'msys2|msys64') 'Windows 上的标准编译环境'
Check 'bat 转交 build_ffmpeg.sh' (HasToken $bat 'build_ffmpeg\.sh') '委托给真正的构建脚本'
Check 'bat 设置 MSYSTEM=MINGW64' (HasToken $bat 'MSYSTEM=MINGW64') '保证使用 mingw64 工具链'
Check 'bat 缺失 MSYS2 时给出指引' (HasToken $bat 'pacman') '报错信息含安装命令'

Write-Host "== B) bash 语法检查（bash -n）==" -ForegroundColor Cyan
function Find-Bash {
    $c = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    if ($AvTool.Gcc) {
        $cand = Join-Path (Split-Path -Parent (Split-Path -Parent $AvTool.Gcc)) 'bin\bash.exe'
        if (Test-Path $cand) { return $cand }
    }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        $g = Split-Path -Parent (Split-Path -Parent $git.Source)   # ...\Git\cmd -> ...\Git
        foreach ($p in @((Join-Path $g 'bin\bash.exe'), (Join-Path $g 'usr\bin\bash.exe'))) {
            if (Test-Path $p) { return $p }
        }
    }
    foreach ($p in @("$env:ProgramFiles\Git\bin\bash.exe", 'C:\msys64\usr\bin\bash.exe')) {
        if (Test-Path $p) { return $p }
    }
    return $null
}
$bash = Find-Bash
$bashSyntaxOk = $false
$bashSyntaxDetail = '未找到 bash，跳过语法检查'
if ($bash) {
    $r = Invoke-AvNative $bash @('-n', $shPath)
    $bashSyntaxOk = ($r.Code -eq 0)
    $bashSyntaxDetail = if ($bashSyntaxOk) { "通过（$bash）" } else { "失败: $($r.Output)" }
}
Check 'build_ffmpeg.sh 语法有效' $bashSyntaxOk $bashSyntaxDetail

Write-Host "== C) 本机编译前提探测（信息性，不判定成败）==" -ForegroundColor Cyan
function Probe([string]$name, [string[]]$candidates) {
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        if (Test-Path $c) { return [pscustomobject]@{ name = $name; present = $true; path = $c } }
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return [pscustomobject]@{ name = $name; present = $true; path = $cmd.Source } }
    }
    return [pscustomobject]@{ name = $name; present = $false; path = $null }
}
$probes = @(
    (Probe 'gcc'    @($AvTool.Gcc)),
    (Probe 'make'   @($AvTool.Make)),
    (Probe 'git'    @('git.exe')),
    (Probe 'curl'   @('curl.exe')),
    (Probe 'nasm'   @('nasm.exe')),
    (Probe 'yasm'   @('yasm.exe')),
    (Probe 'bash'   @($bash)),
    (Probe 'msys2'  @('C:\msys64\usr\bin\bash.exe')),
    (Probe 'wsl'    @('wsl.exe'))
)
foreach ($p in $probes) {
    $mark = if ($p.present) { '有' } else { '无' }
    Write-Host ("  {0,-6}: {1}  {2}" -f $p.name, $mark, $(if ($p.path) { $p.path } else { '' })) -ForegroundColor Gray
}

$failed = @($script:checks | Where-Object { -not $_.ok })
$report = [pscustomobject]@{
    module = 'L1-01-srcbuild'
    generatedAt = (Get-Date).ToString('s')
    checks = $script:checks.Count
    passed = ($script:checks.Count - $failed.Count)
    failed = $failed.Count
    bashSyntaxChecked = [bool]$bash
    environment = $probes
    manualHint = '真正的编译需 MSYS2 或 WSL：bash srcbuild/build_ffmpeg.sh'
}
$report | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $outDir 'srcbuild_report.json')

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host ("srcbuild_check FAIL（{0}/{1} 项未通过）" -f $failed.Count, $script:checks.Count) -ForegroundColor Red
    exit 1
}
Write-Host ("srcbuild_check PASS（{0} 项契约校验全通过）" -f $script:checks.Count) -ForegroundColor Green
Write-Host "说明：本机环境探测结果见 srcbuild_report.json；真正编译需 MSYS2/WSL。" -ForegroundColor Gray
exit 0
