# env_check.ps1 —— 校验工具链三件套版本
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\avtool.ps1')

$failed = @()

function Check-One([string]$label, [string]$exe, [string]$verArg) {
    if (-not $exe -or -not (Test-Path $exe)) {
        Write-Host "[FAIL] $label 未找到" -ForegroundColor Red
        return $null
    }
    $line = (& $exe $verArg 2>&1 | Select-Object -First 1)
    Write-Host ("[ OK ] {0,-8}: {1}" -f $label, $line) -ForegroundColor Green
    return $line
}

$gcc    = Check-One 'gcc'    $AvTool.Gcc    '--version'
$gpp    = Check-One 'g++'    $AvTool.Gpp    '--version'
$cmake  = Check-One 'cmake'  $AvTool.Cmake  '--version'
$ffmpeg = Check-One 'ffmpeg' $AvTool.Ffmpeg '-version'
$ffprobe= Check-One 'ffprobe' $AvTool.Ffprobe '-version'

foreach ($p in @($gcc,$gpp,$cmake,$ffmpeg,$ffprobe)) { if (-not $p) { $failed += $p } }

if ($failed.Count -gt 0) {
    Write-Host "env_check FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "env_check PASS" -ForegroundColor Green
exit 0
