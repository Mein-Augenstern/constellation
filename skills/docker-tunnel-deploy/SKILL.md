---
name: docker-tunnel-deploy
description: Docker 容器化 + frp 内网穿透公网部署。适用于 Mac/Linux 开发机上用 Docker 跑全栈、通过 frpc 隧道暴露到公网 ECS 的场景。覆盖容器编排（自愈/网络拓扑）、frpc 配置（版本匹配/Host 路由）、密钥管理（gitignore 分层）。
---

# docker-tunnel-deploy · Docker + frp 隧道公网部署

## 何时使用

- 全栈跑在本地 Mac/Linux（Docker 容器），需要公网可访问
- 有公网 ECS 当门卫（frps），本地 frpc 隧道回连
- 需要容器自愈 + 零人工维护的长期运行

## 架构模式（家庭生产形态）

```
公网用户
  │  http://<ECS_IP>:<vhost_port>
  ▼
ECS（2C2G 门卫）
  ├─ frps（TOML 配置，vhost HTTP 按域名路由）
  └─ 可选 Caddy（HTTPS 终结，备案域名后启用）
       │  frp 隧道（auth.token）
       ▼
本地 Mac（全栈 Docker 容器）
  ├─ frpc 容器（docker_default 网络，同网直连后端容器）
  ├─ 网关容器（如 Spring Cloud Gateway）
  ├─ 后端容器（FastAPI / Spring Boot）
  └─ MySQL / Redis 容器
```

## 核心决策树

### 容器网络选什么？

| 方式 | 适用 | 坑 |
|---|---|---|
| `--network host` + `localIP=127.0.0.1` | Linux 宿主进程 | **macOS 是 VM 回环，连不到宿主** |
| `--network host` + `localIP=host.docker.internal` | macOS 访问宿主进程 | 间接层，不稳 |
| **`--network docker_default` + `localIP=<容器名>`** | **容器对容器（推荐）** | 零间接、最稳 |

### frpc 配置放哪里？

| 方案 | 问题 |
|---|---|
| mktemp 临时文件挂载 | **脚本退出→文件删除→容器 stop/start 后无配置→永久失联** |
| 环境变量 + frp {$VAR} 模板 | 特殊字符（$!@#）在 shell→docker→frp 链路语义不一 |
| **固定路径渲染（logs/frpc.rendered.toml）** | ✅ 推荐：持久 + 0600 + gitignore |

### frp 版本策略

**严格同版**：frpc 与 frps 用同一版本号。跨版本症状：login success + proxy start success + 转发 EOF（数据面协议不兼容）。

国内拉镜像：`docker.m.daocloud.io/snowdreamtech/frpc:<version>`

## 部署脚本模板

```bash
#!/usr/bin/env bash
# docker-serve.sh：双容器（star 模式网关上游 + LAN 模式隧道后端）
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env.dev ]; then
  set -a; source .env.dev; set +a
fi
: "${JWT_SECRET:?缺 JWT_SECRET}"
: "${LAN_TOKEN:?缺 LAN_TOKEN}"

DB_URL="${INVEST_DB_URL:-}"
CONTAINER_DB_URL="${DB_URL//127.0.0.1:3307/<mysql容器名>:3306}"

NET="docker_default"
IMAGE="your-app:latest"

for C in app-star app-lan; do docker rm -f "$C" 2>/dev/null || true; done

# ① star 模式（网关上游）
docker run -d --name app-star --network "$NET" --restart unless-stopped \
  -p 127.0.0.1:8790:8790 \
  -e AUTH_MODE=jwt -e JWT_SECRET \
  -e DB_URL="$CONTAINER_DB_URL" \
  -e HOSTS_EXTRA=app-star,127.0.0.1 \
  "$IMAGE"

# ② LAN 模式（隧道后端，固定令牌）
docker run -d --name app-lan --network "$NET" --restart unless-stopped \
  -e AUTH_MODE=token -e MP_TOKEN="$LAN_TOKEN" \
  -e DB_URL="$CONTAINER_DB_URL" \
  "$IMAGE" \
  uvicorn app:app --host 0.0.0.0 --port 8792

# ③ frpc 隧道
./scripts/frpc-up.sh
```

```bash
#!/usr/bin/env bash
# frpc-up.sh：渲染配置（token 不入库）+ 启动 frpc 容器
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.dev

mkdir -p logs
RENDERED="$(pwd)/logs/frpc.rendered.toml"
sed "s|{\$FRP_TOKEN}|${FRP_TOKEN}|" scripts/frpc.toml > "$RENDERED"
chmod 600 "$RENDERED"

FRPC_IMAGE="docker.m.daocloud.io/snowdreamtech/frpc:<与frps同版>"
docker rm -f my-frpc 2>/dev/null || true
docker run -d --name my-frpc --network docker_default --restart unless-stopped \
  -v "$RENDERED:/etc/frp/frpc.toml:ro" \
  "$FRPC_IMAGE"
```

## 密钥管理（gitignore 分层）

```
.gitignore 条目：
  .env.dev            # 本机密钥/连接串
  logs/               # 运行日志（含 frpc.rendered.toml）
  data/               # 真实数据
  config/*.local.yaml # 本地配置覆盖
```

## 自愈验证（必须做）

```bash
# 容器自愈
docker restart <后端容器> && time curl -m 5 http://<health>  # 应 <10s 恢复

# 隧道重连
docker restart my-frpc && time curl http://<公网>/health     # 应 <5s 恢复

# 断链感知
docker stop my-frpc && curl http://<公网>/health             # 应有明确错误（404/超时）
```

## 已知陷阱

| 陷阱 | 症状 | 解法 |
|---|---|---|
| macOS host 网络 | connection refused | localIP 用容器名（同 Docker 网络） |
| mktemp 配置 | stop/start 后失联 | 渲染到 logs/ 持久路径 |
| frp 跨版本 | login OK 转发 EOF | 镜像严格同版 |
| vhost Host 路由 | 404（IP 直连时） | customDomains=[IP]，后端加 hostHeaderRewrite |
| DNS 重绑定 | host not allowed | 后端 INVEST_HOSTS_EXTRA 放行网关容器名 |
| MySQL 慢日志 OFF | 压测时慢 SQL 不可见 | SET GLOBAL slow_query_log=ON, long_query_time=0.5 |
| **compose build 覆盖预构建镜像** | 新代码不生效 / digest 空 | docker run 直跑，见 java-service-redeploy skill |
| **网关 DNS 缓存旧 IP** | 重启后端后网关 500 | docker restart star-platform-gateway |
| **frpc stop/start 撞 proxy 名** | 60s 内隧道不恢复 | 等 frps 释放（1-2 分钟）或换 proxy name |
| **logback 路径差异** | logs/ vs /app/logs/ | 检查 logback-spring.xml 的 LOG_PATH 变量 |
| **容器间 DNS 短名解析** | star-platform-member 不可达 | 同网络容器名即 DNS，不需要 IP |

## 并行会话协作纪律（2026-11-02 新增）

两个 AI 会话并行操作同一仓库时的规则：
- 提交一律**显式文件名**（禁 `git add -A`），避免误提交对方半成品
- 动手前 `git status --short` 探测对方未提交改动
- 容器重建前先看 `docker ps` 确认当前跑的是谁的版本
- 重建后四端点验证（ping/trades/signals/overview），失败立即回滚
