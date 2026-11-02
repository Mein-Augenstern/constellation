---
name: wx-miniapp-cicd
description: 微信小程序 CI/CD 全链路：从本地开发到体验版上手机的自动化部署。覆盖 AppID 管理 тест/正式号判别、miniprogram-ci 免 IDE 上传（密钥+IP 白名单）、公网隧道（frpc→Docker）、调试模式域名校验豁免。适用于任何微信小程序项目。
---

# wx-miniapp-cicd · 微信小程序 CI/CD 部署

## 何时使用

- 小程序开发完成后需要部署到体验版（手机扫码可用）
- 需要从命令行自动上传代码（绕开微信开发者工具 GUI）
- 小程序需要访问公网后端（内网穿透/Docker 容器化部署）
- 遇到"测试号无法上传"、"url not in domain list"、"invalid ip" 等平台限制

## 全链路架构（终态）

```
微信手机端（体验版 + 开调试模式）
   │  http://<公网IP>:<port>
   ▼
ECS/公网服务器（frps vhost HTTP 按域名路由）
   │  frp 隧道（auth.token 认证）
   ▼
Mac/开发机（frpc Docker 容器，同 Docker 网络）
   │  容器对容器直连（localIP=容器名）
   ▼
后端容器（FastAPI/Spring Boot，JWT/静态令牌鉴权）
   │
   ▼
MySQL/Redis（Docker 容器，同网络）
```

## 五个关键环节（每环一个坑，逐个击破）

### ① AppID 管理（测试号 vs 正式号）

**坑**：一个项目可能有 2-3 个 AppID 散落在不同文件，测试号不能上传/不能生成体验版。

| 文件 | 优先级 | 说明 |
|---|---|---|
| `src/manifest.json` → `mp-weixin.appid` | **最高（构建时生效）** | uni-app 项目唯一真相源 |
| `project.config.json` → `appid` | 低（IDE 读但不入构建） | 常与 manifest 不一致 |
| `project.private.config.json` | 中（IDE 本地覆盖） | 不入库 |

**判别测试号 vs 正式号**：
- mp 后台 → 开发设置 → 若有「小程序代码上传密钥」区 = **正式号**（测试号没有）
- IDE 缓存 `WeappLocalData/localstorage_*.json` → `appName` 含 `接口测试号` = 测试号
- 正式号 AppID 在微信「公众平台」可搜到，测试号只在「开发者工具」内可见

**修正优先级**：manifest.json > project.private.config.json > project.config.json > IDE 缓存（localstorage json 里 patch）

### ② miniprogram-ci 上传（免 IDE 自动化通道）

**前提**：正式号 + 代码上传密钥 + IP 白名单。

```bash
# 1. mp 后台 → 开发设置 → 小程序代码上传密钥 → 生成 → 下载 private.<appid>.key
# 2. 同页面 IP 白名单 → 编辑 → 填入上传机器的出口 IP（curl ifconfig.me 查）
# 3. 上传脚本：
cat > ci-upload.cjs << 'EOF'
const ci = require('miniprogram-ci');
new ci.Project({
  appid: 'wxYOUR_APPID',
  type: 'miniProgram',
  projectPath: './dist/release/mp-weixin',
  privateKeyPath: '~/Downloads/private.wxYOUR_APPID.key',
  ignores: ['node_modules/**/*'],
});
ci.upload({
  project, version: '1.0.1', desc: '发布描述',
  setting: { es6: true, minify: true },
});
EOF
node ci-upload.cjs
```

**坑**：
- **IP 白名单为空 = CI 通道全禁**（非"无限制"），仅 IDE 工具通道可传
- 报 `invalid ip: <IPv6>` → 加 `NODE_OPTIONS=--dns-result-order=ipv4first` 强制 IPv4 再试
- 密钥文件 ~1.7KB，**不入仓库**（放 ~/Downloads 或 CI Secret）

### ③ 公网隧道（frpc + Docker 容器化）

**坑**：Docker Desktop 的 `--network host` 是 Linux VM 的 host，不是 Mac 宿主。

```toml
# frpc.toml（渲染后挂载，token 不入库）
serverAddr = "<ECS公网IP>"
serverPort = 7000
auth.token = "<token>"

[[proxies]]
name = "app-vhost"
type = "http"
localIP = "<后端容器名>"        # ← 不是 127.0.0.1！容器对容器直连
localPort = 8790
customDomains = ["<ECS公网IP>"]  # 过渡期用 IP 当 Host（无备案域名时）
# hostHeaderRewrite = "127.0.0.1"  # 后端有 Host 白名单时才需要
```

