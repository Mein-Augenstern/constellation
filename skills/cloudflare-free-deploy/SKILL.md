---
name: cloudflare-free-deploy
description: Cloudflare 免费额度部署公网 Web 应用（不买域名）。pages.dev 前端 + trycloudflare 隧道打通 HTTP API 的完整方案，覆盖混合内容约束、CORS 收敛、隧道变址恢复 runbook、域名升级路径。适用于个人项目零成本上线的场景。
---

# cloudflare-free-deploy · Cloudflare 免费额度公网部署（无域名）

## 何时使用

- 个人/小项目要公网可访问的 HTTPS Web 应用，**暂不购买域名**
- 后端只有裸 IP（如 ECS http://1.2.3.4），想借 Cloudflare 免费托管前端 + 打通 API
- 已有域名的情况看文末「升级路径」，不要用本方案的隧道杂技

## 三条硬约束（方案形态的决定因素）

1. **混合内容**：`https://*.pages.dev` 页面里的 fetch 不能调 `http://裸IP`（浏览器直接拦）——前端 HTTPS 就要求 API 也是 HTTPS
2. **Cloudflare 不认裸 IP**：Pages `_redirects` 200 代理 / Worker fetch 都拒绝裸 IP 回源（error 1003）
3. **trycloudflare 快速隧道**：免费无账号，但域名随机、**容器重启即变址**——这是无域名方案的全部代价

## 部署形态（2026-11 invest 实证）

```
浏览器 ──HTTPS──▶ <app>.pages.dev（Cloudflare Pages，静态 SPA）
                    │ fetch 跨域（CORS 精确放行此 origin）
                    ▼
        https://<random>.trycloudflare.com（cloudflared 容器，restart=unless-stopped）
                    ▼
          ECS nginx 127.0.0.1:8081 镜像 vhost（专供隧道）
            ├─ /api/business/ → 本机后端（Host 回写白名单值）
            └─ /api/auth/**   → frps vhost → 另一台机器的网关
备用入口：http://<IP>/（同源 nginx :80，隧道故障兜底）
```

### 关键细节（各踩过一次坑）

- **隧道 vhost 必须独立监听端口**（如 127.0.0.1:8081 + `server_name _`）：隧道 Host 是随机域名，
  不能进后端 HostCheck，也不能抢 :80 默认 server —— 在该 vhost 里 `proxy_set_header Host <白名单值>`
- **cloudflared 用 `--network host`** 直连本机 127.0.0.1 端口，省容器网络一层
- **CORS 收敛**：链路上若有两个组件都加 `Access-Control-Allow-Origin`（如 Spring Gateway + 下游服务），
  重复头浏览器判**非法**直接 fetch 失败——nginx 层 `proxy_hide_header` 全部隐藏后按白名单单份回写。
  注意 nginx `map` 在同机已有他方配置时可能触发 map_hash_bucket_size 冲突，用 `if+set` 替代
- **后端 CORS 白名单双 origin**：`https://<app>.pages.dev` + `http://<IP>`（备用入口），env 注入、缺省不开
- 登录类接口（/api/auth/）加 nginx `limit_req`（如 10r/m burst10 → 429）

## 隧道变址恢复 runbook（重启后域名变了）

```bash
# 1. 取新隧道地址
ssh <host> "docker logs invest-tunnel 2>&1" | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1
# 2. 前端带新基址重建部署（构建期注入方式必须可靠，见 frontend-build-inject-verify 技能）
cd <web>/ && printf 'VITE_API_BASE=<新地址>\n' > .env.production.local \
  && <build> && rm .env.production.local \
  && wrangler pages deploy dist --project-name=<app> --branch=main
# 3. 验证：curl -D - OPTIONS/POST 登录端点（带 Origin 头）→ 200 + 单份 ACAO
```

## 升级路径（买了域名后一次性切换）

1. DNS 全部进同一 Cloudflare zone；`api.<domain>` 用 **命名隧道**（地址稳定）
2. Pages 前端 `_redirects`：`/api/* https://api.<domain>/api/:splat 200`（**同 zone 才能代理**）
   → 全同源，撤销后端 CORS、退役快速隧道与变址 runbook
3. `invest`/`muyi` 等项目共用一个域名做子域，一次购买全家用

## 实证记录

- 2026-11-07 invest 上线 pages.dev + 快速隧道端到端跑通
- 2026-11-08 双入口（Cloudflare 主 + IP 备）+ CORS 收敛 + 登录 405 三连环修复后稳定
  （修复细节见 frontend-build-inject-verify——本方案的唯一高频故障源是前端构建注入）
