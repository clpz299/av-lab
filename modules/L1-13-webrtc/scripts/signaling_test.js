'use strict';
/*
 * signaling_test.js —— 信令协议级测试（不依赖浏览器）
 *
 * 用 Node 内置 WebSocket 客户端冒充两个（及以上）终端，
 * 校验信令服务器的房间管理、SDP/ICE 中继、"满员"与"离线"等行为。
 *
 * 输出最后一行：RESULT {"ok":true,"checks":[...]}
 * 退出码：0 全部通过；1 有失败
 */
const { spawn } = require('child_process');
const path = require('path');

const PORT = Number(process.env.SIG_PORT || 8614);
const URL = `ws://127.0.0.1:${PORT}`;
const checks = [];
const record = (name, ok, detail = '') => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? '[ok]  ' : '[FAIL]'} ${name}${detail ? '  -- ' + detail : ''}`);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function mkClient(url) {
  const ws = new WebSocket(url);
  const inbox = [];
  let waiter = null;
  const flush = () => {
    if (!waiter) return;
    const i = inbox.findIndex(waiter.pred);
    if (i >= 0) { const m = inbox.splice(i, 1)[0]; const w = waiter; waiter = null; w.resolve(m); }
  };
  ws.onmessage = (ev) => { inbox.push(JSON.parse(ev.data)); flush(); };
  return {
    ws,
    open: new Promise((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws error')); }),
    send: (o) => ws.send(JSON.stringify(o)),
    wait(pred, ms = 5000) {
      return new Promise((resolve, reject) => {
        waiter = { pred, resolve };
        flush();
        setTimeout(() => { if (waiter) { waiter = null; reject(new Error('timeout waiting message')); } }, ms);
      });
    },
    close: () => ws.close(),
  };
}

const isType = (t) => (m) => m.type === t;

(async () => {
  const srv = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'signal_server.js'), String(PORT)], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let ready = false;
  srv.stdout.on('data', (d) => { if (String(d).includes('SIGNAL_READY')) ready = true; });
  srv.stderr.on('data', (d) => console.error('[server]', String(d).trim()));
  for (let i = 0; i < 40 && !ready; i++) await sleep(100);

  try {
    if (!ready) throw new Error('信令服务器未就绪');

    // 1) 单端加入房间
    const a = mkClient(URL);
    await a.open;
    a.send({ type: 'join', room: 'r1' });
    const joinedA = await a.wait(isType('joined'));
    record('单端加入房间成功', joinedA.peers === 1, `peers=${joinedA.peers}`);

    // 2) 第二端加入 -> 双方都收到 ready，第二端为 offerer
    const b = mkClient(URL);
    await b.open;
    b.send({ type: 'join', room: 'r1' });
    const readyB = await b.wait(isType('ready'));
    const readyA = await a.wait(isType('ready'));
    record('两端到齐后双方都收到 ready', true);
    record('后加入者被指定为发起方(offerer)', readyB.initiator === true && readyA.initiator === false,
      `offerer.initiator=${readyB.initiator} answerer.initiator=${readyA.initiator}`);

    // 3) offer 中继：A -> B
    const offer = { type: 'offer', sdp: 'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n' };
    a.send({ type: 'signal', payload: offer });
    const gotOffer = await b.wait((m) => m.type === 'signal');
    record('offer 被中继到对端', gotOffer.payload && gotOffer.payload.type === 'offer',
      `收到 type=${gotOffer.payload && gotOffer.payload.type}`);

    // 4) answer 中继：B -> A
    b.send({ type: 'signal', payload: { type: 'answer', sdp: 'v=0\r\no=- 2 2 IN IP4 127.0.0.1\r\n' } });
    const gotAnswer = await a.wait((m) => m.type === 'signal');
    record('answer 被中继回发起方', gotAnswer.payload && gotAnswer.payload.type === 'answer');

    // 5) ICE 候选中继
    const cand = { candidate: 'candidate:1 1 udp 2130706431 192.168.1.10 54321 typ host', sdpMid: '0', sdpMLineIndex: 0 };
    a.send({ type: 'ice', payload: cand });
    const gotIce = await b.wait(isType('ice'));
    record('ICE 候选中继成功', gotIce.payload && /typ host/.test(gotIce.payload.candidate),
      gotIce.payload && gotIce.payload.candidate);

    // 6) 1v1 房间满员
    const c = mkClient(URL);
    await c.open;
    c.send({ type: 'join', room: 'r1' });
    const full = await c.wait(isType('full'));
    record('第三人加入 1v1 房间被拒绝(full)', !!full);

    // 7) 一方离开 -> 另一方收到 bye
    b.close();
    const bye = await a.wait(isType('bye'));
    record('对端离开后收到 bye 通知', !!bye);

    a.close();
    c.close();

    // 8) 连不存在的信令服务应失败（常见踩坑：信令服务器没启动）
    const bad = mkClient('ws://127.0.0.1:1');
    let failed = false;
    try { await bad.open; } catch { failed = true; }
    record('信令服务器未启动时连接失败', failed, 'ws://127.0.0.1:1');
  } catch (e) {
    record('未捕获异常', false, e.message);
  } finally {
    srv.kill();
  }

  const ok = checks.every((c) => c.ok);
  console.log('RESULT ' + JSON.stringify({ ok, checks }));
  process.exit(ok ? 0 : 1);
})();