**版本铁律**：frpc 与 frps **严格同版**（跨版本 login success 但 work 连接 EOF）。
**配置持久化**：不要用 mktemp 临时文件（容器 stop/start 后无配置→永久失联），用固定路径渲染。

### ④ 域名校验豁免（体验版必踩）

**坑**：体验版默认强制域名校验，`url not in domain list`。

| 形态 | 域名校验 | 豁免方式 |
|---|---|---|
| 开发版（预览码） | 开发者工具里设 `urlCheck:false` | 自动豁免 |
| **体验版** | **强制** | 手机端开调试模式（胶囊→开发调试→打开调试） |
| 正式版 | 强制 | 必须配置已备案 https 域名（无豁免） |

**IP 直连过渡方案**：`http://<IP>:<port>` + 手机开调试模式（无需备案域名，G2 过渡期方案）。

### ⑤ 体验版页面路径

**坑**：mp 后台设置体验版时"页面路径"默认是旧版的——新版的首页路径必须手动改。

查正确首页：`dist/release/mp-weixin/app.json` → `pages[0]`（如 `pages/overview/overview`）。

## 一键部署清单（新项目从零到手机可用的最短路径）

1. `manifest.json` 填正式号 AppID
2. `pnpm build:mp-weixin` 构建 release 产物
3. mp 后台生成代码上传密钥 + IP 白名单加入口 IP
4. `node ci-upload.cjs` 上传
5. mp 后台 → 版本管理 → 设为体验版 → **改页面路径为新版首页**
6. 手机扫码 → 开调试模式 → 验证

## 故障速查表

| 症状 | 根因 | 解法 |
|---|---|---|
| 上传菜单灰色 | 测试号 AppID / IDE 登录过期 | 换正式号 / 重新扫码 |
| `invalid ip` | IP 白名单空=全禁 | mp 后台加出口 IP |
| `invalid ip: <IPv6>` | IPv6 出口被拒 | `--dns-result-order=ipv4first` |
| `url not in domain list` | 体验版域名校验 | 手机开调试模式 |
| 页面不存在 | 体验版路径是旧版的 | mp 后台改页面路径 |
| frpc login success 但转发 EOF | frpc/frps 跨版本 | 严格同版镜像 |
| Docker `--network host` 连不到宿主 | macOS host=VM | localIP 用容器名 |
| frpc stop/start 后失联 | mktemp 配置被删 | 渲染到持久路径 |
| **wx-login 报 500** | WeChat API 返回 text/plain，RestClient 报 converter 错 | `body(String.class)` 后手动 JSON 解析 |
| **wx-login 报 40029** | code 无效/已消费（auto-recovery 重试用旧 code） | 确保每次 wx.login() 只发一次；真实 code 不能重试 |
| **登录成功但 memberId 变** | mock 通道（WX_MP_SECRET 未配） | 配置真实 AppSecret 走 code2Session |
| **compose up 后新代码不生效** | compose build 覆盖预构建镜像 | docker run 直跑，见 java-service-redeploy skill |

## 实战踩坑存档（invest G2 公网化，2026-11-01~02）

1. **三个 AppID 张冠李戴**：manifest(测试号)/project.config(正式号)/IDE缓存(第三个号)——构建用 manifest 的，IDE 读缓存的，上传走正式号的
2. **IDE 服务端口 CLI 死结**：存储注入无效（IDE 从内存态覆盖）、交互确认是死文案——GUI 自动化（System Events + CGEvent + Vision OCR）是唯一通路
3. **mp 后台自动化**：CGEvent 点击（Swift 合成鼠标）+ Vision OCR（本地文字识别）可完成 生成密钥→确认→下载→IP白名单 全流程零人工
4. **AppSecret 身份确认**：生成 AppSecret 需身份确认（扫码/输入已有 secret），与代码上传密钥流程不同
5. **WeChat API text/plain（2026-11-01）**：`RestClient.body(JsonNode.class)` 抛 `no suitable HttpMessageConverter`——微信返回 Content-Type: text/plain。修法：`body(String.class)` → `ObjectMapper.readTree()`
6. **网关 DNS 缓存旧 member IP（2026-11-01）**：docker run 换了 member 容器 IP，网关 Java 进程 DNS 缓存仍指旧 IP → 500。修法：`docker restart star-platform-gateway`
7. **JWT 密钥三端不一致（2026-11-01）**：gateway 用 compose 默认值(40字节 HS256)、member 用真实值(48字节 HS384)、invest 用第三个值——三端必须统一，否则 401 死循环
