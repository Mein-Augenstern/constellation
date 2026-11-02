---
name: java-service-redeploy
description: Java 微服务安全重新部署（star-site 技能栈专用）：从代码更新到容器重建到验证的完整流程，覆盖 compose build 缓存陷阱、DNS 缓存、预构建 JAR 直跑模式。适用于任何 Spring Boot 微服务的 Docker 重新部署。
---

# java-service-redeploy · Java 微服务安全重新部署

## 何时使用

- Java 代码有更新（新字段/新 Filter/新端点），需要重新部署容器
- 容器行为与代码不一致（跑的是旧镜像）
- compose 重启后服务异常（digest 空/端点 500）

## ⚠️ 最重要的一个教训

**Docker compose 的 `build:` 段会覆盖你手动 build 的同名镜像。**

compose 多阶段源码构建（COPY 源码 → 容器内 mvn package）在依赖缓存不齐时会
**还原到旧的缓存层**——你 `docker build` 的新镜像 tag 被 compose 的
`docker compose up -d --force-recreate` 覆盖回旧代码。

**实证**：GatewayDigestWebFilter 写入代码 → `docker build` → `docker compose up -d --force-recreate`
→ 容器内 digest 文件 0 字节 → 确认 class 文件不在 JAR 中。
**解法**：绕过 compose，直接 `docker run` 预构建 JAR。

## 标准部署流程（6 步）

### Step 1: 本地编译验证

```bash
cd /path/to/repo
export JAVA_HOME="/Applications/IntelliJ IDEA CE.app/Contents/jbr/Contents/Home"
# 构建目标模块及其依赖（-am = also-make）
mvn -q clean install -DskipTests -Dspotless.check.skip=true \
  -pl star-site-common,<目标模块> -am
# 确认 JAR 存在且足够大（fat JAR 通常 >40MB）
find <模块>/target -name "*.jar" ! -name "*sources*" -exec stat -f%z {} \;
```

### Step 2: 创建简单 Dockerfile（预构建 JAR 模式）

```dockerfile
# /tmp/<service>-simple.Dockerfile
FROM eclipse-temurin:21-jre
WORKDIR /app
ENV TZ=Asia/Shanghai JAVA_OPTS=""
COPY <模块>/target/<jar-name>.jar app.jar
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
```

### Step 3: 构建镜像 + 停旧容器 + 启新容器

```bash
# 构建镜像
docker buildx build -f /tmp/<service>-simple.Dockerfile \
  -t star-site/<service>:latest .

# 停旧容器（不用 compose stop——它可能会用 build 段重建）
docker rm -f <container-name>

# 直接 docker run（绕过 compose）
docker run -d --name <container-name> \
  --network docker_default \
  --restart unless-stopped \
  -p <port>:<port> \
  -e SPRING_CLOUD_NACOS_SERVER_ADDR=star-nacos:8848 \
  -e SPRING_CLOUD_NACOS_DISCOVERY_IP=<container-name> \
  -e JWT_SECRET=<从 docker/.env 读取> \
  -e <其他环境变量> \
  -e JAVA_OPTS="-Xmx192m -Xms64m" \
  star-site/<service>:latest
```

### Step 4: 等待启动（Spring Boot 通常 15-25 秒）

```bash
sleep 22
# 检查启动完成
docker logs <container-name> 2>&1 | grep "Started"
```

### Step 5: 健康验证

```bash
# 直连容器
curl -s http://localhost:<port>/actuator/health

# 经网关（验证路由 + Nacos 注册）
curl -s http://localhost:8080/<路由路径>

# 公网（验证 frpc 隧道）
curl -s http://<公网IP>:8080/<路由路径>
```

### Step 6: 确认依赖服务重启（如果网关也换了 IP）

**关键坑**：如果重启的是网关，其 DNS 缓存会指向旧 member/invest IP → 500。
必须同时重启依赖方或至少重启网关：

```bash
docker restart star-platform-gateway  # 清 DNS + LoadBalancer 缓存
```

## 常见陷阱速查表

| 症状 | 根因 | 解法 |
|---|---|---|
| 新代码不生效 | compose build 覆盖预构建镜像 | `docker run` 直跑，不用 compose |
| digest 文件 0 字节 | 容器内 JAR 没有新 Filter | Step 2 的简单 Dockerfile |
| 重启后其他服务 500 | 网关 DNS 缓存旧 IP | `docker restart star-platform-gateway` |
| 网关→member traceId 断 | GlobalFilter mutate 不传播到 Netty | 框架限制，需 GatewayFilterFactory |
| WeChat API 报 converter 错误 | 微信返回 text/plain | `body(String.class)` 后手动 JSON 解析 |
| compose up 报 image not found | pull_policy: never 但 compose 尝试 rebuild | 确认 image tag 存在 |

## 环境变量清单（docker/.env 统一管理）

```bash
# 从现有容器提取（新容器复用）
docker exec <old-container> printenv | grep -E "JWT|WX|INVEST"
```

关键变量（从 docker/.env 读取，不入 git）：
- `JWT_SECRET` — 三端统一（gateway/member/invest 必须一致）
- `WX_MP_APPID` / `WX_MP_SECRET` — 微信小程序
- `INVEST_UPSTREAM` — 网关路由到 invest 的地址
- `INVEST_JWT_SECRET` — invest 的 JWT 密钥（与 JWT_SECRET 一致）

## 与 compose 的关系

| 场景 | 用 compose | 用 docker run |
|---|---|---|
| 首次部署全栈 | ✅（一键起 mysql/redis/nacos） | ❌（繁琐） |
| **更新单个 Java 服务** | ❌（build 覆盖预构建镜像） | ✅（精确控制） |
| 基础设施重启 | ✅（mysql/redis/nacos） | — |
| 网关/member/invest | ❌（必须绕过） | ✅ |

## 实战存档（2026-11-01~02 踩坑实录）

1. GatewayDigestWebFilter 写完 → compose up → digest 空 → 3 次重建才发现 compose build 覆盖
2. member 的 text/plain 修复 → 本机跑 JAR OK → Docker 容器还是旧代码 → 原因同上
3. invest 容器旧镜像（缺 quantity 字段）→ 500 → 需要重建（docker build + docker-serve.sh）
4. 网关重启后 member 500 → DNS 缓存旧 IP → restart 网关恢复
