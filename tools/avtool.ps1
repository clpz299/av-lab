# avtool.ps1 —— 统一解析本工程使用的工具链路径（gcc/g++/cmake/ffmpeg）
# 用法： . .\tools\avtool.ps1   （点源引入后使用 $AvTool.* 变量）
# 工具链查找顺序：$env:AVTOOLCHAIN -> 仓库同级 .avtoolchain -> 仓库内 .avtoolchain

$ErrorActionPreference = 'Stop'

function Resolve-AvToolchain {
    $candidates = @()
    if ($env:AVTOOLCHAIN) { $candidates += $env:AVTOOLCHAIN }
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $candidates += (Join-Path (Split-Path -Parent $repoRoot) '.avtoolchain')
    $candidates += (Join-Path $repoRoot '.avtoolchain')
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    throw "未找到工具链目录 .avtoolchain；请设置环境变量 AVTOOLCHAIN 或先运行 tools/bootstrap.ps1"
}

$script:tc = Resolve-AvToolchain

function Find-Exe([string]$fileName, [string]$subDir) {
    $base = Join-Path $script:tc $subDir
    if (-not (Test-Path $base)) { return $null }
    return (Get-ChildItem $base -Recurse -Filter $fileName -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName)
}

$AvTool = [pscustomobject]@{
    Root      = $script:tc
    Gcc       = Find-Exe 'gcc.exe'   'w64devkit'
    Gpp       = Find-Exe 'g++.exe'   'w64devkit'
    Make      = Find-Exe 'make.exe'  'w64devkit'
    Cmake     = Find-Exe 'cmake.exe' 'cmake'
    Ctest     = Find-Exe 'ctest.exe' 'cmake'
    Ffmpeg    = Find-Exe 'ffmpeg.exe'  'ffmpeg'
    Ffprobe   = Find-Exe 'ffprobe.exe' 'ffmpeg'
    Ffplay    = Find-Exe 'ffplay.exe'  'ffmpeg'
}

# 把工具链 bin 目录加入当前会话 PATH（gcc 需要能定位自身工具）
$binDirs = @()
foreach ($e in @($AvTool.Gcc, $AvTool.Cmake, $AvTool.Ffmpeg)) {
    if ($e) { $binDirs += (Split-Path -Parent $e) }
}
foreach ($d in ($binDirs | Select-Object -Unique)) {
    if ($env:PATH -notlike "*$d*") { $env:PATH = "$d;$env:PATH" }
}

# 调用原生命令的封装：ffmpeg/ffprobe 等会把日志写到 stderr，
# PS 5.1 在 Stop 模式下会把 stderr 误判为致命错误；这里临时切到 Continue，
# 捕获输出后单独用 $LASTEXITCODE 判定成败，返回 { Code; Output }。
function Invoke-AvNative {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$CliArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out  = & $Exe @CliArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    [pscustomobject]@{ Code = $code; Output = ($out | Out-String).Trim() }
}
