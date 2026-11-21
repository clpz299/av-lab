'use strict';
/*
 * signal_server.js —— 零依赖的信令服务器（HTTP 静态资源 + WebSocket 信令）
 *
 * 为什么需要信令服务器？
 *   WebRTC 只规定了「两个 peer 之间怎么传媒体」（SRTP/DTLS/ICE），
 *   并没有规定「双方怎么把 SDP 和 ICE 候选交给对方」。这段交换必须由业务自己实现，
 *   最常见做法就是一个 WebSocket 服务：转发 offer / answer / candidate。
 *
 * 本实现不依赖任何 npm 包（Node 内置 http + crypto 手写 RFC6455 帧），
 * 便于在实验环境里一键启动。
 *
 * 用法：
 *   node signal_server.js [port] [webRoot]
 *   环境变量：PORT / WEB_ROOT 亦可
 */
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const PORT = Number(process.argv[2] || process.env.PORT || 8613);
const WEB_ROOT = path.resolve(process.argv[3] || process.env.WEB_ROOT || path.join(__dirname, '..', 'web'));

// room -> [peer, ...]，每个房间最多 2 人（1v1）
const rooms = new Map();

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

// ---------- WebSocket 基础：握手 / 帧编解码 ----------

function acceptKey(key) {
  return crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
}

// 服务端 -> 客户端：服务端发出的帧不加掩码
function encodeFrame(payload, opcode = 0x1) {
  const data = Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload), 'utf8');
  const len = data.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x80 | opcode, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, data]);
}

// 客户端 -> 服务端：客户端帧必须带掩码，需要按 4 字节循环异或解出明文
function createParser(onMessage) {
  let buf = Buffer.alloc(0);
  let fragments = [];
  return (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      const fin = (buf[0] & 0x80) !== 0;
      const opcode = buf[0] & 0x0f;
      const masked = (buf[1] & 0x80) !== 0;
      let len = buf[1] & 0x7f;
      let off = 2;
      if (len === 126) {
        if (buf.length < 4) return;
        len = buf.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (buf.length < 10) return;
        len = Number(buf.readBigUInt64BE(2));
        off = 10;
      }
      let mask = null;
      if (masked) {
        if (buf.length < off + 4) return;
        mask = buf.slice(off, off + 4);
        off += 4;
      }
      if (buf.length < off + len) return;
      const payload = Buffer.from(buf.slice(off, off + len));
      if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      buf = buf.slice(off + len);

      if (opcode === 0x8) { onMessage({ op: 'close' }); return; }
      if (opcode === 0x9) { onMessage({ op: 'ping', payload }); continue; }
      if (opcode === 0xa) { continue; } // pong
      if (opcode === 0x0) {
        fragments.push(payload);
        if (fin) { onMessage({ op: 'text', payload: Buffer.concat(fragments) }); fragments = []; }
        continue;
      }
      if (!fin) { fragments = [payload]; continue; }
      onMessage({ op: 'text', payload });
    }
  };
}

// ---------- HTTP：静态资源 ----------

const server = http.createServer((req, res) => {
  let rel = decodeURIComponent(req.url.split('?')[0]);
  if (rel === '/') rel = '/index.html';
  const file = path.join(WEB_ROOT, path.normalize(rel));
  if (!file.startsWith(WEB_ROOT)) { res.writeHead(403); res.end('forbidden'); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end('404 not found'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
});

// ---------- WebSocket：信令逻辑 ----------

server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${acceptKey(key)}\r\n\r\n`
  );

  const id = crypto.randomBytes(3).toString('hex');
  const peer = { id, socket, room: null };
  const send = (obj) => { if (!socket.destroyed) socket.write(encodeFrame(JSON.stringify(obj))); };

  const parse = createParser((m) => {
    if (m.op === 'close') { leave(); return; }
    if (m.op === 'ping') { socket.write(encodeFrame(m.payload, 0xa)); return; }
    if (m.op !== 'text') return;

    let msg;
    try { msg = JSON.parse(m.payload.toString('utf8')); } catch { return; }

    if (msg.type === 'join') {
      if (typeof msg.room !== 'string' || !msg.room.trim()) { send({ type: 'error', reason: 'empty room' }); return; }
      const list = rooms.get(msg.room) || [];
      if (list.length >= 2) { send({ type: 'full' }); return; }
      list.push(peer);
      peer.room = msg.room;
      rooms.set(msg.room, list);
      send({ type: 'joined', id, room: msg.room, peers: list.length });
      if (list.length === 2) {
        // 约定：后加入者作为 offerer（发起方），先加入者作为 answerer（应答方）
        for (const o of list) o.socket.write(encodeFrame(JSON.stringify({ type: 'ready', initiator: o === peer })));
      }
    } else if (msg.type === 'signal' || msg.type === 'ice') {
      const list = rooms.get(peer.room) || [];
      for (const o of list) {
        if (o !== peer) o.socket.write(encodeFrame(JSON.stringify({ type: msg.type, payload: msg.payload })));
      }
    }
  });

  function leave() {
    const list = rooms.get(peer.room);
    if (list) {
      const i = list.indexOf(peer);
      if (i >= 0) list.splice(i, 1);
      for (const o of list) o.socket.write(encodeFrame(JSON.stringify({ type: 'bye' })));
      if (list.length === 0) rooms.delete(peer.room);
    }
    if (!socket.destroyed) socket.destroy();
  }

  socket.on('data', parse);
  socket.on('close', leave);
  socket.on('error', leave);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`SIGNAL_READY http://127.0.0.1:${PORT}  (webRoot=${WEB_ROOT})`);
});
