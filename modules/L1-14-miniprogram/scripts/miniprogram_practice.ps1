# miniprogram_practice.ps1 —— L1-14 微信小程序音视频能力初探
#
# 背景：微信小程序 live-pusher / live-player 的真正推拉流需要
#       「真实 appid + 后台类目权限 + 真机」，无法在本机 CI 中自动跑通。
#       因此本脚本对「小程序 demo 工程」做可自动化的验证：
#         1) 工程结构完整（必需文件齐全）
#         2) 全部 JSON 配置合法且关键字段存在
#         3) 页面组件契约（live-pusher / live-player 必需属性与事件绑定）
#         4) 推拉流地址协议契约（push 必须 rtmp://；play 支持 rtmp/http/https）
#       并如实输出「必须人工在真机验证」的边界。
# 用法：powershell -NoProfile -File scripts\miniprogram_practice.ps1

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$projDir  = (Resolve-Path (Join-Path $PSScriptRoot '..\miniprogram')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-14-miniprogram'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$script:checks = New-Object System.Collections.ArrayList
function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
    [void]$script:checks.Add($msg)
    Write-Host "  [OK] $msg" -ForegroundColor Green
}
function Read-Text([string]$p) { return (Get-Content -Raw -Encoding UTF8 $p) }
function Read-Json([string]$p) { return (Read-Text $p | ConvertFrom-Json) }
function Get-TagAttrs([string]$wxml, [string]$tag) {
    $m = [regex]::Match($wxml, "<$tag\b(?<attrs>[^>]*)>")
    Assert-True $m.Success "wxml 中存在 <$tag> 组件"
    return $m.Groups['attrs'].Value
}
function Get-Attr([string]$attrs, [string]$name) {
    $m = [regex]::Match($attrs, "$name\s*=\s*""(?<v>[^""]*)""")
    if ($m.Success) { return $m.Groups['v'].Value }
    return $null
}

