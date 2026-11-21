'use strict';
/*
 * app.js —— 浏览器端 1v1 通话逻辑（WebRTC 官方 API，无第三方库）
 *
 * 三个核心 API：
 *   getUserMedia()     采集本地摄像头/麦克风
 *   RTCPeerConnection  建立点对点连接、协商编解码、传输 RTP
 *   (信令) WebSocket    交换 SDP 与 ICE 候选 —— WebRTC 规范之外，需要自己实现
 *
 * URL 参数：
 *   ?room=xxx   预填房间号
 *   ?auto=1     打开页面自动加入房间（自动化测试用）
 *   ?stun=1     额外使用公共 STUN 服务器（跨 NAT 时才有意义，局域网/本机不需要）
 */
const params = new URLSearchParams(location.search);

// 供自动化测试读取的运行状态
window.__state = {
  role: 'idle', pc: 'new', ice: 'new',
  localTracks: 0, remoteTracks: 0,
  remoteWidth: 0, remoteHeight: 0, bytesReceived: 0,
  peers: 0, error: '',
};

const $ = (id) => document.getElementById(id);
const localVideo = $('local');
const remoteVideo = $('remote');

let pc = null;
let ws = null;
let localStream = null;
const remoteStream = new MediaStream();
remoteVideo.srcObject = remoteStream;

function log(line) {
  const el = $('log');
  el.textContent += `[${new Date().toLocaleTimeString()}] ${line}\n`;
  el.scrollTop = el.scrollHeight;
}

function setStat(id, value) { $(id).textContent = value; }

function iceServers() {
  return params.get('stun') === '1'
    ? [{ urls: 'stun:stun.l.google.com:19302' }]
    : []; // 本机/局域网用 host 候选即可，不需要 STUN
}

// ---------- 1. 采集 ----------

async function openCamera() {
  if (localStream) return localStream;
  // 注意：getUserMedia 只在「安全上下文」可用 —— https:// 或 http://localhost、http://127.0.0.1
  localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
  localVideo.srcObject = localStream;
  window.__state.localTracks = localStream.getTracks().length;
  log(`采集成功：${localStream.getTracks().map((t) => t.kind).join(', ')}`);
  return localStream;
}

// ---------- 2. 连接 ----------

function createPeerConnection() {
  if (pc) return pc;
  pc = new RTCPeerConnection({ iceServers: iceServers() });
  window.__pc = pc; // 便于在 DevTools 里手动排查

  for (const track of localStream.getTracks()) pc.addTrack(track, localStream);

  // 远端媒体到达：必须自己挂到 <video> 上，WebRTC 不会自动播放
  pc.ontrack = (ev) => {
    remoteStream.addTrack(ev.track);
    window.__state.remoteTracks = remoteStream.getTracks().length;
    log(`收到远端轨道：${ev.track.kind}`);
  };

  // ICE 候选是「边收集边产生」的，每拿到一个就要通过信令发给对方
  pc.onicecandidate = (ev) => {
    if (ev.candidate) signal({ type: 'ice', payload: ev.candidate });
  };
  pc.onicecandidateerror = (ev) => log(`ICE 候选错误：${ev.url || ''} ${ev.errorText || ''}`);

  pc.onconnectionstatechange = () => {
    window.__state.pc = pc.connectionState;
    setStat('s-pc', pc.connectionState);
    log(`connectionState -> ${pc.connectionState}`);
  };
  pc.oniceconnectionstatechange = () => {
    window.__state.ice = pc.iceConnectionState;
    setStat('s-ice', pc.iceConnectionState);
    log(`iceConnectionState -> ${pc.iceConnectionState}`);
  };
  return pc;
}

// ---------- 3. 信令 ----------

function signal(msg) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}

