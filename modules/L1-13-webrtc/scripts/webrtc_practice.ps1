# webrtc_practice.ps1 —— L1-13 WebRTC 快速上手：浏览器 1v1 通话实验
#
# 链路：Node 信令服务器(WebSocket) + 浏览器 getUserMedia/RTCPeerConnection
#   1) 信令协议级测试：房间管理 / offer-answer-ICE 中继 / 满员 / 离线（不需要浏览器）
#   2) 端到端通话测试：headless Chromium 开两个标签页，用假摄像头跑通真实 1v1 媒体流
# 用法：powershell -NoProfile -File scripts\webrtc_practice.ps1

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$outDir   = Join-Path $repoRoot 'build\_artifacts\L1-13-webrtc'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Assert-True([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "断言失败: $msg" }
}

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-True ($null -ne $node) "未找到 Node.js；L1-13 的信令服务与测试需要 node 运行时"
Write-Host "node: $($node.Source)"
Write-Host "  版本: $((& $node.Source --version))"

# 调用 node 脚本：node 会往 stderr 写日志，PS 5.1 在 Stop 模式下会误判为致命错误，
# 这里临时降到 Continue 捕获全部输出，用 $LASTEXITCODE 判定成败。
function Invoke-NodeScript([string]$scriptPath) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $lines = @(& $node.Source $scriptPath 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    return [pscustomobject]@{ Code = $code; Lines = $lines }
}

function Get-NodeResult([string[]]$lines) {
    $line = $lines | Where-Object { $_ -like 'RESULT *' } | Select-Object -Last 1
    if (-not $line) { return $null }
    return ($line.Substring('RESULT '.Length) | ConvertFrom-Json)
}

function Show-NodeOutput([string[]]$lines) {
    foreach ($l in ($lines | Where-Object { $_ -notlike 'RESULT *' })) {
        Write-Host "  $l"
    }
}

function Show-Checks($result) {
    foreach ($c in $result.checks) {
        $mark = if ($c.ok) { '[ok]  ' } else { '[FAIL]' }
        $extra = if ($c.detail) { "  -- $($c.detail)" } else { '' }
        Write-Host ("  {0} {1}{2}" -f $mark, $c.name, $extra)
    }
}

# ---------- 1) 信令协议级测试 ----------
Write-Host ''
Write-Host '== 1) 信令服务器协议测试（Node WebSocket 客户端模拟两端）==' -ForegroundColor Cyan
$r1 = Invoke-NodeScript (Join-Path $PSScriptRoot 'signaling_test.js')
$res1 = Get-NodeResult $r1.Lines
if (-not $res1) { Show-NodeOutput $r1.Lines; throw "信令测试未输出 RESULT（exit=$($r1.Code)）" }
Show-NodeOutput $r1.Lines
Show-Checks $res1
Assert-True $res1.ok "信令协议测试存在失败项"
Assert-True ($r1.Code -eq 0) "信令协议测试退出码应为 0（实际 $($r1.Code)）"

# ---------- 2) 端到端通话测试 ----------
Write-Host ''
Write-Host '== 2) 端到端 1v1 通话（headless Chromium + 假摄像头）==' -ForegroundColor Cyan
$r2 = Invoke-NodeScript (Join-Path $PSScriptRoot 'e2e_test.js')
$res2 = Get-NodeResult $r2.Lines
if (-not $res2) { Show-NodeOutput $r2.Lines; throw "E2E 测试未输出 RESULT（exit=$($r2.Code)）" }
Show-NodeOutput $r2.Lines
if ($res2.skipped) {
    Write-Host '  [SKIP] 环境未安装 Chromium 系浏览器，已跳过真实通话测试' -ForegroundColor Yellow
} else {
    Show-Checks $res2
}
Assert-True $res2.ok "端到端通话测试存在失败项"
Assert-True ($r2.Code -eq 0) "端到端通话测试退出码应为 0（实际 $($r2.Code)）"

# ---------- 3) 人工体验入口 ----------
Write-Host ''
Write-Host '== 3) 手动体验（真实两路摄像头/两个标签页）==' -ForegroundColor Cyan
Write-Host '  启动信令服务器：'
Write-Host "    node `"$PSScriptRoot\..\server\signal_server.js`" 8613"
Write-Host '  浏览器打开两个标签页（需 http://127.0.0.1 或 https，否则采集会被拒绝）：'
Write-Host '    http://127.0.0.1:8613/?room=demo  和  http://127.0.0.1:8613/?room=demo'
Write-Host '  两端点「加入房间」即可看到对方画面。'

Write-Host ''
Write-Host 'L1-13 WebRTC 实验全部通过。' -ForegroundColor Green
