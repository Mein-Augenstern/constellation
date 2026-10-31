---
name: component-update
description: star-site-components 仓库更新闭环。用户说"更新组件、改了组件代码、组件要加功能、组件代码改完了、同步组件变更"等一律触发。编排 component-builder/reviewer/portfolio-sync/link-doctor 四个 skill 的执行顺序，确保每次更新走完全部收尾步骤（测试→审计→镜像同步→CI→backend 回归），不留尾巴。本 skill 是指挥官不是执行者——具体规则在各自 skill 中。
---

# 组件更新闭环（component-update）

> 你改了 star-site-components 的代码，接下来要做什么？
> 本 skill 是指挥官：按序编排四个专项 skill，每步给出完成标准。
> 具体规约不在本 skill——builder 管怎么写、reviewer 管怎么审、
> portfolio-sync 管镜像同步、link-doctor 管链接测活。

## 更新流程（8 步闭环，逐步执行）

### 第 1 步：写代码
- 调用 **component-builder** skill
- 遵循其 10 步建造法 + 第 9.3 步代码写法规约 + 第 9.5 步注释规约
- 新功能须配套测试

### 第 2 步：全量测试
```bash
cd ~/Documents/GitHub/star-site-components && ./mvnw verify
```
- **完成标准**：`BUILD SUCCESS` + 零测试失败
- **注意**：测试数会变化——记住最终数字（后面第 5 步要用）

### 第 3 步：代码审计
- 调用 **component-reviewer** skill
- 对改动涉及的类跑 7 把尺子
- **完成标准**：问题清单清零（或明确记录否决判断）

### 第 4 步：安装 + backend 回归
```bash
cd ~/Documents/GitHub/star-site-components && ./mvnw install -DskipTests -q
cd ~/Documents/GitHub/star-site-backend && mvn clean test -q
```
- **完成标准**：backend 全量测试绿
- **如果改了 API**（包名/方法签名/枚举值）：backend 代码需同步修改后再跑

### 第 5 步：数字同步（portfolio-sync）
- 调用 **portfolio-sync** skill
- 跑 `audit.sh` 获取镜像面差异清单
- **必查数字**：测试数（README/site/Profile 三处）、篇数（如有 MUYI 变化）
- **完成标准**：audit 零 ✗

### 第 6 步：推送组件仓
```bash
cd ~/Documents/GitHub/star-site-components
git add -A && git commit -m "feat/fix/docs: <描述>" && git push origin main
```
- **完成标准**：GitHub Actions CI 绿（`gh run list` 确认）
- **如果 backend 也有改动**：同步推送，确认 backend CI 绿

### 第 7 步：镜像面推送（portfolio-sync 续）
- 更新站点（mein-augenstern.github.io）→ push master
- 更新 Profile README（gh api PUT）
- **完成标准**：portfolio-sync audit 再次全绿 + 线上验证（带 `?v=` 参数绕缓存）

### 第 8 步：链接测活（仅当部署面有变化）
- 调用 **link-doctor** skill
- 跑 `check.sh` 检查变更页面
- **完成标准**：零同源死链

## 快速检查清单（打印版）

```
□ 1. 代码遵循 component-builder 规约
□ 2. mvn verify 全绿（记录测试数 N）
□ 3. component-reviewer 七尺过审
□ 4. mvn install + backend mvn test 绿
□ 5. portfolio-sync audit.sh 零 ✗
□ 6. 组件仓 push + CI 绿
□ 7. 镜像面（site/Profile/README）同步 + 线上验证
□ 8. （如有部署面变化）link-doctor 零死链
□ 9. backend push + CI 绿（如有改动）
□ 10. portfolio-sync 终审计零 ✗
```

## 特殊场景

| 场景 | 追加步骤 |
|---|---|
| **改了 SQL/XML** | 跑 `-Pit` 真库 IT（需 Docker）；检查索引完备性测试仍绿 |
| **改了包名/类名** | backend 全仓 grep 旧名替换；检查 MyBatis XML 命名空间 |
| **加了新组件** | portfolio-sync 公开仓登记核对（新仓需补 Profile 代表作 + 站点卡片） |
| **升版本号** | 全部子 pom 同步 + backend 引用同步 + tag + GitHub Release |
| **改了表结构** | 更新 DDL 脚本 + backend 迁移文件 + internals.md |

## 已知坑（每条都踩过）

| 坑 | 解法 |
|---|---|
| SSH 偶尔断连 | 切 HTTPS 推送；profile README 走 gh api |
| H2 测试互污 | EmbeddedDatabaseBuilder 必须 `.setName()` 显式隔离 |
| Mimosa 拦截 .java 写入 | 只用 Write/Edit 工具写源码；Bash 只做 git 操作 |
| 测试数三处不一致 | portfolio-sync audit.sh 自动核对；手动改时 grep 三个镜像面 |
| README 数字与 mvn verify 不一致 | 以 `mvn verify` 汇总行为权威源，README 是声明口径 |
