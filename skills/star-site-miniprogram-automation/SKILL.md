---
name: star-site-miniprogram-automation
description: 自动化构建并测试 star-site 微信小程序（pnpm 构建 + 微信开发者工具 cli auto + miniprogram-automator）。凡需要在小程序模拟器里验证页面、跑端到端流程、截图给负责人验收、回归打卡/报告/提醒等页面流程时触发；也适用于"帮我在开发者工具里看一眼/跑一下小程序"类请求。
---

# star-site 小程序自动化

构建 → 启动开发者工具自动化端口 → automator 连接 → 操作与截图。整条链路在本机闭环，不需要真机。

**改哪个仓库（2026-10-14 起的分工）**：迭代一律在 **`star-site-app-demo2`**（现役端，报告+复查闭环主线）；`star-site-app`（demo1）与 `star-site-frontend` 已**冻结**，只查不改。

## 1. 构建

```bash
cd ~/develop/star-site-app-demo2
pnpm install --dangerously-allow-all-builds   # pnpm 12 不再读 onlyBuiltDependencies，必须带此旗标
pnpm build:mp-weixin    # 产物在 dist/build/mp-weixin
```

**BASE_URL 注入（最常见坑）**：接口地址来自 `VITE_API_BASE` 环境变量，必须是**局域网 IP**（如 `http://192.168.3.196:9090/api`），不能写 localhost/127.0.0.1——模拟器里的 localhost 指向模拟器自身，不是 Mac。构建前确认 `.env` 或环境变量已注入。demo2 的 storage 前缀是 `star_site_d2_`（与 demo1 隔离）。

## 2. 启动开发者工具（自动化端口）

```bash
/Applications/wechatwebdevtools.app/Contents/MacOS/cli auto \
  --project ~/develop/star-site-app/dist/build/mp-weixin \
  --auto-port 9420
```

前置条件与坑：
- **服务端口被重置（更新/删缓存/换 IDE 版本后）无需 GUI**：彻底退出工具（`pkill -f wechatdevtools`）后 `printf 'y\n' | "/Applications/wechatwebdevtools.app/Contents/MacOS/cli" islogin`——新版 CLI 会自动拉起工具并激活端口（旧版 2.02 无此流程才需手动开 GUI 开关）。成功标志：输出 `{"login":true}`，端口写入 `<数据目录>/<hash>/Default/.ide`。
- IDE 版本与数据目录 hash 绑定（2.01 stable=50a7d…、2.02=d1e876…，`~/Library/Application Support/微信开发者工具/`），换版本=登录态/端口/项目表全部重来。
- 端口被占先 `lsof -ti :9420 | xargs kill -9`；`cli auto` 报 "http port is open" 失败时先重跑上面的 y-授权流。
- 需要登录态：工具首次要用负责人微信扫码登录（GUI 环节留给负责人）。
- **automator 版本锁 0.12.1**（0.13.0/2026-10-15 发布版有连接回归）。

## 3.5 排障速查（2026-10-20 invest 惨案沉淀）

- **白屏 + `getCurrentPages()` 空 + automator `getPageMetaByWebviewId null` 三连锁 = 产物编译错误炸掉 appLaunch**（不是工具坏！）。权威取证：IDE 日志 `~/Library/Application Support/微信开发者工具/<hash>/WeappLog/logs/*.log` 里搜 `msgForConsole`（编译错误的逐字原文），比截图读 Console 可靠。
- **WXSS 不支持 `\XXXX` unicode 转义**：Vue 编译器会把中文类名（`.贪婪`）转成 `.\8d2a\5a6a` → 编译错误 → 上述三连锁。类名一律 ASCII，构建后 grep 反斜杠兜底。
- **appservice 活但模拟器白屏、`page.$()` 挂起** = 基础库 3.17.x 渲染/元素查询回归。切回 3.8.x：改产物里 **`project.private.config.json` 的 `libVersion`**（它才是真开关，优先级盖过 project.config.json），且数据目录 WeappVendor 下要有对应 wxvpkg；改完重启工具验证 `mp.systemInfo().SDKVersion` 真的变了。
- automator 探针模板：`evaluate(() => ({ts: Date.now(), pages: getCurrentPages().map(p=>p.route), storage: wx.getStorageSync('key')}))`——appservice 域自检，不依赖 page 通道。

## 3. automator 连接与操作

npm 依赖 `miniprogram-automator`（可用 `npx` 临时跑）。见 `scripts/example-e2e.js`：

```js
const automator = require('miniprogram-automator')
const miniProgram = await automator.connect({ wsEndpoint: 'ws://127.0.0.1:9420' })
const page = await miniProgram.currentPage()
await miniProgram.navigateTo('/pages/metrics/metrics?type=bp')
await miniProgram.screenshot({ path: '/tmp/shot.png' })   // 截图后用 Read 工具查看
```

常用 API：`currentPage / navigateTo / reLaunch / page.$(selector) / element.tap() / element.attribute()`。
截图是给负责人做视觉验收的默认手段（负责人习惯：改完页面要截图看效果）。

## 4. 验收纪律

- 页面改完必须截图回贴给负责人过目，再提交。
- 测试账号见负责人记忆/口述（不在本仓库写入明文）。
- AI 相关功能（报告识别/解读）依赖后端 LLM_KEY 配置，模拟器联调前确认后端已注入。