# ---------- 1) 工程结构 ----------
Write-Host "== 1) 工程结构：必需文件 ==" -ForegroundColor Cyan
$required = @(
    'app.json', 'app.js', 'app.wxss', 'sitemap.json', 'project.config.json', 'config.js',
    'pages/live/live.json', 'pages/live/live.js', 'pages/live/live.wxml', 'pages/live/live.wxss'
)
foreach ($rel in $required) {
    $p = Join-Path $projDir ($rel -replace '/', '\')
    Assert-True (Test-Path $p) "存在文件 $rel"
}

# ---------- 2) JSON 配置合法性 ----------
Write-Host "== 2) JSON 配置合法性与关键字段 ==" -ForegroundColor Cyan
$appJson = Read-Json (Join-Path $projDir 'app.json')
$projCfg = Read-Json (Join-Path $projDir 'project.config.json')
$sitemap = Read-Json (Join-Path $projDir 'sitemap.json')
$pageCfg = Read-Json (Join-Path $projDir 'pages\live\live.json')

Assert-True ($appJson.pages -contains 'pages/live/live') "app.json 已注册页面 pages/live/live"
Assert-True ($projCfg.compileType -eq 'miniprogram') "project.config.json compileType=miniprogram"
Assert-True ($null -ne $projCfg.setting) "project.config.json 含 setting 配置"
Assert-True ($null -ne $projCfg.setting.urlCheck) "project.config.json 含 setting.urlCheck（域名校验开关）"
Assert-True ($sitemap.rules.Count -ge 1) "sitemap.json 含 rules"
Assert-True ($null -ne $pageCfg.usingComponents) "页面 live.json 含 usingComponents"

# ---------- 3) 页面组件契约 ----------
Write-Host "== 3) 页面组件契约（live-pusher / live-player）==" -ForegroundColor Cyan
$wxml = Read-Text (Join-Path $projDir 'pages\live\live.wxml')
$pushAttrs = Get-TagAttrs $wxml 'live-pusher'
$playAttrs = Get-TagAttrs $wxml 'live-player'

foreach ($a in @('url', 'mode', 'bindstatechange', 'binderror')) {
    Assert-True ($null -ne (Get-Attr $pushAttrs $a)) "live-pusher 含属性 $a"
}
foreach ($a in @('src', 'mode', 'autoplay', 'bindstatechange', 'binderror')) {
    Assert-True ($null -ne (Get-Attr $playAttrs $a)) "live-player 含属性 $a"
}

Assert-True ((Get-Attr $pushAttrs 'url') -eq '{{pushUrl}}') "live-pusher.url 绑定 {{pushUrl}}"
Assert-True ((Get-Attr $playAttrs 'src') -eq '{{playUrl}}') "live-player.src 绑定 {{playUrl}}"

# 组件 mode 枚举：live-pusher 为 SD/HD/FHD/RTC；live-player 为 live/RTC（两者不同）
$pushMode = Get-Attr $pushAttrs 'mode'
$playMode = Get-Attr $playAttrs 'mode'
Assert-True (@('SD', 'HD', 'FHD', 'RTC') -contains $pushMode) "live-pusher mode 取值合法（$pushMode）"
Assert-True (@('live', 'RTC') -contains $playMode) "live-player mode 取值合法（$playMode）"

# 事件处理函数必须在页面 js 中实现，否则组件回调触发时运行时报错
$pageJs = Read-Text (Join-Path $projDir 'pages\live\live.js')
foreach ($fn in @('onPushStateChange', 'onPushError', 'onPlayStateChange', 'onPlayError')) {
    Assert-True ($pageJs -match "$fn\s*\(") "live.js 已实现事件处理函数 $fn"
}

# ---------- 4) 推拉流地址协议契约 ----------
Write-Host "== 4) 推拉流地址协议契约 ==" -ForegroundColor Cyan
$cfgText = Read-Text (Join-Path $projDir 'config.js')
$pushUrl = ([regex]::Match($cfgText, "pushUrl:\s*'(?<v>[^']*)'")).Groups['v'].Value
$playUrl = ([regex]::Match($cfgText, "playUrl:\s*'(?<v>[^']*)'")).Groups['v'].Value
Assert-True ($pushUrl -ne '') "config.js 中解析出 pushUrl"
Assert-True ($playUrl -ne '') "config.js 中解析出 playUrl"
Assert-True ($pushUrl -match '^rtmp://') "live-pusher 推流地址必须为 RTMP（$pushUrl）"
Assert-True ($playUrl -match '^(rtmp|http|https)://') "live-player 拉流地址协议在 rtmp/http/https 内（$playUrl）"

# ---------- 报告 ----------
$manualSteps = @(
    '在微信公众平台注册小程序并获取真实 appid（测试号 touristappid 仅供开发者工具预览）',
    '后台「设置-基本设置-服务类目」选择「工具 > 视频客服」以开通 live-pusher/live-player 接口权限',
    '后台「开发设置-服务器域名」将推/拉流域名加入白名单，否则会被域名校验拦截（urlCheck）',
    '用真实可用的 RTMP 地址替换 config.js 中的占位地址',
    '真机（非开发者工具）预览：扫码进入，完成一路推流 + 一路播放'
)
$report = [pscustomobject]@{
    module      = 'L1-14-miniprogram'
    generatedAt = (Get-Date).ToString('s')
    checks      = $script:checks.Count
    pushUrl     = $pushUrl
    playUrl     = $playUrl
    manualSteps = $manualSteps
}
$reportPath = Join-Path $outDir 'contract_report.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $reportPath

Write-Host ""
Write-Host "自动化校验通过：$($script:checks.Count) 项（工程结构 + 配置契约）" -ForegroundColor Green
Write-Host "契约报告：$reportPath" -ForegroundColor Gray
Write-Host "以下步骤必须人工在真机完成（无法自动化）：" -ForegroundColor Yellow
foreach ($s in $manualSteps) { Write-Host "  - $s" -ForegroundColor Yellow }