function connectSignal(room) {
  return new Promise((resolve, reject) => {
    const url = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host;
    ws = new WebSocket(url);
    ws.onopen = () => { log(`信令已连接 ${url}`); signal({ type: 'join', room }); resolve(); };
    ws.onerror = () => { window.__state.error = 'sigal server unreachable'; log('信令连接失败（信令服务器没启动？）'); reject(new Error('signal connect failed')); };
    ws.onclose = () => { log('信令已断开'); setStat('s-signal', 'closed'); };
    ws.onmessage = (ev) => onSignal(JSON.parse(ev.data)).catch((e) => log('处理信令出错：' + e.message));
  });
}

async function onSignal(msg) {
  switch (msg.type) {
    case 'joined':
      window.__state.peers = msg.peers;
      setStat('s-signal', `joined (${msg.peers}/2)`);
      log(`已加入房间，当前 ${msg.peers} 人`);
      break;

    case 'ready':
      window.__state.role = msg.initiator ? 'offerer' : 'answerer';
      setStat('s-signal', msg.initiator ? '发起方(offerer)' : '应答方(answerer)');
      await openCamera();
      createPeerConnection();
      if (msg.initiator) {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        signal({ type: 'signal', payload: pc.localDescription });
        log('已发送 offer');
      }
      break;

    case 'signal': {
      await openCamera();
      createPeerConnection();
      await pc.setRemoteDescription(msg.payload);
      log(`收到 ${msg.payload.type}`);
      if (msg.payload.type === 'offer') {
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        signal({ type: 'signal', payload: pc.localDescription });
        log('已发送 answer');
      }
      break;
    }

    case 'ice':
      if (pc) { await pc.addIceCandidate(msg.payload); log('已添加远端 ICE 候选'); }
      break;

    case 'bye':
      window.__state.pc = 'peer left';
      log('对方已离开房间');
      break;

    case 'full':
      window.__state.error = 'room full';
      log('房间已满（1v1 只允许 2 人）');
      break;
  }
}

// ---------- 入口 ----------

async function join() {
  const room = $('room').value.trim();
  if (!room) { log('请填写房间号'); return; }
  $('join').disabled = true;
  $('leave').disabled = false;
  $('role').textContent = '连接中…';
  try {
    await openCamera();
    await connectSignal(room);
  } catch (e) {
    window.__state.error = e.message;
    $('join').disabled = false;
    $('leave').disabled = true;
  }
}

function leave() {
  if (ws) { ws.close(); ws = null; }
  if (pc) { pc.close(); pc = null; }
  if (localStream) { localStream.getTracks().forEach((t) => t.stop()); localStream = null; }
  remoteStream.getTracks().forEach((t) => remoteStream.removeTrack(t));
  localVideo.srcObject = null;
  window.__state = Object.assign(window.__state, { pc: 'closed', ice: 'closed', remoteTracks: 0, role: 'idle' });
  $('join').disabled = false;
  $('leave').disabled = true;
  $('role').textContent = '已离开';
  log('已离开房间');
}

$('join').onclick = join;
$('leave').onclick = leave;

// 每 500ms 刷新统计（便于肉眼确认「真的有多媒体数据在流动」）
setInterval(async () => {
  if (remoteVideo.videoWidth) {
    window.__state.remoteWidth = remoteVideo.videoWidth;
    window.__state.remoteHeight = remoteVideo.videoHeight;
    setStat('s-remote', `${remoteStream.getTracks().length} 条轨道 / ${remoteVideo.videoWidth}x${remoteVideo.videoHeight}`);
  }
  if (!pc) return;
  try {
    const stats = await pc.getStats();
    let bytes = 0;
    stats.forEach((s) => { if (s.type === 'inbound-rtp' && s.bytesReceived) bytes += s.bytesReceived; });
    window.__state.bytesReceived = bytes;
    setStat('s-bytes', bytes.toLocaleString());
  } catch { /* 连接关闭时忽略 */ }
}, 500);

const presetRoom = params.get('room');
if (presetRoom) $('room').value = presetRoom;
if (params.get('auto') === '1') join();
