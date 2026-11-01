---
name: log-driven-verify
description: 日志驱动验证：从运行中的 Docker 容器日志反向推导系统行为是否符合预期（测试视角验收）。适用于任何容器化微服务栈的自动化巡检、故障发现、上线后验收。
---

# log-driven-verify · 日志驱动验证

## 何时使用

- 容器栈部署后/迭代后需要快速验收"功能是否真的在按预期工作"
- 疑似有隐性缺陷但没人报 bug（测试视角主动扫描）
- 需要产出机器可解析的验收报告（PASS/FAIL + 证据行）
- 面试/演示场景：展示"用日志当测试用例"的工程能力

## 核心打法（五步法）

```bash
# Step 1: 全容器日志健康扫描（ERROR/WARN 计数 + 容器状态 + 重启次数）
for c in $(docker ps --format '{{.Names}}'); do
  E=$(docker logs "$c" 2>&1 | grep -cE ' ERROR ')
  W=$(docker logs "$c" 2>&1 | grep -cE ' WARN ')
  R=$(docker inspect "$c" --format '{{.RestartCount}}')
  S=$(docker inspect "$c" --format '{{.State.Status}}')
  echo "$c: status=$S restarts=$R ERROR=$E WARN=$W"
done

# Step 2: 唯一标记请求打点（用不存在的标记让 trace 可追踪）
UNIQ="probe-$(date +%s)"
curl -s -H "X-Trace-Id: $UNIQ" http://<入口>/api/xxx
# 然后在每个服务日志中 grep $UNIQ——能 grep 到=链路通，grep 不到=断点

# Step 3: digest/结构化日志巡检（如果系统有 digest 文件体系）
# 检查每个容器的 digest 文件是否有内容（0 字节=中间件未注册/盲区）
for c in $(docker ps --format '{{.Names}}'); do
  docker exec "$c" sh -c 'ls -la logs/*/ 2>/dev/null | head -10'
done

# Step 4: traceId 跨服务关联断言
# 在网关日志 grep traceId → 下游服务 grep 同 traceId → 断言链路连续
TID=$(docker logs <gateway> 2>&1 | grep -oE '[a-f0-9]{32}' | tail -1)
for svc in <service1> <service2>; do
  C=$(docker logs "$svc" 2>&1 | grep -c "$TID")
  echo "$svc: traceId $TID count=$C"
done

# Step 5: 唯一标记请求打点验证功能路径
# 在每个关键服务日志中 grep 唯一标记——能 grep 到=链路通，grep 不到=断点
```

## 巡检清单（按优先级）

### P1（正确性缺陷——必须修）
| 检查项 | 方法 | 判定 |
|---|---|---|
| 鉴权链路 | 唯一标记登录→访问受限端点→检查 401/200 | 每一步都有日志记录 |
| 路由→存储 | 打点请求→网关日志→服务日志→DB/文件 | traceId 跨服务连续 |
| 中间件注册 | digest 文件全量检查 | **0 字节 = Filter 未注册（盲区）** |
| 优雅停机 vs 故障 | 退出码 + RestartCount + shutdown 日志 | 退出码 0 + restart 0 = 部署行为 |

### P2（可观测性缺陷——应该修）
| 检查项 | 方法 |
|---|---|
| traceId 入口生成 | 网关日志 traceId 段是否非空 |
| 跨语言透传 | Python/Go 等非 Java 服务是否读 X-Trace-Id |
| 慢日志/慢查询 | `SHOW VARIABLES LIKE 'slow_query%'` / 应用层 slow log |
| 服务发现 503 | `grep "Unable to find instance"` 在网关日志 |

### P3（噪音——可以修）
- 探针端点（/actuator/health）是否在打 digest（噪音）
- 重复注册的容器（同名 proxy 占位、测试残留）

## 报告模板

```markdown
## 日志驱动测试报告（<日期>，<栈名>）

### ✅ 功能符合预期（日志实证）
| 断言 | 证据 |

### 🔴 发现的缺陷
| 编号 | 优先级 | 描述 | 证据 | 修法 |

### 建议沉淀为自动化
- 可重复的检查 → 回归脚本
```

## 实战踩坑记录（star-site + invest）

1. **Servlet Filter 在 WebFlux 不生效**：网关是 Netty，`OncePerRequestFilter` 不注册
   → digest 八文件恰在流量入口全 0 字节。修法：写 WebFilter 版（`GatewayDigestWebFilter`）
2. **traceId 只在 Java 段工作**：网关入口不生成、Python invest 无概念
   → 修法：网关入口生成 + Python middleware 读取 X-Trace-Id
3. **容器"Exited(0)"是部署行为非故障**：热更新/restart 退出码 0 + RestartCount 0
   → 测试视角应标注为"预期重启"，不报故障
4. **公网链路 /api/invest/ping 不带 token = 401**：恢复探测须用网关白名单端点
   → 回归脚本判据要用 /api/bench/health（白名单内）

## 与传统测试的区别

| 维度 | 传统测试（pytest/junit） | 日志驱动验证 |
|---|---|---|
| 视角 | 白盒（知道代码怎么写的） | 黑盒（只看运行时行为） |
| 时机 | 开发期/CI | 部署后/生产巡检 |
| 覆盖 | 代码路径 | 全链路真实流量路径 |
| 发现什么 | 功能 bug | 集成缺陷、盲区、配置漂移 |
| 证据 | assert 输出 | 日志原文（grep 可回溯） |
