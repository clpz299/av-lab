'use strict';
/*
 * e2e_test.js —— 真·端到端通话测试（headless Chromium + 假摄像头）
 *
 * 流程：
 *   1) 起信令服务器
 *   2) 起 headless 浏览器（--use-fake-device-for-media-stream 提供假摄像头/麦克风）
 *   3) 通过 CDP 打开两个标签页，各自 auto=1 自动加入同一房间
 *   4) 轮询页面里的 window.__state，断言：连接建立 + 收到对端轨道 + 有 RTP 字节流动
 *
 * 输出最后一行：RESULT {"ok":...,"skipped":...,"checks":[...]}
 * 退出码：0 通过/跳过；1 失败
 */
const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');
const http = require('http');

const PORT = Number(process.env.E2E_PORT || 8615);
const CDP_PORT = Number(process.env.CDP_PORT || 9337);
const ROOM = 'e2e-room';
const MAX_WAIT_MS = 25000;

const checks = [];
const record = (name, ok, detail = '') => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? '[ok]  ' : '[FAIL]'} ${name}${detail ? '  -- ' + detail : ''}`);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function findBrowser() {
  const candidates = [
    process.env.AVWEB_BROWSER,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Chromium\\Application\\chrome.exe',
  ].filter(Boolean);
  for (const c of candidates) { try { if (fs.existsSync(c)) return c; } catch { /* ignore */ } }
  return null;
}

function request(url, method = 'GET') {
  return new Promise((resolve, reject) => {
    const req = http.request(url, { method, timeout: 5000 }, (res) => {
      let d = ''; res.on('data', (c) => d += c); res.on('end', () => resolve(d));
    });
    req.on('error', reject);
    req.on('timeout', () => reject(new Error('http timeout')));
    req.end();
  });
}

function cdp(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  const ready = new Promise((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('cdp ws error')); });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  };
  return {
    ready,
    send(method, params) {
      return new Promise((resolve) => { const n = ++id; pending.set(n, resolve); ws.send(JSON.stringify({ id: n, method, params })); });
    },
    async evalValue(expr) {
      const r = await this.send('Runtime.evaluate', { expression: expr, returnByValue: true });
      return r.result && r.result.result ? r.result.result.value : undefined;
    },
    close() { ws.close(); },
  };
}

function killTree(pid) {
  try { spawn('taskkill', ['/pid', String(pid), '/T', '/F'], { stdio: 'ignore' }); } catch { /* ignore */ }
}

(async () => {
  const browser = findBrowser();
  if (!browser) {
    console.log('[SKIP] 未找到 Chromium 系浏览器（Chrome/Edge/Chromium），跳过端到端通话测试');
    console.log('      可设置环境变量 AVWEB_BROWSER 指向浏览器可执行文件。');
    console.log('RESULT ' + JSON.stringify({ ok: true, skipped: true, checks: [] }));
    process.exit(0);
  }
  console.log('使用浏览器: ' + browser);

  const udd = path.join(os.tmpdir(), 'avlab-webrtc-' + Date.now());
  const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'signal_server.js'), String(PORT)], { stdio: ['ignore', 'pipe', 'pipe'] });
  let srvReady = false;
  srv.stdout.on('data', (d) => { if (String(d).includes('SIGNAL_READY')) srvReady = true; });
  srv.stderr.on('data', (d) => console.error('[server]', String(d).trim()));

  let br = null;
  const clients = [];
  try {
    for (let i = 0; i < 50 && !srvReady; i++) await sleep(100);
    if (!srvReady) throw new Error('信令服务器未就绪');

    br = spawn(browser, [
      '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
      '--remote-debugging-port=' + CDP_PORT, '--user-data-dir=' + udd,
      '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
      '--autoplay-policy=no-user-gesture-required', '--mute-audio',
      'about:blank',
    ], { stdio: ['ignore', 'ignore', 'ignore'] });

    // 等 DevTools 端点就绪
    let up = false;
    for (let i = 0; i < 60 && !up; i++) {
      await sleep(250);
      try { await request(`http://127.0.0.1:${CDP_PORT}/json/version`); up = true; } catch { /* retry */ }
    }
    if (!up) throw new Error('浏览器 DevTools 端点未就绪');

    const pageUrl = `http://127.0.0.1:${PORT}/?room=${ROOM}&auto=1`;
    for (let i = 0; i < 2; i++) {
      const info = JSON.parse(await request(`http://127.0.0.1:${CDP_PORT}/json/new?${encodeURIComponent('about:blank')}`, 'PUT'));
      const c = cdp(info.webSocketDebuggerUrl);
      await c.ready;
      await c.send('Runtime.enable');
      await c.send('Page.enable');
      await c.send('Page.navigate', { url: pageUrl });
      clients.push(c);
    }
    record('两个标签页已打开并加入同一房间', true, pageUrl);

    const readState = async () => Promise.all(clients.map(async (c) => {
      const s = await c.evalValue('JSON.stringify(window.__state)');
      return s ? JSON.parse(s) : null;
    }));

    let states = [];
    const deadline = Date.now() + MAX_WAIT_MS;
    while (Date.now() < deadline) {
      await sleep(500);
      states = await readState();
      if (states.every((s) => s && s.pc === 'connected' && s.remoteTracks >= 2 && s.bytesReceived > 0)) break;
    }
    console.log('最终状态: ' + JSON.stringify(states));

    const ok = (f) => states.filter((s) => s && f(s)).length;
    record('每端都用 getUserMedia 采集到本地音视频', ok((s) => s.localTracks >= 2) === 2,
      states.map((s) => s && s.localTracks).join(','));
    record('两端 peerConnection 均进入 connected', ok((s) => s.pc === 'connected') === 2,
      states.map((s) => s && s.pc).join(','));
    record('两端 iceConnectionState 均为 connected', ok((s) => s.ice === 'connected') === 2,
      states.map((s) => s && s.ice).join(','));
    record('两端都通过 ontrack 收到对端轨道', ok((s) => s.remoteTracks >= 2) === 2,
      states.map((s) => s && s.remoteTracks).join(','));
    record('远端视频已解码出画面尺寸', ok((s) => s.remoteWidth > 0) === 2,
      states.map((s) => s && `${s.remoteWidth}x${s.remoteHeight}`).join(','));
    record('有真实 RTP 媒体字节流动(不再是"仅信令通了")', ok((s) => s.bytesReceived > 0) === 2,
      states.map((s) => s && s.bytesReceived).join(','));
    record('发起/应答角色分配正确', states.some((s) => s.role === 'offerer') && states.some((s) => s.role === 'answerer'),
      states.map((s) => s && s.role).join(','));
  } catch (e) {
    record('端到端测试异常', false, e.message);
  } finally {
    clients.forEach((c) => c.close());
    if (br) killTree(br.pid);
    srv.kill();
    await sleep(500);
    try { fs.rmSync(udd, { recursive: true, force: true }); } catch { /* ignore */ }
  }

  const ok = checks.every((c) => c.ok);
  console.log('RESULT ' + JSON.stringify({ ok, skipped: false, checks }));
  process.exit(ok ? 0 : 1);
})();
