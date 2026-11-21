// live.js —— 页面逻辑：一路推流 + 一路播放
// 组件事件回调里的 code 取值见官方文档；这里只做日志与状态展示，便于真机联调排查。
const config = require('../../config.js');

Page({
  data: {
    pushUrl: config.pushUrl,
    playUrl: config.playUrl,
    lastEvent: ''
  },

  onLoad(query) {
    // 支持用启动参数覆盖地址，方便真机联调时快速切换推拉流地址
    this.setData({
      pushUrl: query.push || config.pushUrl,
      playUrl: query.play || config.playUrl
    });
  },

  // live-pusher：推流状态变化 / 推流错误
  onPushStateChange(e) {
    console.log('[pusher] state', e.detail);
    this.report('push', e.detail);
  },
  onPushError(e) {
    console.error('[pusher] error', e.detail);
    this.report('push-error', e.detail);
  },

  // live-player：播放状态变化 / 播放错误
  onPlayStateChange(e) {
    console.log('[player] state', e.detail);
    this.report('play', e.detail);
  },
  onPlayError(e) {
    console.error('[player] error', e.detail);
    this.report('play-error', e.detail);
  },

  report(stage, detail) {
    const code = detail && detail.code !== undefined ? detail.code : '?';
    this.setData({ lastEvent: stage + ' code=' + code });
  }
});
