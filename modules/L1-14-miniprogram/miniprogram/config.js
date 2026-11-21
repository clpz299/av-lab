// config.js —— 推拉流地址集中配置
// 真机联调时只改这里，或用启动参数覆盖：?push=xxx&play=xxx
// 说明：
//   - live-pusher 的 url 只支持 RTMP 协议（rtmp://...）
//   - live-player 的 src 支持 RTMP、HTTP-FLV(http://...)、HLS(https://...)
module.exports = {
  // 推流地址（RTMP），示例占位，需替换为真实可用的 RTMP 地址
  pushUrl: 'rtmp://push.example.com/live/room1',
  // 拉流地址（与推流同源即可），示例占位
  playUrl: 'rtmp://play.example.com/live/room1'
};
