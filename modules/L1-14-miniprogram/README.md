# L1-14 微信小程序音视频能力初探

## 目标

用微信小程序自带的 **`live-pusher`（推流）** 与 **`live-player`（播放）** 组件，搭一个最小 demo 工程：
在页面上同时摆放「一路推流 + 一路播放」两个组件，并理清小程序音视频的能力边界、权限与域名要求。

> ⚠️ 本模块的「一路推流 + 一路播放」**需要真机 + 真实 appid + 后台类目权限**，无法在本机 CI 自动跑通。
> 自动化测试覆盖到 **工程结构 + 配置契约** 层（见下文「测试实现说明」），真机联调步骤见「实验步骤」。

## 核心概念（脚本实现依据）

| 概念 | 要点 |
|---|---|
| `live-pusher` | 小程序内置推流组件。`url` **只支持 RTMP**（`rtmp://...`）；`mode` 取值 `SD / HD / FHD / RTC` |
| `live-player` | 小程序内置播放组件。`src` 支持 **RTMP / HTTP-FLV(`http://`) / HLS(`https://`)**；`mode` 取值 `live / RTC` |
| 两种组件 mode 枚举不同 | pusher 是 `SD/HD/FHD/RTC`，player 是 `live/RTC`，写错不会报错但行为异常 |
| 类目权限 | 使用 `live-pusher`/`live-player` 需在小程序后台开通对应接口权限，**受服务类目限制**；测试可选「工具 > 视频客服」 |
| 域名校验（`urlCheck`） | 开发者工具项，开启后所有网络请求域名须在后台白名单内，否则报「不在以下 request 合法域名列表中」 |
| 真机 vs 开发者工具 | `live-pusher` 的真机推流能力远强于开发者工具模拟，**以真机为准** |

## 实验步骤

### A. 自动化校验（本机可跑）

```powershell
powershell -NoProfile -File scripts\miniprogram_practice.ps1
```

校验：工程结构完整 → JSON 配置合法 → 组件属性与事件契约 → 推拉流地址协议契约。

### B. 真机联调（必须人工）

1. **准备 appid**：在微信公众平台注册小程序，获取真实 `appid`，替换 `miniprogram/project.config.json` 中的 `touristappid`
2. **开通接口权限**：后台「设置 → 基本设置 → 服务类目」选择「**工具 > 视频客服**」（测试用途，无需资格证），再到「开发 → 接口设置」开通 `live-pusher`/`live-player`
3. **配置域名**：后台「开发 → 开发设置 → 服务器域名」，把推/拉流域名加入白名单
4. **填地址**：把 `miniprogram/config.js` 的 `pushUrl`/`playUrl` 换成真实可用的 RTMP 地址（也可用启动参数 `?push=xxx&play=xxx` 覆盖）
5. **真机预览**：用微信开发者工具「预览」生成二维码，手机扫码进入，观察一路推流 + 一路播放

## 依赖

- 自动化校验：PowerShell（无 ffmpeg / Node 依赖）
- 真机联调：微信开发者工具 + 微信手机客户端 + 真实 appid + 可用 RTMP 服务

## 构建与运行

```powershell
# 仓库根（av-lab）一键构建 + 全量测试
powershell -NoProfile -File tools\build.ps1
```

模块自身无 C/C++ 目标，仅注册一个脚本型测试 `L1-14.miniprogram_practice`。

## 预期输出（实测）

| 项目 | 实测结果 |
|---|---|
| ctest 用例 | `L1-14.miniprogram_practice` **Passed**（0.38 sec） |
| 自动化校验项 | **39 项**（工程结构 + 配置契约）全通过 |
| 解析到的推流地址 | `rtmp://push.example.com/live/room1`（协议校验通过） |
| 解析到的拉流地址 | `rtmp://play.example.com/live/room1`（协议校验通过） |
| 契约报告 | `build/_artifacts/L1-14-miniprogram/contract_report.json` |
| 全量 ctest | **17 / 17 全绿**（含 L1-01 ~ L1-14） |

## 高频命令速查

| 需求 | 命令 |
|---|---|
| 跑本模块校验 | `powershell -NoProfile -File scripts\miniprogram_practice.ps1` |
| 看契约报告 | `Get-Content build\_artifacts\L1-14-miniprogram\contract_report.json` |
| 校验 JSON 合法性 | `Get-Content -Raw miniprogram\app.json \| ConvertFrom-Json` |
| 只跑本模块测试 | `ctest -R L1-14`（需先 `tools\build.ps1` 配好工具链 PATH） |

## 踩坑清单

1. **类目权限未开通**：接口设置里 `live-pusher`/`live-player` 无法开通，通常是服务类目不符；测试可用「工具 > 视频客服」。
2. **`urlCheck` 域名校验拦截**：开发者工具开启了 `urlCheck` 但后台未配域名 → 请求全部失败；联调期可先关 `urlCheck`，上线前务必配白名单。
3. **推流地址协议写错**：`live-pusher.url` 只吃 RTMP，写成 `http://`/`webrtc://` 不生效；`live-player.src` 才支持 RTMP/HTTP-FLV/HLS。
4. **两种 mode 枚举混用**：pusher 是 `SD/HD/FHD/RTC`、player 是 `live/RTC`，混用不报错但表现异常。
5. **开发者工具与真机不一致**：`live-pusher` 在开发者工具里的模拟能力有限，真机表现才是准的。
6. **测试号（`touristappid`）不能真推流**：只能用于开发者工具预览工程结构，真正推拉流必须真实 appid + 类目权限。
7. **事件回调未实现**：`bindstatechange`/`binderror` 绑定了但页面没写对应函数，回调触发时运行时报错。
8. **推拉流地址不同源**：拉流域名与推流域名不是同一路时，可能拉不到流；demo 里两者设为同源。

## 测试实现说明（为什么这么测）

小程序音视频的验证天然分两层：

- **可自动化的「静态/契约层」**——工程能不能被开发者工具正确打开、组件属性写得对不对、地址协议对不对。这些不依赖真机，适合放进 CI，用 PowerShell 做结构校验 + 正则解析组件属性即可，稳定且快。
- **不可自动化的「真机层」**——真实推流/拉流需要 appid、类目权限、手机扫码，本机无微信开发者工具 CLI，无法脚本化。

所以本模块的策略是：**把能自动化的部分（结构 + 契约）做扎实并纳入 ctest，对不能自动化的部分如实列出人工步骤**，避免「假绿」。

## 实测环境

- Windows + PowerShell 5.1
- CMake 4.5.1 / CTest
- 本机未安装微信开发者工具（`C:\Users\Administrator\AppData\Local\微信开发者工具` 仅用户数据缓存，无 IDE/CLI），真机联调需另装
